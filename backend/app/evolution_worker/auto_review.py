"""Evidence-only model review of pending upgrades; identity and anchors stay unchanged."""
from contextlib import closing

from app.data_schema import connect
from app.evolution_worker.llm import DeepSeekProvider
from app.evolution_worker.persistence import review


def pending_claims(path: str, race_id: str) -> list[dict]:
    season, round_number = map(int, race_id.split('-'))
    with closing(connect(path)) as db:
        rows = db.execute('''SELECT u.upgrade_id,ts.display_name,u.component_type_id,
            u.change_description,u.technical_goal,u.expected_effect,u.status,u.confidence,
            c.claim_id,r.display_name FROM upgrades u
            JOIN upgrade_claims uc ON uc.upgrade_id=u.upgrade_id
            JOIN evolution_claims c ON c.claim_id=uc.claim_id
            JOIN team_seasons ts ON ts.team_season_id=u.team_season_id
            JOIN races r ON r.race_id=u.introduced_race_id
            JOIN seasons s ON s.season_id=r.season_id
            WHERE s.year=? AND r.round=? AND u.review_status='pending_review'
              AND c.review_status='pending_review'
              AND NOT EXISTS (SELECT 1 FROM review_items i
                WHERE i.status='pending_review' AND i.issue_type<>'ai_generated'
                  AND (i.entity_id IN (u.upgrade_id,c.claim_id)
                    OR i.entity_id IN (SELECT event_id FROM upgrade_lifecycle_events
                                       WHERE upgrade_id=u.upgrade_id)))
            ORDER BY u.upgrade_id''', (season, round_number)).fetchall()
        claims = []
        for upgrade_id, team, component, change, goal, effect, status, confidence, claim_id, race_name in rows:
            evidence = [dict(field=field, text=text, source_url=url) for field, text, url in
                        db.execute('''SELECT ce.supports_field,a.anchor_text,d.canonical_url
                            FROM claim_evidence ce JOIN evidence_anchors a USING(anchor_id)
                            JOIN evolution_source_documents d ON d.source_id=a.source_id
                            WHERE ce.claim_id=? ORDER BY d.canonical_url,ce.supports_field''',
                                   (claim_id,)).fetchall()]
            if evidence and any(item['field'] == 'change' for item in evidence):
                claims.append({'event_id': upgrade_id, 'claim_id': claim_id,
                               'race_name': race_name, 'team': team, 'component_id': component,
                               'change': change, 'goal': goal, 'expected_effect': effect,
                               'status': status, 'validator_confidence': float(confidence),
                               'evidence': evidence})
    return claims


def _published_keys(path: str, race_id: str) -> dict[tuple[str, str, str, str], str]:
    season, round_number = map(int, race_id.split('-'))
    with closing(connect(path)) as db:
        rows = db.execute('''SELECT ts.display_name,u.component_type_id,u.change_description,
            u.status,u.upgrade_id FROM upgrades u
            JOIN team_seasons ts ON ts.team_season_id=u.team_season_id
            JOIN races r ON r.race_id=u.introduced_race_id
            JOIN seasons s ON s.season_id=r.season_id
            WHERE s.year=? AND r.round=? AND u.review_status='published' ''',
                          (season, round_number)).fetchall()
    return {(team.casefold(), component, ' '.join(change.casefold().split()), status): upgrade_id
            for team, component, change, status, upgrade_id in rows}


def _published_candidates(path: str, race_id: str, claim: dict) -> list[dict]:
    season, round_number = map(int, race_id.split('-'))
    with closing(connect(path)) as db:
        rows = db.execute('''SELECT u.upgrade_id,u.change_description,u.status FROM upgrades u
            JOIN team_seasons ts ON ts.team_season_id=u.team_season_id
            JOIN races r ON r.race_id=u.introduced_race_id
            JOIN seasons s ON s.season_id=r.season_id
            WHERE s.year=? AND r.round=? AND u.review_status='published'
              AND ts.display_name=? AND u.component_type_id=?
            ORDER BY u.created_at''',
                          (season, round_number, claim['team'], claim['component_id'])).fetchall()
        return [{'event_id': upgrade_id, 'change': change, 'status': status,
                 'evidence': [row[0] for row in db.execute('''SELECT DISTINCT a.anchor_text
                     FROM upgrade_claims uc JOIN claim_evidence ce USING(claim_id)
                     JOIN evidence_anchors a USING(anchor_id)
                     WHERE uc.upgrade_id=? ORDER BY a.anchor_text LIMIT 3''',
                                                          (upgrade_id,)).fetchall()]}
                for upgrade_id, change, status in rows]


