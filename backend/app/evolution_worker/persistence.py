"""Deterministic claim persistence and human review for Evolution data."""
import hashlib
import json
import re
import sqlite3
from contextlib import closing

from app.data_schema import connect, migrate, new_id, utc_now
from app.evolution_worker.models import EvolutionExtraction, SourceDocument


COMPONENTS = {
    'front_wing': 'Front wing', 'nose': 'Nose', 'front_suspension': 'Front suspension',
    'front_wheels': 'Front wheels', 'halo': 'Halo', 'cockpit': 'Cockpit',
    'sidepods': 'Sidepods', 'floor': 'Floor', 'engine_cover': 'Engine cover',
    'rear_suspension': 'Rear suspension', 'rear_wheels': 'Rear wheels',
    'beam_wing': 'Beam wing', 'rear_wing': 'Rear wing', 'other': 'Other',
}
TEAM_NAMES = {
    'alpine': 'alpinef1team', 'astonmartin': 'astonmartin', 'astonmartinf1team': 'astonmartin',
    'audi': 'audi', 'cadillac': 'cadillacf1team', 'cadillacf1team': 'cadillacf1team',
    'ferrari': 'ferrari', 'haas': 'haasf1team', 'haasf1team': 'haasf1team',
    'mclaren': 'mclaren', 'mercedes': 'mercedes', 'mercedesamg': 'mercedes',
    'racingbulls': 'rbf1team', 'rb': 'rbf1team', 'redbull': 'redbull',
    'redbullracing': 'redbull', 'sauber': 'sauber', 'williams': 'williams',
}


def _key(value: str) -> str:
    return re.sub(r'[^a-z0-9]+', '', value.casefold())


def _ensure_components(db: sqlite3.Connection, season_id: str) -> None:
    era_id = f'era_{season_id}'
    db.execute("INSERT INTO technical_eras(technical_era_id,name,status) VALUES (?,?,'active') "
               "ON CONFLICT(technical_era_id) DO NOTHING", (era_id, f'{season_id} component taxonomy'))
    for component_id, name in COMPONENTS.items():
        db.execute('''INSERT INTO car_component_types
            (component_type_id,technical_era_id,canonical_name,status) VALUES (?,?,?,'active')
            ON CONFLICT(component_type_id) DO NOTHING''', (component_id, era_id, name))


def _team_season(db: sqlite3.Connection, season_id: str, alias: str,
                 documents: list[SourceDocument]) -> tuple[str, str] | None:
    cited = {_key(team) for document in documents for team in document.team_ids}
    wanted = cited or {_key(alias)}
    wanted |= {TEAM_NAMES.get(item, item) for item in tuple(wanted)}
    rows = db.execute('''SELECT ts.team_season_id,t.team_id,t.canonical_name,ts.display_name
        FROM team_seasons ts JOIN teams t ON t.team_id=ts.team_id WHERE ts.season_id=?''',
                      (season_id,)).fetchall()
    matches = [row for row in rows if wanted & {_key(row[1]), _key(row[2]), _key(row[3])}]
    return (matches[0][0], matches[0][1]) if len(matches) == 1 else None


def _save_documents(db: sqlite3.Connection, documents: list[SourceDocument],
                    internal_race_id: str) -> tuple[str, dict[str, str]]:
    revisions: dict[str, str] = {}
    for item in documents:
        url = str(item.url)
        db.execute('''INSERT INTO evolution_source_documents
            (source_id,canonical_url,publisher,source_type,created_at) VALUES (?,?,?,?,?)
            ON CONFLICT(canonical_url) DO UPDATE SET
                publisher=excluded.publisher,source_type=excluded.source_type''',
                   (item.source_id, url, item.publisher, item.source_type, item.fetched_at.isoformat()))
        source_id = db.execute('SELECT source_id FROM evolution_source_documents WHERE canonical_url=?',
                               (url,)).fetchone()[0]
        revision_id = 'rev_' + hashlib.sha256(
            f'{source_id}|{item.content_hash}'.encode()).hexdigest()[:24]
        db.execute('''INSERT INTO evolution_source_revisions
            (revision_id,source_id,race_id,publication_phase,published_at,fetched_at,cleaned_text,content_hash)
            VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(source_id,content_hash) DO NOTHING''', (
                revision_id, source_id, internal_race_id, item.publication_phase,
                item.published_at.isoformat() if item.published_at else None,
                item.fetched_at.isoformat(), item.cleaned_text, item.content_hash,
            ))
        revisions[item.source_id] = db.execute('''SELECT revision_id FROM evolution_source_revisions
            WHERE source_id=? AND content_hash=?''', (source_id, item.content_hash)).fetchone()[0]
    snapshot_hash = hashlib.sha256('|'.join(sorted(revisions.values())).encode()).hexdigest()
    db.execute('''INSERT INTO source_snapshots(snapshot_id,created_at,content_hash,source_count)
        VALUES (?,?,?,?) ON CONFLICT(content_hash) DO NOTHING''',
               ('snp_' + snapshot_hash[:24], utc_now(), snapshot_hash, len(revisions)))
    snapshot_id = db.execute('SELECT snapshot_id FROM source_snapshots WHERE content_hash=?',
                             (snapshot_hash,)).fetchone()[0]
    for revision_id in revisions.values():
        digest = db.execute('SELECT content_hash FROM evolution_source_revisions WHERE revision_id=?',
                            (revision_id,)).fetchone()[0]
        db.execute('''INSERT INTO source_snapshot_items(snapshot_id,entity_type,entity_id,content_hash)
            VALUES (?,?,?,?) ON CONFLICT(snapshot_id,entity_type,entity_id) DO NOTHING''',
                   (snapshot_id, 'evolution_source_revision', revision_id, digest))
    return snapshot_id, revisions


