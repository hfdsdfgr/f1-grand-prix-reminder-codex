"""Backfill presentation translations; it never creates or changes factual entities."""
from __future__ import annotations

import argparse
import asyncio
from contextlib import closing

from app.data_schema import connect, migrate
from app.evolution_worker.llm import DeepSeekProvider
from app.localization import seed_canonical, upsert_translation


def _items(path: str, public_race_id: str) -> list[dict[str, str]]:
    season, round_number = map(int, public_race_id.split('-'))
    with closing(connect(path)) as db:
        race = db.execute('''SELECT r.race_id FROM races r JOIN seasons s USING(season_id)
            WHERE s.year=? AND r.round=?''', (season, round_number)).fetchone()
        if not race:
            raise RuntimeError(f'Unknown race: {public_race_id}')
        internal_race_id = race[0]
        rows = list(db.execute('''SELECT u.upgrade_id,u.title,u.change_description,u.technical_goal,u.expected_effect
            FROM upgrades u JOIN team_seasons ts USING(team_season_id)
            JOIN seasons s USING(season_id) WHERE s.year=? AND u.introduced_race_id=?
            AND u.review_status='published' ''', (season, internal_race_id)))
        brief = db.execute('''SELECT b.race_brief_id,b.technical_themes,b.team_performance,b.tyre_issues,
            b.strategy_issues,b.upgrade_feedback,b.driver_concerns,b.next_race_expectations,
            b.race_assessment,b.car_strengths,b.car_weaknesses,b.technical_issues,b.incidents,b.key_quotes
            FROM race_briefs b JOIN ai_generations g USING(generation_id)
            WHERE b.race_id=? ORDER BY g.generated_at DESC,b.rowid DESC LIMIT 1''', (internal_race_id,)).fetchone()
    items: list[dict[str, str]] = []
    with closing(connect(path)) as db, db:
        for row in rows:
            values = dict(zip(('title', 'change', 'goal', 'expected_effect'), row[1:]))
            seed_canonical(db, 'upgrade', row[0], values)
            items.extend({'entity_type': 'upgrade', 'entity_id': row[0], 'field': field, 'text': value}
                         for field, value in values.items() if value is not None)
        if brief:
            fields = ('technical_themes', 'team_performance', 'tyres', 'strategy',
                      'upgrade_feedback', 'driver_concerns', 'future_expectations', 'race_assessment',
                      'car_strengths', 'car_weaknesses', 'technical_issues', 'incidents', 'key_quotes')
            values = dict(zip(fields, brief[1:]))
            seed_canonical(db, 'brief_fact', brief[0], values)
            items.extend({'entity_type': 'brief_fact', 'entity_id': brief[0], 'field': field, 'text': value}
                         for field, value in values.items() if value is not None)
    return items


async def localize_race(path: str, race_id: str, *, provider=None) -> dict:
    migrate(path)
    items = _items(path, race_id)
    if not items:
        return {'race_id': race_id, 'candidates': 0, 'stored': 0}
    translated = await (provider or DeepSeekProvider()).localize(items, 'zh-CN')
    allowed = {(item['entity_type'], item['entity_id'], item['field']) for item in items}
    accepted = [item for item in translated if
                (item.get('entity_type'), item.get('entity_id'), item.get('field')) in allowed and
                isinstance(item.get('text'), str) and item['text'].strip() and
                any('\u4e00' <= char <= '\u9fff' for char in item['text'])]
    with closing(connect(path)) as db, db:
        for item in accepted:
            upsert_translation(db, item['entity_type'], item['entity_id'], item['field'],
                               'zh-CN', item['text'].strip())
    return {'race_id': race_id, 'candidates': len(items), 'stored': len(accepted),
            'rejected': len(translated) - len(accepted)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('race_id')
    parser.add_argument('--database', default='data/schedules.db')
    args = parser.parse_args()
    print(asyncio.run(localize_race(args.database, args.race_id)))


if __name__ == '__main__':
    main()
