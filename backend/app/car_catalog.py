"""Fetch current-season chassis names from official Formula1.com team profiles."""
from __future__ import annotations

import argparse
import asyncio
import json
import re
from contextlib import closing
from urllib.parse import urlsplit

from app.data_schema import connect, migrate
from app.evolution_worker.sources import TrustedUrlProvider


TEAM_PROFILES = {
    'alpine': 'alpine',
    'alpinef1team': 'alpine',
    'astonmartin': 'aston-martin',
    'audi': 'audi',
    'cadillac': 'cadillac',
    'cadillacf1team': 'cadillac',
    'ferrari': 'ferrari',
    'haas': 'haas',
    'haasf1team': 'haas',
    'mclaren': 'mclaren',
    'mercedes': 'mercedes',
    'rbf1team': 'racing-bulls',
    'racingbulls': 'racing-bulls',
    'redbull': 'red-bull-racing',
    'redbullracing': 'red-bull-racing',
    'williams': 'williams',
}


def _key(value: str) -> str:
    return re.sub(r'[^a-z0-9]+', '', value.casefold())


def team_profile_url(name: str) -> str | None:
    slug = TEAM_PROFILES.get(_key(name))
    return f'https://www.formula1.com/en/teams/{slug}' if slug else None


def chassis_name(text: str) -> str | None:
    # Formula1.com renders adjacent profile labels without whitespace after HTML
    # cleaning (for example ``ChassisMCL40Power UnitMercedes``).
    match = re.search(r'Chassis\s*([A-Z][A-Z0-9 -]{1,20}?)\s*Power\s*Unit', text, re.I)
    return re.sub(r'\s+', ' ', match.group(1)).strip() if match else None


def _store(path: str, season: int, cars: dict[str, tuple[str, str]]) -> list[dict]:
    stored = []
    with closing(connect(path)) as db, db:
        rows = db.execute('''SELECT ts.team_season_id,ts.display_name,s.season_id,
            (SELECT COUNT(*) FROM upgrades u WHERE u.team_season_id=ts.team_season_id) AS usage
            FROM team_seasons ts JOIN seasons s USING(season_id) WHERE s.year=?
            ORDER BY usage DESC,ts.team_season_id''',
                          (season,)).fetchall()
        model_written = set()
        for team_season_id, team, season_id, _ in rows:
            slug = TEAM_PROFILES.get(_key(team))
            if not slug or slug not in cars:
                continue
            name, source_url = cars[slug]
            car_model_id = f'car_{season}_{slug.replace("-", "_")}'
            db.execute('UPDATE team_seasons SET car_name=? WHERE team_season_id=?',
                       (name, team_season_id))
            if slug in model_written:
                continue
            db.execute('''INSERT INTO car_models
                (car_model_id,team_season_id,name,season_id,base_3d_model_id,status)
                VALUES (?,?,?,?,NULL,'active') ON CONFLICT(car_model_id) DO UPDATE SET
                team_season_id=excluded.team_season_id,name=excluded.name,
                season_id=excluded.season_id,status='active' ''',
                       (car_model_id, team_season_id, name, season_id))
            stored.append({'team': team, 'car_name': name, 'source_url': source_url})
            model_written.add(slug)
    return stored


async def sync_car_catalog(path: str, season: int, *, provider=None) -> dict:
    migrate(path)
    with closing(connect(path)) as db:
        teams = [row[0] for row in db.execute('''SELECT ts.display_name FROM team_seasons ts
            JOIN seasons s USING(season_id) WHERE s.year=? ORDER BY ts.display_name''', (season,))]
    urls = list(dict.fromkeys(
        url for team in teams if (url := team_profile_url(team))
    ))
    collection = await (provider or TrustedUrlProvider()).collect(f'{season}-catalog', urls)
    cars = {}
    for document in collection.documents:
        slug = urlsplit(str(document.url)).path.rstrip('/').rsplit('/', 1)[-1]
        name = chassis_name(document.cleaned_text)
        if slug in TEAM_PROFILES.values() and name:
            cars[slug] = (name, str(document.url))
    stored = _store(path, season, cars)
    return {'season': season, 'requested': len(urls), 'stored': len(stored),
            'cars': stored, 'failures': collection.failures}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('season', type=int)
    parser.add_argument('--database', default='data/schedules.db')
    args = parser.parse_args()
    print(json.dumps(asyncio.run(sync_car_catalog(args.database, args.season)),
                     ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
