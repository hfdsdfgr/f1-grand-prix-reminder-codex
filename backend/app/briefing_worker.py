"""Evidence-only race briefing worker backed by the existing briefing tables."""
import hashlib
import json
import sqlite3
from contextlib import closing

from app.data_schema import connect, migrate, new_id, utc_now
from app.evolution_worker.llm import DeepSeekProvider, LLMProvider
from app.evolution_worker.models import BriefingFact, SourceDocument
from app.evolution_worker.sources import OfficialSourceDiscovery, TrustedUrlProvider
from app.evolution_worker.worker import race_context


PIPELINE_VERSION = 'briefing-evidence-v1'
PROMPT_VERSION = 'briefing-evidence-v1'
FIELD_COLUMNS = {
    'race_assessment': 'race_assessment', 'car_strengths': 'car_strengths',
    'car_weaknesses': 'car_weaknesses', 'strategy': 'strategy_issues',
    'tyres': 'tyre_issues', 'technical_issues': 'technical_issues',
    'upgrade_feedback': 'upgrade_feedback', 'incidents': 'incidents',
    'future_expectations': 'next_race_expectations', 'key_quotes': 'key_quotes',
}


def _race(path: str, public_race_id: str) -> str:
    season, round_number = map(int, public_race_id.split('-'))
    with closing(connect(path)) as db:
        row = db.execute('''SELECT r.race_id FROM races r JOIN seasons s USING(season_id)
            WHERE s.year=? AND r.round=?''', (season, round_number)).fetchone()
    if not row:
        raise RuntimeError(f'Unknown race: {public_race_id}')
    return row[0]


def _store_sources(path: str, public_race_id: str, documents: list[SourceDocument]) -> tuple[str, str, dict[str, str]]:
    internal_race_id = _race(path, public_race_id)
    now = utc_now()
    interviews: dict[str, str] = {}
    with closing(connect(path)) as db, db:
        for document in documents:
            interview_id = 'int_' + hashlib.sha256(
                f'{internal_race_id}|{document.url}'.encode()).hexdigest()[:24]
            db.execute('''INSERT INTO interviews
                (interview_id,race_id,source_provider,source_url,published_at,retrieved_at,
                 original_text,status,content_hash) VALUES (?,?,?,?,?,?,?,?,?)
                ON CONFLICT(interview_id) DO UPDATE SET retrieved_at=excluded.retrieved_at,
                original_text=excluded.original_text,content_hash=excluded.content_hash,
                published_at=COALESCE(excluded.published_at,interviews.published_at)''', (
                    interview_id, internal_race_id, document.publisher, str(document.url),
                    document.published_at.isoformat() if document.published_at else None,
                    document.fetched_at.isoformat(), document.cleaned_text, 'source_backed',
                    document.content_hash))
            interviews[document.source_id] = interview_id
        fingerprint = hashlib.sha256('|'.join(sorted(
            f'{interviews[item.source_id]}:{item.content_hash}' for item in documents)).encode()).hexdigest()
        snapshot_id = 'snp_brief_' + fingerprint[:20]
        db.execute('''INSERT INTO source_snapshots(snapshot_id,created_at,content_hash,source_count)
            VALUES (?,?,?,?) ON CONFLICT(content_hash) DO NOTHING''',
                   (snapshot_id, now, fingerprint, len(documents)))
        snapshot_id = db.execute('SELECT snapshot_id FROM source_snapshots WHERE content_hash=?',
                                 (fingerprint,)).fetchone()[0]
        for document in documents:
            db.execute('''INSERT INTO source_snapshot_items(snapshot_id,entity_type,entity_id,content_hash)
                VALUES (?,?,?,?) ON CONFLICT(snapshot_id,entity_type,entity_id) DO NOTHING''',
                       (snapshot_id, 'interview', interviews[document.source_id], document.content_hash))
    return internal_race_id, snapshot_id, interviews


def _existing(path: str, internal_race_id: str, snapshot_id: str) -> bool:
    with closing(connect(path)) as db:
        return db.execute('''SELECT 1 FROM race_briefs b JOIN ai_generations g USING(generation_id)
            WHERE b.race_id=? AND g.source_snapshot_id=? AND g.pipeline_version=?''',
                          (internal_race_id, snapshot_id, PIPELINE_VERSION)).fetchone() is not None


