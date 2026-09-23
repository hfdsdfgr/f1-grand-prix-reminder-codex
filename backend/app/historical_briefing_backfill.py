"""One-time, conservative backfill using the existing official discovery and Briefing Worker."""
import argparse
import asyncio
import json
from contextlib import closing
from pathlib import Path

from app.briefing_worker import execute_briefing
from app.data_schema import connect
from app.evolution_worker.sources import (
    OfficialSourceDiscovery, TrustedUrlProvider, eligible_race_day_report,
    publication_phase,
)
from app.evolution_worker.worker import completed_race, race_context, race_window


def eligible_post_race(document, race_name: str, race_start, race_end) -> bool:
    """Exclude ambiguous dates and incidental mentions from historical writeback."""
    title = document.title.casefold()
    url = str(document.url).casefold()
    editorial = any(label in title for label in (
        'race report', 'race day', 'debrief', 'driver quotes', 'driver comments',
        'race reaction', 'post-race', 'post race',
    )) or '/reports/' in url or '/race-report/' in url
    return (document.source_type in {'formula1_official', 'team_official'}
            and race_name.casefold() in title
            and editorial
            and 'preview' not in title
            and publication_phase(document.published_at, race_start, race_end) == 'post_race')


def already_briefed(path: str, season: int, round_number: int) -> bool:
    with closing(connect(path)) as db:
        return db.execute('''SELECT 1 FROM race_briefs b
            JOIN races r ON r.race_id=b.race_id
            JOIN seasons s ON s.season_id=r.season_id
            WHERE s.year=? AND r.round=? LIMIT 1''', (season, round_number)).fetchone() is not None


async def backfill_one(path: str, season: int, round_number: int,
                       supplied: dict[str, list[str]] | None = None,
                       inspect_only: bool = False) -> dict:
    race_id = f'{season}-{round_number}'
    try:
        _, race_name = completed_race(path, season, round_number)
        if already_briefed(path, season, round_number):
            return {'race_id': race_id, 'status': 'existing_brief'}
        race_start, race_end = race_window(path, race_id)
        urls = (supplied.get(race_id, []) if supplied is not None else
                await OfficialSourceDiscovery().discover(
                    race_id=race_id, race_start=race_start, **race_context(path, race_id)))
        if not urls:
            return {'race_id': race_id, 'discovered': 0, 'eligible': 0, 'status': 'no_official_source'}
        collected = await TrustedUrlProvider().collect(race_id, urls)
        eligible = [str(item.url) for item in collected.documents if (
            eligible_race_day_report(item, race_name, season, race_start) if supplied is not None
            else eligible_post_race(item, race_name, race_start, race_end))]
        if not eligible:
            return {'race_id': race_id, 'discovered': len(urls), 'eligible': 0,
                    'fetch_failures': len(collected.failures), 'status': 'no_verified_post_race_source'}
        if inspect_only:
            return {'race_id': race_id, 'eligible': len(eligible), 'urls': eligible,
                    'status': 'verified_source_only'}
        result = await execute_briefing(path, race_id, urls=eligible,
                                        allow_race_day_sources=supplied is not None)
        return {'race_id': race_id, 'discovered': len(urls), 'eligible': len(eligible),
                'urls': eligible, 'fetch_failures': len(collected.failures) + len(result['provider_failures']),
                'facts': result['persistence']['inserted'], 'status': result['persistence']['status']}
    except Exception as exc:
        # DeepSeek credentials and HTTP details must never enter operational logs.
        return {'race_id': race_id, 'status': 'failed', 'error_type': type(exc).__name__}


async def backfill(path: str, season: int, before_round: int,
                   supplied: dict[str, list[str]] | None = None,
                   inspect_only: bool = False) -> None:
    semaphore = asyncio.Semaphore(2)

    async def bounded(round_number: int) -> dict:
        async with semaphore:
            return await backfill_one(path, season, round_number, supplied, inspect_only)

    tasks = [asyncio.create_task(bounded(round_number)) for round_number in range(1, before_round)]
    for task in asyncio.as_completed(tasks):
        print(json.dumps(await task, ensure_ascii=False), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--season', type=int, required=True)
    parser.add_argument('--before-round', type=int, required=True)
    parser.add_argument('--urls-file', type=Path,
                        help='Optional reviewed official race-report URLs for historical replay')
    parser.add_argument('--inspect-only', action='store_true', help='Verify sources without writes or AI calls')
    args = parser.parse_args()
    supplied = json.loads(args.urls_file.read_text(encoding='utf-8')) if args.urls_file else None
    asyncio.run(backfill(args.database, args.season, args.before_round, supplied, args.inspect_only))


if __name__ == '__main__':
    main()
