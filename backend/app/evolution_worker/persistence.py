"""SQLite persistence and review operations for validated Evolution events."""
import hashlib
import re
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from difflib import SequenceMatcher

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
    'alpine': 'alpine f1 team', 'aston_martin': 'aston martin', 'audi': 'audi',
    'cadillac': 'cadillac f1 team', 'ferrari': 'ferrari', 'haas': 'haas f1 team',
    'mclaren': 'mclaren', 'mercedes': 'mercedes', 'racing_bulls': 'rb f1 team',
    'red_bull': 'red bull', 'sauber': 'sauber', 'williams': 'williams',
}


def _normal(value: str) -> str:
    words = re.sub(r'\W+', ' ', value.casefold()).split()
    return ' '.join(word for word in words if word not in {'a', 'an', 'the', 'additional'})


def _fingerprint(race_id: str, team_id: str, component_id: str, change: str) -> str:
    value = '|'.join((race_id, team_id, component_id, _normal(change)))
    return hashlib.sha256(value.encode()).hexdigest()


def _ensure_components(db: sqlite3.Connection, season_id: str) -> None:
    era_id = f'era_{season_id}'
    db.execute('''INSERT OR IGNORE INTO technical_eras(technical_era_id,name,status)
        VALUES (?,?,'active')''', (era_id, f'{season_id} component taxonomy'))
    for component_id, name in COMPONENTS.items():
        db.execute('''INSERT OR IGNORE INTO car_component_types
            (component_type_id,technical_era_id,canonical_name,status) VALUES (?,?,?,'active')''',
                   (component_id, era_id, name))


def _team_season(db: sqlite3.Connection, season_id: str, team_key: str) -> tuple[str, str] | None:
    canonical = TEAM_NAMES.get(team_key, team_key.replace('_', ' '))
    row = db.execute('''SELECT ts.team_season_id,t.team_id FROM team_seasons ts
        JOIN teams t ON t.team_id=ts.team_id WHERE ts.season_id=?
        AND lower(t.canonical_name)=? ORDER BY t.updated_at DESC LIMIT 1''',
                     (season_id, canonical)).fetchone()
    return tuple(row) if row else None


def _save_documents(db: sqlite3.Connection, documents: list[SourceDocument], internal_race_id: str) -> str:
    snapshot_hash = hashlib.sha256('|'.join(sorted(item.content_hash for item in documents)).encode()).hexdigest()
    row = db.execute('SELECT snapshot_id FROM source_snapshots WHERE content_hash=?', (snapshot_hash,)).fetchone()
    snapshot_id = row[0] if row else new_id('snp')
    if not row:
        db.execute('''INSERT INTO source_snapshots(snapshot_id,created_at,content_hash,source_count)
            VALUES (?,?,?,?)''', (snapshot_id, utc_now(), snapshot_hash, len(documents)))
    for item in documents:
        db.execute('''INSERT OR IGNORE INTO evolution_source_documents
            (source_id,race_id,publisher,source_type,publication_phase,url,published_at,fetched_at,cleaned_text,content_hash)
            VALUES (?,?,?,?,?,?,?,?,?,?)''', (
                item.source_id, internal_race_id, item.publisher, item.source_type,
                item.publication_phase, str(item.url),
                item.published_at.isoformat() if item.published_at else None,
                item.fetched_at.isoformat(), item.cleaned_text, item.content_hash,
            ))
        db.execute('''INSERT OR IGNORE INTO source_snapshot_items
            (snapshot_id,entity_type,entity_id,content_hash) VALUES (?,?,?,?)''',
                   (snapshot_id, 'evolution_source', item.source_id, item.content_hash))
    return snapshot_id


