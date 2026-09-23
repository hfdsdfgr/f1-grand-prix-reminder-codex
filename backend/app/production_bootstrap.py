"""One-time, repeatable season bootstrap through the existing repositories."""
import argparse
import json
import os
from datetime import datetime, timezone

from app.lifecycle import with_lifecycle
from app.repositories.schedules import ScheduleRepository
from app.results import ResultsRepository


def bootstrap(season: int, database: str, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    races = ScheduleRepository(database).season(season).races
    results = ResultsRepository(database)
    roster = results.roster(season)
    completed = [race for race in races
                 if with_lifecycle(race, now).lifecycle_phase == 'post_race']
    coverage = []
    for race in completed:
        qualifying = results.load(season, race.round, 'qualifying')
        classification = results.load(season, race.round, 'results')
        coverage.append({
            'race_id': race.id,
            'qualifying': len(qualifying.entries),
            'results': len(classification.entries),
        })
    return {'season': season, 'races': len(races), 'drivers': len(roster.entries),
            'completed': coverage}


def main() -> None:
    parser = argparse.ArgumentParser(description='Bootstrap source-backed season data')
    parser.add_argument('--season', type=int, required=True)
    parser.add_argument('--database', default=os.getenv('DATABASE_PATH', 'data/schedules.db'))
    args = parser.parse_args()
    print(json.dumps(bootstrap(args.season, args.database)))


if __name__ == '__main__':
    main()