def _validated_facts(facts: list[BriefingFact], documents: list[SourceDocument]) -> list[BriefingFact]:
    texts = {item.source_id: ' '.join(item.cleaned_text.casefold().split()) for item in documents}
    accepted: list[BriefingFact] = []
    fields: set[str] = set()
    for fact in facts:
        if fact.field in fields:
            continue
        evidence = [item for item in fact.evidence if item.source_id in texts and
                    ' '.join(item.quote.casefold().split()) in texts[item.source_id]]
        if evidence:
            accepted.append(fact.model_copy(update={'evidence': evidence}))
            fields.add(fact.field)
    return accepted


def _persist_facts(path: str, internal_race_id: str, snapshot_id: str,
                   interviews: dict[str, str], facts: list[BriefingFact], provider: str,
                   model: str) -> dict:
    if not facts:
        return {'inserted': 0, 'observed': 0, 'status': 'no_supported_facts'}
    now = utc_now()
    with closing(connect(path)) as db, db:
        db.execute('BEGIN IMMEDIATE')
        if db.execute('''SELECT 1 FROM race_briefs b JOIN ai_generations g USING(generation_id)
            WHERE b.race_id=? AND g.source_snapshot_id=? AND g.pipeline_version=?''',
                      (internal_race_id, snapshot_id, PIPELINE_VERSION)).fetchone():
            return {'inserted': 0, 'observed': 0, 'status': 'reused'}
        generation_id = new_id('gen')
        db.execute('INSERT INTO ai_generations VALUES (?,?,?,?,?,?,?,?)', (
            generation_id, provider, model, PROMPT_VERSION, PIPELINE_VERSION, now, snapshot_id, 'validated'))
        brief_id = 'brf_' + hashlib.sha256(f'{internal_race_id}|{snapshot_id}'.encode()).hexdigest()[:24]
        values = {column: None for column in FIELD_COLUMNS.values()}
        for fact in facts:
            values[FIELD_COLUMNS[fact.field]] = fact.value
        db.execute('''INSERT INTO race_briefs
            (race_brief_id,race_id,technical_themes,team_performance,tyre_issues,strategy_issues,
             upgrade_feedback,driver_concerns,next_race_expectations,race_assessment,car_strengths,
             car_weaknesses,technical_issues,incidents,key_quotes,status,generation_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', (
                brief_id, internal_race_id, None, None, values['tyre_issues'], values['strategy_issues'],
                values['upgrade_feedback'], None, values['next_race_expectations'], values['race_assessment'],
                values['car_strengths'], values['car_weaknesses'], values['technical_issues'],
                values['incidents'], values['key_quotes'], 'source_backed', generation_id))
        for fact in facts:
            for evidence in fact.evidence:
                db.execute('''INSERT INTO briefing_evidence VALUES (?,?,?,?)
                    ON CONFLICT(race_brief_id,field,interview_id,quote) DO NOTHING''',
                           (brief_id, fact.field, interviews[evidence.source_id], evidence.quote))
    return {'inserted': len(facts), 'observed': len(facts), 'brief_id': brief_id, 'status': 'created'}


async def execute_briefing(path: str, race_id: str, urls: list[str] | None = None, *,
                           llm_provider: LLMProvider | None = None) -> dict:
    """Run automatic official discovery, or explicit URLs for debug/replay."""
    migrate(path)
    if urls is None:
        urls = await OfficialSourceDiscovery().discover(race_id=race_id, **race_context(path, race_id))
    if not urls:
        return {'race_id': race_id, 'sources': [], 'provider_failures': [],
                'persistence': {'inserted': 0, 'observed': 0, 'status': 'no_official_source'}}
    collection = await TrustedUrlProvider().collect(race_id, urls)
    if not collection.documents:
        return {'race_id': race_id, 'sources': [], 'provider_failures': collection.failures,
                'persistence': {'inserted': 0, 'observed': 0, 'status': 'no_readable_source'}}
    internal_race_id, snapshot_id, interviews = _store_sources(path, race_id, collection.documents)
    if _existing(path, internal_race_id, snapshot_id):
        persistence = {'inserted': 0, 'observed': 0, 'status': 'reused'}
        facts = []
    else:
        provider = llm_provider or DeepSeekProvider()
        extracted = await provider.extract_briefing(race_id, collection.documents)
        facts = _validated_facts(extracted.facts, collection.documents)
        persistence = _persist_facts(path, internal_race_id, snapshot_id, interviews, facts,
                                     'deepseek', provider.model_name)
    return {'race_id': race_id, 'sources': [{'source_id': item.source_id, 'publisher': item.publisher,
            'title': item.title, 'url': str(item.url)} for item in collection.documents],
            'provider_failures': collection.failures, 'facts': [item.model_dump() for item in facts],
            'persistence': persistence}
