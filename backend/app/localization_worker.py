"""Backfill presentation translations; it never creates or changes factual entities."""
from __future__ import annotations

import argparse
import asyncio
from contextlib import closing
from unicodedata import combining, normalize

from app.data_schema import connect, migrate
from app.evolution_worker.llm import DeepSeekProvider
from app.localization import seed_canonical, upsert_translation


def _proper_names(path: str) -> list[str]:
    with closing(connect(path)) as db:
        drivers = [row[0] for row in db.execute('SELECT full_name FROM drivers')]
        values = list(drivers)
        for full_name in drivers:
            parts = full_name.split()
            if len(parts) > 1:
                values.extend((parts[0], parts[-1]))
        values.extend(row[0] for row in db.execute('SELECT canonical_name FROM teams'))
        values.extend(row[0] for row in db.execute('SELECT display_name FROM team_seasons'))
        values.extend(row[0] for row in db.execute('SELECT canonical_name FROM circuits'))
    aliases = {value for value in values if value and len(value) >= 3}
    aliases.update(''.join(char for char in normalize('NFKD', value) if not combining(char))
                   for value in tuple(aliases))
    return sorted(aliases, key=len, reverse=True)


def _protect_proper_names(items: list[dict[str, str]], names: list[str]):
    tokens = {f'__PROPER_NAME_{index:03d}__': name for index, name in enumerate(names)}
    protected, required = [], {}
    for item in items:
        copy = dict(item)
        needed = set()
        for token, name in tokens.items():
            if name in copy['text']:
                copy['text'] = copy['text'].replace(name, token)
                needed.add(token)
        key = (copy['entity_type'], copy['entity_id'], copy['field'])
        required[key] = needed
        protected.append(copy)
    return protected, tokens, required


def _restore_proper_names(text: str, tokens: dict[str, str]) -> str:
    for token, name in tokens.items():
        text = text.replace(token, name)
    return text


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


async def localize_race(path: str, race_id: str, *, provider=None,
                        refresh: bool = False) -> dict:
    migrate(path)
    items = _items(path, race_id)
    if not refresh:
        with closing(connect(path)) as db:
            items = [item for item in items if not db.execute('''SELECT 1 FROM content_localizations
                WHERE entity_type=? AND entity_id=? AND field=? AND language='zh-CN' ''',
                (item['entity_type'], item['entity_id'], item['field'])).fetchone()]
    if not items:
        return {'race_id': race_id, 'candidates': 0, 'stored': 0}
    protected, tokens, required = _protect_proper_names(items, _proper_names(path))
    llm = provider or DeepSeekProvider()
    translated = []
    for offset in range(0, len(protected), 6):
        translated.extend(await llm.localize(protected[offset:offset + 6], 'zh-CN'))
    allowed = {(item['entity_type'], item['entity_id'], item['field']) for item in items}
    accepted = []
    for item in translated:
        key = (item.get('entity_type'), item.get('entity_id'), item.get('field'))
        text = item.get('text')
        if (key not in allowed or not isinstance(text, str) or not text.strip() or
                not any('\u4e00' <= char <= '\u9fff' for char in text) or
                not all(token in text for token in required[key])):
            continue
        accepted.append({**item, 'text': _restore_proper_names(text.strip(), tokens)})
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
    parser.add_argument('--refresh', action='store_true',
                        help='Regenerate existing presentation translations for this race only')
    args = parser.parse_args()
    print(asyncio.run(localize_race(args.database, args.race_id, refresh=args.refresh)))


if __name__ == '__main__':
    main()
