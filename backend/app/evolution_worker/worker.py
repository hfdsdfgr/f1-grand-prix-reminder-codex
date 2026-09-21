import argparse
import asyncio
import json
import logging
import os
import sqlite3
from datetime import datetime, timedelta, timezone

from app.evolution_worker.llm import DeepSeekProvider, LLMProvider, PIPELINE_VERSION, PROMPT_VERSION
from app.evolution_worker.sources import EvolutionSourceProvider, TrustedUrlProvider
from app.evolution_worker.validator import validate_batch


logger = logging.getLogger('evolution_worker')


def completed_race(path: str, season: int, round_number: int) -> tuple[str, str]:
    with sqlite3.connect(path) as db:
        row = db.execute('''SELECT r.race_id,r.display_name,s.scheduled_start,s.actual_end,s.status
            FROM races r JOIN seasons y ON y.season_id=r.season_id
            LEFT JOIN sessions s ON s.race_id=r.race_id AND s.session_type='race'
            WHERE y.year=? AND r.round=?''', (season, round_number)).fetchone()
    if row is None:
        raise RuntimeError(f'Race {season}-{round_number} is not present in the local calendar database')
    _, name, scheduled_start, actual_end, status = row
    finished = status == 'completed' or actual_end is not None
    if not finished and scheduled_start:
        start = datetime.fromisoformat(scheduled_start.replace('Z', '+00:00'))
        finished = datetime.now(timezone.utc) >= start + timedelta(hours=4)
    if not finished:
        raise RuntimeError(f'Race {season}-{round_number} is not completed')
    return f'{season}-{round_number}', name


async def run_worker(
    race_id: str, urls: list[str], source_provider: EvolutionSourceProvider,
    llm_provider: LLMProvider,
) -> dict:
    logger.info('Race detected: %s', race_id)
    logger.info('Source discovery started')
    collection = await source_provider.collect(race_id, urls)
    logger.info('Source collection completed: found=%d failed=%d duplicate=%d',
                len(collection.documents), len(collection.failures), collection.duplicates_skipped)
    if not collection.documents:
        raise RuntimeError('No readable trusted source was collected; DeepSeek was not called')
    logger.info('DeepSeek request started')
    extracted = await llm_provider.extract_evolution(race_id, collection.documents)
    logger.info('DeepSeek extraction completed')
    validated = validate_batch(extracted, collection.documents)
    logger.info('Validation completed: results=%d issues=%d', len(validated.results), len(validated.issues))
    return {
        'race_id': race_id,
        'job_status': 'partial' if collection.failures else 'completed',
        'review_status': validated.review_status,
        'model_provider': 'deepseek',
        'model_name': llm_provider.model_name,
        'prompt_version': PROMPT_VERSION,
        'pipeline_version': PIPELINE_VERSION,
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'sources': [{
            'source_id': item.source_id, 'publisher': item.publisher,
            'source_type': item.source_type, 'source_tier': item.source_tier,
            'title': item.title, 'url': str(item.url), 'content_hash': item.content_hash,
        } for item in collection.documents],
        'provider_failures': collection.failures,
        'duplicates_skipped': collection.duplicates_skipped,
        'validation_issues': validated.issues,
        'results': [item.model_dump(mode='json') for item in validated.results],
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description='Extract sourced post-race Evolution data')
    result.add_argument('--season', type=int, required=True)
    result.add_argument('--round', dest='round_number', type=int, required=True)
    result.add_argument('--source-url', action='append', required=True,
                        help='Trusted evidence URL; repeat for more sources (maximum 12)')
    result.add_argument('--database', default=os.getenv('DATABASE_PATH', 'data/schedules.db'))
    result.add_argument('--dry-run', action='store_true')
    return result


def main() -> None:
    args = parser().parse_args()
    if not args.dry_run:
        raise SystemExit('Database writes are intentionally disabled until Phase C acceptance passes; use --dry-run')
    logging.basicConfig(level=logging.INFO, format='%(levelname)s %(message)s')
    race_id, race_name = completed_race(args.database, args.season, args.round_number)
    output = asyncio.run(run_worker(
        race_id, args.source_url, TrustedUrlProvider(), DeepSeekProvider(),
    ))
    output['race_name'] = race_name
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