def persist_validated(
    path: str, documents: list[SourceDocument], results: list[EvolutionExtraction], *,
    provider: str, model: str, prompt_version: str, pipeline_version: str,
) -> dict:
    """Persist validated events as pending review; existing published values are immutable."""
    migrate(path)
    now = utc_now()
    inserted = updated = skipped = 0
    with closing(connect(path)) as db, db:
        season, round_number = map(int, documents[0].race_id.split('-'))
        race = db.execute('''SELECT r.race_id,y.season_id FROM races r JOIN seasons y USING(season_id)
            WHERE y.year=? AND r.round=?''', (season, round_number)).fetchone()
        if race is None:
            raise RuntimeError(f'Unknown race: {documents[0].race_id}')
        race_id, season_id = race
        _ensure_components(db, season_id)
        urls = [str(document.url) for document in documents]
        known_urls = set()
        if urls:
            marks = ','.join('?' for _ in urls)
            known_urls = {row[0] for row in db.execute(
                f'SELECT url FROM evolution_source_documents WHERE url IN ({marks})', urls
            )}
        all_sources_previously_seen = len(known_urls) == len(set(urls))
        snapshot_id = _save_documents(db, documents, race_id)
        generation_id = new_id('gen')
        db.execute('''INSERT INTO ai_generations VALUES (?,?,?,?,?,?,?,?)''', (
            generation_id, provider, model, prompt_version, pipeline_version, now,
            snapshot_id, 'validated',
        ))
        for extraction in results:
            team = _team_season(db, season_id, extraction.team_id)
            if team is None:
                skipped += len(extraction.updates)
                continue
            team_season_id, _ = team
            for update in extraction.updates:
                fingerprint = _fingerprint(race_id, extraction.team_id, update.component_id, update.change)
                existing = db.execute('''SELECT upgrade_id,review_status,change_description FROM upgrades
                    WHERE event_fingerprint=?''', (fingerprint,)).fetchone()
                if existing is None:
                    # Similarity only runs inside the same race/team/component, avoiding broad merges.
                    candidates = db.execute('''SELECT upgrade_id,review_status,change_description FROM upgrades
                        WHERE team_season_id=? AND introduced_race_id=? AND component_type_id=?''',
                                            (team_season_id, race_id, update.component_id)).fetchall()
                    existing = next((item for item in candidates if item[2] and
                                     SequenceMatcher(None, _normal(item[2]), _normal(update.change)).ratio() >= .88), None)
                if existing is None:
                    # Model wording can change between runs.  Reuse a prior event only when
                    # its team/component/race and at least one cited source are identical.
                    source_urls = [str(item.url) for item in documents if item.source_id in update.source_ids]
                    if source_urls:
                        marks = ','.join('?' for _ in source_urls)
                        existing = db.execute(f'''SELECT u.upgrade_id,u.review_status,u.change_description
                            FROM upgrades u JOIN evolution_upgrade_sources eus ON eus.upgrade_id=u.upgrade_id
                            JOIN evolution_source_documents d ON d.source_id=eus.source_id
                            WHERE u.team_season_id=? AND u.introduced_race_id=? AND u.component_type_id=?
                            AND d.url IN ({marks}) LIMIT 1''',
                            (team_season_id, race_id, update.component_id, *source_urls)).fetchone()
                if existing is None:
                    # A repeat using only known documents must not let a non-deterministic
                    # model invent a new event.  New documents may still enrich the race.
                    if all_sources_previously_seen:
                        skipped += 1
                        continue
                    upgrade_id = new_id('upg')
                    db.execute('''INSERT INTO upgrades
                        (upgrade_id,team_season_id,car_model_id,introduced_race_id,component_type_id,title,
                        change_description,technical_goal,expected_effect,status,confidence,review_status,event_fingerprint,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', (
                            upgrade_id, team_season_id, None, race_id, update.component_id,
                            f'{COMPONENTS[update.component_id]} update', update.change, update.goal,
                            update.expected_effect, update.status, str(update.confidence), 'pending_review',
                            fingerprint, now, now,
                        ))
                    db.execute('''INSERT INTO review_items
                        (review_id,entity_type,entity_id,issue_type,description,confidence,status,created_at,resolved_at)
                        VALUES (?,?,?,?,?,?,?,?,NULL)''', (
                            new_id('rvw'), 'evolution_upgrade', upgrade_id, 'ai_generated',
                            'Evidence-backed Evolution event requires human review.', str(update.confidence),
                            'pending_review', now,
                        ))
                    inserted += 1
                else:
                    upgrade_id, review_status, _ = existing
                    if review_status != 'published':
                        db.execute('''UPDATE upgrades SET change_description=?,technical_goal=?,expected_effect=?,
                            status=?,confidence=?,updated_at=? WHERE upgrade_id=?''',
                                   (update.change, update.goal, update.expected_effect, update.status,
                                    str(update.confidence), now, upgrade_id))
                        updated += 1
                for source_id in update.source_ids:
                    source = next((item for item in documents if item.source_id == source_id), None)
                    if source is None:
                        continue
                    stored = db.execute('SELECT source_id FROM evolution_source_documents WHERE url=?',
                                        (str(source.url),)).fetchone()
                    source_id = stored[0] if stored else source_id
                    db.execute('''INSERT OR IGNORE INTO evolution_upgrade_sources(upgrade_id,source_id)
                        VALUES (?,?)''', (upgrade_id, source_id))
                    db.execute('''INSERT OR IGNORE INTO upgrade_sources
                        (source_id,upgrade_id,provider,url,published_at,retrieved_at,original_text)
                        VALUES (?,?,?,?,?,?,?)''', (
                            f'ups_{hashlib.sha256((upgrade_id + source_id).encode()).hexdigest()[:24]}',
                            upgrade_id, source.publisher, str(source.url),
                            source.published_at.isoformat() if source.published_at else None,
                            source.fetched_at.isoformat(), source.cleaned_text,
                        ))
                db.execute('''INSERT OR IGNORE INTO upgrade_lifecycle_events
                    (event_id,upgrade_id,race_id,session_id,event_type,timestamp,source)
                    SELECT ?,?,?,NULL,?,?,? WHERE NOT EXISTS (
                        SELECT 1 FROM upgrade_lifecycle_events
                        WHERE upgrade_id=? AND race_id=? AND event_type=? AND source=?
                    )''', (new_id('ule'), upgrade_id, race_id, update.status, now,
                               update.source_ids[0], upgrade_id, race_id, update.status, update.source_ids[0]))
    return {'inserted': inserted, 'updated': updated, 'skipped': skipped, 'generation_id': generation_id}


def review(path: str, action: str, upgrade_id: str | None = None) -> list[dict]:
    migrate(path)
    with closing(connect(path)) as db, db:
        if action == 'list':
            rows = db.execute('''SELECT u.upgrade_id,u.title,u.review_status,u.confidence,r.display_name
                FROM upgrades u LEFT JOIN races r ON r.race_id=u.introduced_race_id
                WHERE u.review_status='pending_review' ORDER BY u.created_at''').fetchall()
            return [dict(zip(('id', 'title', 'status', 'confidence', 'race'), row)) for row in rows]
        if not upgrade_id or action not in {'publish', 'reject'}:
            raise ValueError('Use list, publish EVENT_ID, or reject EVENT_ID')
        status = 'published' if action == 'publish' else 'rejected'
        row = db.execute('SELECT upgrade_id FROM upgrades WHERE upgrade_id=?', (upgrade_id,)).fetchone()
        if row is None:
            raise ValueError('Unknown Evolution event')
        db.execute('UPDATE upgrades SET review_status=?,updated_at=? WHERE upgrade_id=?',
                   (status, utc_now(), upgrade_id))
        db.execute('''UPDATE review_items SET status=?,resolved_at=?
            WHERE entity_type='evolution_upgrade' AND entity_id=?''', (status, utc_now(), upgrade_id))
        return [{'id': upgrade_id, 'status': status}]