def _reject_conflicts(path: str, race_id: str) -> int:
    season, round_number = map(int, race_id.split('-'))
    with closing(connect(path)) as db:
        ids = [row[0] for row in db.execute('''SELECT u.upgrade_id FROM upgrades u
            JOIN races r ON r.race_id=u.introduced_race_id
            JOIN seasons s ON s.season_id=r.season_id
            WHERE s.year=? AND r.round=? AND u.review_status='pending_review'
              AND EXISTS (SELECT 1 FROM review_items i
                WHERE i.status='pending_review' AND i.issue_type<>'ai_generated'
                  AND (i.entity_id IN (SELECT claim_id FROM upgrade_claims
                                       WHERE upgrade_id=u.upgrade_id)
                    OR i.entity_id IN (SELECT event_id FROM upgrade_lifecycle_events
                                       WHERE upgrade_id=u.upgrade_id)))''',
                                     (season, round_number))]
    for upgrade_id in ids:
        review(path, 'reject', upgrade_id)
        with closing(connect(path)) as db, db:
            db.execute('''UPDATE review_items SET status='rejected',resolved_at=CURRENT_TIMESTAMP
                WHERE status='pending_review' AND entity_id IN (
                  SELECT claim_id FROM upgrade_claims WHERE upgrade_id=?
                  UNION SELECT event_id FROM upgrade_lifecycle_events WHERE upgrade_id=?)''',
                       (upgrade_id, upgrade_id))
    return len(ids)


async def auto_review_race(path: str, race_id: str, provider=None) -> dict:
    conflict_rejections = _reject_conflicts(path, race_id)
    claims = pending_claims(path, race_id)
    if not claims:
        return {'reviewed': conflict_rejections, 'published': 0,
                'merged': 0, 'rejected': conflict_rejections, 'pending': 0}
    llm = provider or DeepSeekProvider()
    published = merged = 0
    rejected = conflict_rejections
    known = _published_keys(path, race_id)
    for claim in claims:
        candidates = _published_candidates(path, race_id, claim)
        verdicts = (await llm.review_evolution(
            race_id, [dict(claim, existing_upgrades=candidates)])).verdicts
        verdict = next((item for item in verdicts if item.event_id == claim['event_id']), None)
        if verdict is None:
            continue
        if verdict.supported and verdict.category == 'upgrade':
            key = (claim['team'].casefold(), claim['component_id'],
                   ' '.join(claim['change'].casefold().split()), claim['status'])
            candidate_ids = {item['event_id'] for item in candidates}
            target = (known.get(key) or
                      (verdict.match_event_id if verdict.match_event_id in candidate_ids else None))
            if target:
                review(path, 'merge', claim['claim_id'], target)
                merged += 1
                continue
            confidence = round(min(claim['validator_confidence'], verdict.confidence), 2)
            with closing(connect(path)) as db, db:
                db.execute('''UPDATE upgrades SET confidence=?
                    WHERE upgrade_id=? AND review_status='pending_review' ''',
                           (str(confidence), claim['event_id']))
                db.execute('''UPDATE evolution_claims SET confidence=?
                    WHERE claim_id IN (SELECT claim_id FROM upgrade_claims WHERE upgrade_id=?)
                    AND review_status='pending_review' ''',
                           (str(confidence), claim['event_id']))
            review(path, 'publish', claim['event_id'])
            known[key] = claim['event_id']
            published += 1
        else:
            review(path, 'reject', claim['event_id'])
            rejected += 1
    return {'reviewed': len(claims) + conflict_rejections, 'published': published,
            'merged': merged, 'rejected': rejected,
            'pending': len(claims) - published - (rejected - conflict_rejections) - merged}