def _open_review(db: sqlite3.Connection, entity_type: str, entity_id: str,
                 issue_type: str, description: str, confidence: str | None, now: str) -> None:
    db.execute('''INSERT INTO review_items
        (review_id,entity_type,entity_id,issue_type,description,confidence,status,created_at,resolved_at)
        SELECT ?,?,?,?,?,?,'pending_review',?,NULL WHERE NOT EXISTS (
            SELECT 1 FROM review_items WHERE entity_type=? AND entity_id=? AND status='pending_review')''',
               (new_id('rvw'), entity_type, entity_id, issue_type, description, confidence, now,
                entity_type, entity_id))


def persist_validated(path: str, documents: list[SourceDocument], results: list[EvolutionExtraction], *,
                      provider: str, model: str, prompt_version: str,
                      pipeline_version: str) -> dict:
    """Persist evidence claims; model prose never participates in identity."""
    migrate(path)
    now = utc_now()
    inserted = observed = conflicts = skipped = 0
    with closing(connect(path)) as db, db:
        db.execute('BEGIN IMMEDIATE')
        season, round_number = map(int, documents[0].race_id.split('-'))
        race = db.execute('''SELECT r.race_id,y.season_id FROM races r JOIN seasons y USING(season_id)
            WHERE y.year=? AND r.round=?''', (season, round_number)).fetchone()
        if race is None:
            raise RuntimeError(f'Unknown race: {documents[0].race_id}')
        race_id, season_id = race
        _ensure_components(db, season_id)
        snapshot_id, revisions = _save_documents(db, documents, race_id)
        generation_id = new_id('gen')
        db.execute('INSERT INTO ai_generations VALUES (?,?,?,?,?,?,?,?)', (
            generation_id, provider, model, prompt_version, pipeline_version, now,
            snapshot_id, 'validated'))
        source_map = {item.source_id: item for item in documents}
        for extraction in results:
            for update in extraction.updates:
                for anchor in (item for item in update.anchors if 'change' in item.supports):
                    document = source_map.get(anchor.source_id)
                    revision_id = revisions.get(anchor.source_id)
                    if not document or not revision_id:
                        skipped += 1
                        continue
                    team = _team_season(db, season_id, extraction.team_id, [document])
                    if team is None:
                        skipped += 1
                        continue
                    team_season_id, _ = team
                    source_id = db.execute('''SELECT source_id FROM evolution_source_documents
                        WHERE canonical_url=?''', (str(document.url),)).fetchone()[0]
                    db.execute('''INSERT INTO evidence_anchors
                        (anchor_id,source_id,first_revision_id,anchor_text,anchor_hash)
                        VALUES (?,?,?,?,?) ON CONFLICT(anchor_id) DO NOTHING''',
                               (anchor.anchor_id, source_id, revision_id,
                                anchor.anchor_text, anchor.anchor_hash))
                    db.execute('''INSERT INTO evidence_anchor_revisions VALUES (?,?,?,?)
                        ON CONFLICT(anchor_id,revision_id) DO UPDATE SET
                            start_offset=excluded.start_offset,end_offset=excluded.end_offset''',
                               (anchor.anchor_id, revision_id, anchor.start_offset, anchor.end_offset))
                    existing = db.execute('''SELECT claim_id,component_type_id,review_status
                        FROM evolution_claims WHERE race_id=? AND team_season_id=? AND primary_anchor_id=?''',
                                          (race_id, team_season_id, anchor.anchor_id)).fetchone()
                    component_id = update.component_id.value
                    if existing:
                        claim_id, stored_component, _ = existing
                        if stored_component != component_id:
                            conflicts += 1
                            _open_review(db, 'evolution_claim', claim_id, 'component_conflict',
                                         f'Proposed component {component_id}; stored component is {stored_component}.',
                                         str(update.confidence), now)
                    else:
                        claim_key = hashlib.sha256(
                            f'{race_id}|{team_season_id}|{component_id}|{anchor.anchor_id}'.encode()).hexdigest()
                        claim_id = 'clm_' + claim_key[:24]
                        db.execute('''INSERT INTO evolution_claims VALUES
                            (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', (
                                claim_id, claim_key, race_id, team_season_id, component_id,
                                anchor.anchor_id, update.change, update.goal, update.expected_effect,
                                update.status.value, update.evidence_level.value, str(update.confidence),
                                'pending_review', now, now))
                        upgrade_id = new_id('upg')
                        db.execute('''INSERT INTO upgrades
                            (upgrade_id,team_season_id,car_model_id,introduced_race_id,component_type_id,
                            title,change_description,technical_goal,expected_effect,status,confidence,
                            review_status,event_fingerprint,created_at,updated_at)
                            VALUES (?,?,?,?,?,?,?,?,?,?,?,'pending_review',NULL,?,?)''', (
                                upgrade_id, team_season_id, None, race_id, component_id,
                                f'{COMPONENTS[component_id]} update', update.change, update.goal,
                                update.expected_effect, update.status.value, str(update.confidence), now, now))
                        db.execute("INSERT INTO upgrade_claims VALUES (?,?,'pending_review',?,NULL)",
                                   (upgrade_id, claim_id, now))
                        lifecycle_key = hashlib.sha256(f'{upgrade_id}|{claim_key}'.encode()).hexdigest()
                        db.execute('''INSERT INTO upgrade_lifecycle_events
                            (event_id,upgrade_id,race_id,session_id,event_type,timestamp,source,
                            claim_id,lifecycle_claim_key,review_status)
                            VALUES (?,?,?,NULL,?,?,?,?,?,'pending_review')''',
                                   (new_id('ule'), upgrade_id, race_id, update.status.value, now,
                                    anchor.anchor_id, claim_id, lifecycle_key))
                        _open_review(db, 'evolution_upgrade', upgrade_id, 'ai_generated',
                                     'Evidence claim requires human review.', str(update.confidence), now)
                        inserted += 1
                    for field in anchor.supports:
                        db.execute('''INSERT INTO claim_evidence VALUES (?,?,?)
                            ON CONFLICT(claim_id,anchor_id,supports_field) DO NOTHING''',
                                   (claim_id, anchor.anchor_id, field))
                    payload = json.dumps({
                        'change': update.change, 'goal': update.goal,
                        'expected_effect': update.expected_effect, 'status': update.status.value,
                        'component_id': component_id, 'confidence': update.confidence,
                    }, ensure_ascii=False, sort_keys=True)
                    prior_observation = db.execute('''SELECT proposed_json FROM claim_observations
                        WHERE claim_id=? AND generation_id=?''', (claim_id, generation_id)).fetchone()
                    if prior_observation is None:
                        db.execute('''INSERT INTO claim_observations
                            (observation_id,claim_id,generation_id,proposed_json,observed_at)
                            VALUES (?,?,?,?,?)''', (new_id('obs'), claim_id, generation_id, payload, now))
                        observed += 1
                    elif prior_observation[0] != payload:
                        conflicts += 1
                        _open_review(db, 'evolution_claim', claim_id, 'generation_conflict',
                                     'One model generation proposed conflicting values for the same evidence claim.',
                                     str(update.confidence), now)
                    lifecycle = db.execute('''SELECT event_id,event_type FROM upgrade_lifecycle_events
                        WHERE claim_id=? LIMIT 1''', (claim_id,)).fetchone()
                    if lifecycle and lifecycle[1] != update.status.value:
                        conflicts += 1
                        _open_review(db, 'evolution_lifecycle', lifecycle[0],
                                     'interpretation_changed',
                                     f'Proposed {update.status.value}; stored interpretation is {lifecycle[1]}.',
                                     str(update.confidence), now)
    return {'inserted': inserted, 'observed': observed, 'conflicts': conflicts,
            'skipped': skipped, 'generation_id': generation_id}


def review(path: str, action: str, entity_id: str | None = None,
           target_upgrade_id: str | None = None) -> list[dict]:
    migrate(path)
    with closing(connect(path)) as db, db:
        if action == 'list':
            rows = db.execute('''SELECT u.upgrade_id,u.title,u.review_status,u.confidence,r.display_name
                FROM upgrades u LEFT JOIN races r ON r.race_id=u.introduced_race_id
                WHERE u.review_status='pending_review' ORDER BY u.created_at''').fetchall()
            return [dict(zip(('id', 'title', 'status', 'confidence', 'race'), row)) for row in rows]
        if action == 'merge':
            if not entity_id or not target_upgrade_id:
                raise ValueError('Use merge CLAIM_ID TARGET_UPGRADE_ID')
            mapping = db.execute('SELECT upgrade_id FROM upgrade_claims WHERE claim_id=?',
                                 (entity_id,)).fetchone()
            target = db.execute('SELECT review_status FROM upgrades WHERE upgrade_id=?',
                                (target_upgrade_id,)).fetchone()
            if not mapping or not target:
                raise ValueError('Unknown claim or target Upgrade')
            old_upgrade = mapping[0]
            now = utc_now()
            db.execute("UPDATE upgrade_claims SET upgrade_id=?,status='accepted',reviewed_at=? WHERE claim_id=?",
                       (target_upgrade_id, now, entity_id))
            db.execute("UPDATE evolution_claims SET review_status='published',updated_at=? WHERE claim_id=?",
                       (now, entity_id))
            lifecycle = db.execute('''SELECT race_id,event_type,source FROM upgrade_lifecycle_events
                WHERE claim_id=? ORDER BY timestamp LIMIT 1''', (entity_id,)).fetchone()
            if lifecycle:
                key = hashlib.sha256(f'{target_upgrade_id}|{entity_id}'.encode()).hexdigest()
                db.execute('''INSERT INTO upgrade_lifecycle_events
                    (event_id,upgrade_id,race_id,session_id,event_type,timestamp,source,claim_id,
                    lifecycle_claim_key,review_status)
                    SELECT ?,?,?,NULL,?,?,?,?,?,'published' WHERE NOT EXISTS (
                        SELECT 1 FROM upgrade_lifecycle_events
                        WHERE upgrade_id=? AND lifecycle_claim_key=?)''',
                           (new_id('ule'), target_upgrade_id, lifecycle[0], lifecycle[1], now,
                            lifecycle[2], entity_id, key, target_upgrade_id, key))
                db.execute("UPDATE upgrade_lifecycle_events SET review_status='rejected' WHERE claim_id=? AND upgrade_id=?",
                           (entity_id, old_upgrade))
            db.execute("UPDATE upgrades SET review_status='rejected',updated_at=? WHERE upgrade_id=? AND review_status='pending_review'",
                       (now, old_upgrade))
            db.execute("UPDATE review_items SET status='published',resolved_at=? WHERE entity_id IN (?,?) AND status='pending_review'",
                       (now, entity_id, old_upgrade))
            return [{'claim_id': entity_id, 'upgrade_id': target_upgrade_id, 'status': 'accepted'}]
        if not entity_id or action not in {'publish', 'reject'}:
            raise ValueError('Use list, publish EVENT_ID, reject EVENT_ID, or merge CLAIM_ID TARGET_UPGRADE_ID')
        if db.execute('SELECT 1 FROM upgrades WHERE upgrade_id=?', (entity_id,)).fetchone() is None:
            raise ValueError('Unknown Evolution event')
        review_status = 'published' if action == 'publish' else 'rejected'
        mapping_status = 'accepted' if action == 'publish' else 'rejected'
        now = utc_now()
        db.execute('UPDATE upgrades SET review_status=?,updated_at=? WHERE upgrade_id=?',
                   (review_status, now, entity_id))
        db.execute('UPDATE upgrade_claims SET status=?,reviewed_at=? WHERE upgrade_id=?',
                   (mapping_status, now, entity_id))
        db.execute('''UPDATE evolution_claims SET review_status=?,updated_at=? WHERE claim_id IN
            (SELECT claim_id FROM upgrade_claims WHERE upgrade_id=?)''', (review_status, now, entity_id))
        db.execute('UPDATE upgrade_lifecycle_events SET review_status=? WHERE upgrade_id=?',
                   (review_status, entity_id))
        db.execute('''UPDATE review_items SET status=?,resolved_at=?
            WHERE entity_type='evolution_upgrade' AND entity_id=? AND status='pending_review' ''',
                   (review_status, now, entity_id))
        return [{'id': entity_id, 'status': review_status}]
