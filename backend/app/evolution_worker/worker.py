import argparse
import asyncio
import json
import logging
import os
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone

from app.evolution_worker.llm import DeepSeekProvider, LLMProvider, PIPELINE_VERSION, PROMPT_VERSION
from app.evolution_worker.sources import EvolutionSourceProvider, OfficialSourceDiscovery, TrustedUrlProvider
from app.evolution_worker.sources import publication_phase
from app.evolution_worker.validator import validate_batch
from app.evolution_worker.persistence import persist_validated


logger = logging.getLogger('evolution_worker')


def completed_race(path: str, season: int, round_number: int) -> tuple[str, str]:
    with closing(sqlite3.connect(path)) as db:
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


def race_window(path: str, race_id: str) -> tuple[datetime | None, datetime | None]:
    season, round_number = map(int, race_id.split('-'))
    with closing(sqlite3.connect(path)) as db:
        row = db.execute('''SELECT x.scheduled_start,x.actual_end FROM sessions x
            JOIN races r ON r.race_id=x.race_id JOIN seasons s ON s.season_id=r.season_id
            WHERE s.year=? AND r.round=? AND x.session_type='race'
            ORDER BY x.scheduled_start DESC LIMIT 1''', (season, round_number)).fetchone()
    if row is None or not row[0]:
        return None, None
    start = datetime.fromisoformat(row[0].replace('Z', '+00:00'))
    end = datetime.fromisoformat(row[1].replace('Z', '+00:00')) if row[1] else start + timedelta(hours=4)
    return start, end


def race_context(path: str, public_race_id: str) -> dict:
    season, round_number = map(int, public_race_id.split('-'))
    with closing(sqlite3.connect(path)) as db:
        row = db.execute('''SELECT r.display_name,c.canonical_name,c.country,c.city
            FROM races r JOIN seasons y ON y.season_id=r.season_id JOIN circuits c ON c.circuit_id=r.circuit_id
            WHERE y.year=? AND r.round=?''', (season, round_number)).fetchone()
    if row is None:
        raise RuntimeError(f'Unknown race: {public_race_id}')
    return dict(zip(('race_name', 'circuit', 'country', 'city'), row))


async def run_worker(
    race_id: str, urls: list[str], source_provider: EvolutionSourceProvider,
    llm_provider: LLMProvider, race_start: datetime | None = None, race_end: datetime | None = None,
) -> dict:
    logger.info('Race detected: %s', race_id)
    logger.info('Source discovery started')
    collection = await source_provider.collect(race_id, urls)
    collection.documents = [item.model_copy(update={
        'publication_phase': publication_phase(item.published_at, race_start, race_end),
    }) for item in collection.documents]
    logger.info('Source collection completed: found=%d failed=%d duplicate=%d',
                len(collection.documents), len(collection.failures), collection.duplicates_skipped)
    if not collection.documents:
        raise RuntimeError('No readable trusted source was collected; DeepSeek was not called')
    logger.info('DeepSeek request started')
    extracted = await llm_provider.extract_evolution(race_id, collection.documents)
    logger.info('DeepSeek extraction completed')
    raw_results = [item.model_dump(mode='json') for item in extracted.results]
    validated = validate_batch(extracted, collection.documents)
    logger.info('Validation completed: results=%d issues=%d', len(validated.results), len(validated.issues))
    return {
        '_documents': collection.documents,
        '_validated_results': validated.results,
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
            'title': item.title, 'url': str(item.url),
            'published_at': item.published_at.isoformat() if item.published_at else None,
            'publication_phase': item.publication_phase, 'content_hash': item.content_hash,
        } for item in collection.documents],
        'provider_failures': collection.failures,
        'duplicates_skipped': collection.duplicates_skipped,
        'deepseek_raw_results': raw_results,
        'validation_issues': validated.issues,
        'results': [item.model_dump(mode='json') for item in validated.results],
    }


async def execute_evolution(path: str, race_id: str, urls: list[str], *, dry_run: bool = False,
                            source_provider: EvolutionSourceProvider | None = None,
                            llm_provider: LLMProvider | None = None) -> dict:
    """Shared Evolution entry point for CLI and post-race automation."""
    race_start, race_end = race_window(path, race_id)
    output = await run_worker(
        race_id, urls, source_provider or TrustedUrlProvider(),
        llm_provider or DeepSeekProvider(), race_start, race_end,
    )
    documents = output.pop('_documents')
    validated_results = output.pop('_validated_results')
    if not dry_run:
        output['persistence'] = persist_validated(
            path, documents, validated_results, provider=output['model_provider'],
            model=output['model_name'], prompt_version=output['prompt_version'],
            pipeline_version=output['pipeline_version'],
        )
    return output


async def execute_discovered_evolution(path: str, race_id: str) -> dict:
    """Production scheduler entry point; manual URL mode remains in execute_evolution."""
    context = race_context(path, race_id)
    urls = await OfficialSourceDiscovery().discover(race_id=race_id, **context)
    if not urls:
        return {'race_id': race_id, 'sources': [], 'provider_failures': [],
                'discovery': {'urls': [], 'status': 'no_official_source'}}
    output = await execute_evolution(path, race_id, urls)
    output['discovery'] = {'urls': urls, 'status': 'found'}
    return output


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
    logging.basicConfig(level=logging.INFO, format='%(levelname)s %(message)s')
    race_id, race_name = completed_race(args.database, args.season, args.round_number)
    output = asyncio.run(execute_evolution(
        args.database, race_id, args.source_url, dry_run=args.dry_run,
    ))
    output['race_name'] = race_name
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
