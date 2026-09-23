"""Replay completed races through official discovery, Evolution and model review."""
import argparse
import asyncio
import json

from app.evolution_worker.auto_review import auto_review_race
from app.evolution_worker.worker import completed_race, execute_discovered_evolution


async def one(path: str, season: int, round_number: int, dry_run: bool = False) -> dict:
    race_id = f'{season}-{round_number}'
    try:
        completed_race(path, season, round_number)
        result = await execute_discovered_evolution(path, race_id, dry_run=dry_run)
        reviewed = None if dry_run else await auto_review_race(path, race_id)
        return {'race_id': race_id, 'sources': len(result.get('sources', [])),
                'source_urls': [item['url'] for item in result.get('sources', [])] if dry_run else None,
                'results': result.get('results', []) if dry_run else None,
                'inserted': result.get('persistence', {}).get('inserted', 0),
                'review': reviewed, 'status': result.get('discovery', {}).get('status', 'unknown')}
    except Exception as exc:
        # Keep credentials, provider responses and source text out of batch logs.
        return {'race_id': race_id, 'status': 'failed', 'error_type': type(exc).__name__}


async def run(path: str, season: int, from_round: int, before_round: int,
              dry_run: bool = False) -> None:
    semaphore = asyncio.Semaphore(2)

    async def bounded(round_number: int) -> dict:
        async with semaphore:
            return await one(path, season, round_number, dry_run)

    tasks = [asyncio.create_task(bounded(round_number))
             for round_number in range(from_round, before_round)]
    for task in asyncio.as_completed(tasks):
        print(json.dumps(await task, ensure_ascii=False), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--season', type=int, required=True)
    parser.add_argument('--from-round', type=int, default=1)
    parser.add_argument('--before-round', type=int, required=True)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if not 1 <= args.from_round < args.before_round:
        parser.error('--from-round must be at least 1 and below --before-round')
    asyncio.run(run(args.database, args.season, args.from_round, args.before_round, args.dry_run))


if __name__ == '__main__':
    main()
