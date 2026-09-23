import json
import hashlib
import os
import socket
import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

import httpx

from app.evolution_worker.llm import DeepSeekProvider, ReviewBatch, _validated_response
from app.evolution_worker.auto_review import auto_review_race
from app.evolution_worker.models import ExtractionBatch, SourceDocument, UpgradeStatus
from app.evolution_worker.sources import (
    OfficialSourceDiscovery, TrustedUrlProvider, canonical_url, clean_html, deduplicate, publication_phase,
    published_at_from_html, validate_public_url,
)
from app.evolution_worker.validator import validate_batch
from app.evolution_worker.persistence import persist_validated, review
from app.evolution_worker.worker import execute_discovered_evolution, race_window, run_worker
from app.data_schema import connect
from app.evolution import load_evolution
from app.models import RaceFeed
from app.providers.jolpica import normalize
from app.repositories.schedules import ScheduleRepository
from test_schedules import sample


def public_resolver(host, port):
    return [(socket.AF_INET, socket.SOCK_STREAM, 6, '', ('93.184.216.34', port))]


def source(source_id='src_one', text='The team tested a revised floor geometry during FP1.',
           url=None, team_ids=None):
    return SourceDocument(
        source_id=source_id, race_id='2026-1', publisher='formula1.com',
        source_type='formula1_official', source_tier=2, title='Technical update',
        url=url or f'https://www.formula1.com/{source_id}', fetched_at=datetime.now(timezone.utc),
        team_ids=team_ids or [],
        raw_text=text, cleaned_text=text,
        content_hash=hashlib.sha256(text.encode()).hexdigest(),
    )


def setup_database(path):
    ScheduleRepository(path)._persist(RaceFeed(
        races=[normalize(sample())], updated_at=datetime.now(timezone.utc)))
    with closing(connect(path)) as db, db:
        season_id = db.execute('SELECT season_id FROM seasons').fetchone()[0]
        db.execute("INSERT INTO teams(team_id,canonical_name,status,created_at,updated_at) VALUES ('mer','Mercedes','active','2026-01-01','2026-01-01')")
        db.execute("INSERT INTO team_seasons(team_season_id,team_id,season_id,display_name,status) VALUES ('mer26','mer',?,'Mercedes','active')", (season_id,))


def extraction(change='Revised floor geometry', quote='tested a revised floor geometry during FP1',
               component='floor', team='mercedes', source_ids=None, status='tested'):
    source_ids = source_ids or ['src_one']
    return ExtractionBatch.model_validate({'results': [{
        'race_id': '2026-1', 'team_id': team, 'updates': [{
            'component_id': component, 'change': change, 'goal': None,
            'expected_effect': None, 'status': status, 'evidence_level': 'confirmed',
            'driver_feedback': [], 'source_ids': source_ids, 'confidence': .7,
            'evidence': [{'source_id': item, 'quote': quote, 'supports': ['change', 'status']}
                         for item in source_ids],
        }],
    }]})


class EvolutionSourceTests(unittest.IsolatedAsyncioTestCase):
    async def test_extraction_batches_sources_and_keeps_success_after_one_failure(self):
        documents = [source(f'src_{index}', text=f'Revised floor specification {index}')
                     for index in range(3)]

        class Collector:
            async def collect(self, race_id, urls):
                from app.evolution_worker.sources import CollectionResult
                return CollectionResult(documents, [])

        class Model:
            model_name = 'test'
            calls = []

            async def extract_evolution(self, race_id, items):
                self.calls.append([item.source_id for item in items])
                if len(items) == 2 or items[0].source_id == 'src_0':
                    raise ValueError('truncated response')
                return ExtractionBatch(results=[])

        model = Model()
        result = await run_worker('2026-1', [], Collector(), model)
        self.assertEqual(model.calls, [['src_0', 'src_1'], ['src_0'], ['src_1'], ['src_2']])
        self.assertEqual(result['job_status'], 'partial')
        self.assertEqual(result['extraction_failures'][0]['sources'], ['src_0'])

    async def test_discovered_evolution_requires_technical_source_url(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            report = 'https://www.formula1.com/en/latest/article/race-report-australian-grand-prix.abc'
            with patch('app.evolution_worker.worker.sync_car_catalog', new_callable=AsyncMock), patch(
                'app.evolution_worker.worker.OfficialSourceDiscovery.discover',
                new_callable=AsyncMock, return_value=[report]), patch(
                'app.evolution_worker.worker.execute_evolution', new_callable=AsyncMock) as extraction:
                result = await execute_discovered_evolution(path, '2026-1')
            self.assertEqual(result['discovery']['status'], 'no_technical_source')
            extraction.assert_not_awaited()

    def test_discovery_balances_candidates_across_official_hosts(self):
        candidates = [
            'https://www.formula1.com/one', 'https://www.formula1.com/two',
            'https://www.mclaren.com/one', 'https://www.mclaren.com/two',
            'https://www.ferrari.com/one',
        ]
        self.assertEqual(OfficialSourceDiscovery._balanced(candidates, 4), [
            'https://www.formula1.com/one', 'https://www.mclaren.com/one',
            'https://www.ferrari.com/one', 'https://www.formula1.com/two',
        ])
        self.assertFalse(OfficialSourceDiscovery._usable_url(
            'https://www.mercedesamgf1.com/news/win-a-signed-tee'))

    async def test_discovery_reads_official_article_sitemap_index(self):
        report = 'https://www.formula1.com/en/latest/article/spanish-grand-prix-race-report.abc'
        requested = []

        async def handler(request):
            requested.append(str(request.url))
            path = request.url.path
            if path == '/robots.txt' and request.url.host == 'www.formula1.com':
                return httpx.Response(200, text='Sitemap: https://www.formula1.com/sitemap.xml')
            if path == '/sitemap.xml':
                return httpx.Response(200, text='<loc>https://www.formula1.com/en/latest/article/sitemap.xml</loc>')
            if path == '/en/latest/article/sitemap.xml':
                return httpx.Response(200, text='<loc>https://www.formula1.com/en/latest/articles/sitemap-1.xml</loc>')
            if path == '/en/latest/articles/sitemap-1.xml':
                return httpx.Response(200, text=f'<loc>{report}</loc>')
            if str(request.url) == report:
                return httpx.Response(200, headers={'content-type': 'text/html'}, text=(
                    '<title>2026 Spanish Grand Prix Race Report</title><article>'
                    'The 2026 Spanish Grand Prix race report covers the Spanish Grand Prix. '
                    'The team reviewed its race strategy and the drivers discussed the result.'
                    '</article>'))
            return httpx.Response(404)

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            urls = await OfficialSourceDiscovery(client, public_resolver).discover(
                race_id='2026-14', race_name='Spanish Grand Prix')
        self.assertEqual(urls, [report], requested)

    def test_json_ld_publication_time_drives_post_race_phase(self):
        published = published_at_from_html(
            '<script type="application/ld+json">{"datePublished":"2026-09-13T17:00:00.000Z"}</script>')
        self.assertEqual(published.isoformat(), '2026-09-13T17:00:00+00:00')
        self.assertEqual(publication_phase(
            published, datetime.fromisoformat('2026-09-13T13:00:00+00:00'),
            datetime.fromisoformat('2026-09-13T17:00:00+00:00')), 'post_race')

    def test_cleaner_removes_scripts_and_deduplicates_text(self):
        title, text = clean_html('''<html><title>Tech</title><script>steal()</script>
            <article><h1>Floor</h1><p>A revised floor was tested in FP1.</p></article></html>''')
        self.assertEqual(title, 'Tech')
        self.assertNotIn('steal', text)
        first = source()
        duplicate = source('src_two')
        unique, skipped = deduplicate([first, duplicate])
        self.assertEqual([item.source_id for item in unique], ['src_one'])
        self.assertEqual(skipped, 1)

    def test_ssrf_and_host_allowlist(self):
        with self.assertRaises(ValueError):
            validate_public_url('http://127.0.0.1/private')
        with self.assertRaises(ValueError):
            validate_public_url('https://unknown.example/story', public_resolver)
        private = lambda host, port: [
            (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('10.0.0.1', port)),
        ]
        with self.assertRaises(ValueError):
            validate_public_url('https://www.formula1.com/story', private)

    async def test_provider_fetches_trusted_html(self):
        async def handler(request):
            return httpx.Response(200, headers={'content-type': 'text/html'}, text='''
                <title>Race tech</title><article>The team tested a revised floor geometry
                during Friday practice, comparing the new part with the old specification.
                Engineers collected data before choosing the race configuration.</article>''')
        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            result = await TrustedUrlProvider(client, public_resolver).collect(
                '2026-1', ['https://www.formula1.com/tech'],
            )
        finally:
            await client.aclose()
        self.assertEqual(len(result.documents), 1)
        self.assertEqual(result.documents[0].source_tier, 2)
        self.assertEqual(result.failures, [])

    async def test_redirect_navigation_preserves_required_trailing_slash(self):
        async def handler(request):
            if request.url.path.endswith('/'):
                return httpx.Response(200, headers={'content-type': 'text/html'}, text='''
                    <title>Race report</title><article>The team tested a revised floor geometry
                    during Friday practice and retained it for the race after reviewing data.</article>''')
            return httpx.Response(308, headers={'location': str(request.url) + '/'})
        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            result = await TrustedUrlProvider(client, public_resolver).collect(
                '2026-1', ['https://www.mclaren.com/race-report'],
            )
        finally:
            await client.aclose()
        self.assertEqual(result.failures, [])
        self.assertEqual(str(result.documents[0].url), 'https://www.mclaren.com/race-report')


class ValidatorTests(unittest.TestCase):
    def test_validator_requires_quotes_and_downgrades_test_to_tested(self):
        batch = ExtractionBatch.model_validate({
            'results': [{
                'race_id': '2026-1', 'team_id': 'test-team', 'car_model_id': None,
                'specification_id': None, 'updates': [{
                    'component_id': 'floor', 'change': 'Revised floor geometry',
                    'goal': 'Increase downforce', 'expected_effect': None,
                    'status': 'introduced', 'evidence_level': 'confirmed',
                    'driver_feedback': [], 'source_ids': ['src_one'], 'confidence': .99,
                    'evidence': [{
                        'source_id': 'src_one',
                        'quote': 'tested a revised floor geometry during FP1',
                        'supports': ['change', 'status'],
                    }],
                }],
            }],
        })
        result = validate_batch(batch, [source()])
        update = result.results[0].updates[0]
        self.assertEqual(update.status, 'tested')
        self.assertIsNone(update.goal)
        self.assertLess(update.confidence, .99)
        self.assertEqual(result.review_status, 'pending_review')
        self.assertTrue(any('unsupported goal' in issue for issue in result.issues))

    def test_validator_discards_change_without_literal_evidence(self):
        batch = ExtractionBatch.model_validate({
            'results': [{
                'race_id': '2026-1', 'team_id': 'test-team', 'updates': [{
                    'component_id': 'rear_wing', 'change': 'New rear wing',
                    'status': 'introduced', 'evidence_level': 'confirmed',
                    'driver_feedback': [], 'source_ids': ['src_one'], 'confidence': .9,
                    'evidence': [{'source_id': 'src_one', 'quote': 'not in source',
                                  'supports': ['change']}],
                }],
            }],
        })
        result = validate_batch(batch, [source()])
        self.assertEqual(result.results[0].updates, [])

    def test_validator_does_not_assume_introduced_without_status_words(self):
        batch = ExtractionBatch.model_validate({
            'results': [{'race_id': '2026-1', 'team_id': 'test-team', 'updates': [{
                'component_id': 'floor', 'change': 'Revised floor geometry',
                'status': 'introduced', 'evidence_level': 'confirmed',
                'driver_feedback': [], 'source_ids': ['src_one'], 'confidence': .9,
                'evidence': [{'source_id': 'src_one',
                              'quote': 'floor geometry during FP1',
                              'supports': ['change', 'status']}],
            }]}],
        })
        result = validate_batch(batch, [source()])
        self.assertEqual(result.results[0].updates[0].status, 'unknown')


class DeepSeekTests(unittest.IsolatedAsyncioTestCase):
    def test_unstructured_driver_feedback_is_dropped_without_losing_sourced_upgrade(self):
        raw = extraction().model_dump(mode='json')
        raw['results'][0]['updates'][0]['driver_feedback'] = ['unsupported feedback string']
        batch = _validated_response(json.dumps(raw), ExtractionBatch)
        self.assertEqual(batch.results[0].updates[0].driver_feedback, [])
        self.assertEqual(batch.results[0].updates[0].component_id, 'floor')

    async def test_json_request_and_bearer_header(self):
        seen = {}

        async def handler(request):
            seen['authorization'] = request.headers['authorization']
            seen['body'] = json.loads(request.content)
            return httpx.Response(200, json={
                'choices': [{'message': {'content': json.dumps({'results': []})}}],
            })

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            with patch.dict(os.environ, {'DEEPSEEK_API_KEY': 'test-secret'}, clear=False):
                provider = DeepSeekProvider(client)
                result = await provider.extract_evolution('2026-1', [source()])
        finally:
            await client.aclose()
        self.assertEqual(result.results, [])
        self.assertEqual(seen['authorization'], 'Bearer test-secret')
        self.assertEqual(seen['body']['response_format'], {'type': 'json_object'})
        self.assertEqual(seen['body']['thinking'], {'type': 'disabled'})
        self.assertNotIn('test-secret', json.dumps(seen['body']))


class PersistenceTests(unittest.TestCase):
    def test_public_race_id_resolves_internal_session_window(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            start, end = race_window(path, '2026-1')
            self.assertIsNotNone(start)
            self.assertIsNotNone(end)

    def persist(self, path, documents, batch):
        validated = validate_batch(batch, documents)
        result = persist_validated(path, documents, validated.results, provider='deepseek',
                                   model='test', prompt_version='p', pipeline_version='v')
        return validated, result

    def test_pending_events_are_idempotent_and_publishable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            ScheduleRepository(path)._persist(RaceFeed(
                races=[normalize(sample())], updated_at=datetime.now(timezone.utc),
            ))
            with closing(connect(path)) as db, db:
                season_id = db.execute('SELECT season_id FROM seasons').fetchone()[0]
                db.execute("INSERT INTO teams(team_id,canonical_name,status,created_at,updated_at) VALUES ('mer','Mercedes','active','2026-01-01','2026-01-01')")
                db.execute("INSERT INTO team_seasons(team_season_id,team_id,season_id,display_name,status) VALUES ('mer26','mer',?,'Mercedes','active')", (season_id,))
            batch = ExtractionBatch.model_validate({'results': [{
                'race_id': '2026-1', 'team_id': 'mercedes', 'updates': [{
                    'component_id': 'floor', 'change': 'Revised floor geometry', 'goal': None,
                    'expected_effect': None, 'status': 'tested', 'evidence_level': 'confirmed',
                    'driver_feedback': [], 'source_ids': ['src_one'], 'confidence': .7,
                    'evidence': [{'source_id': 'src_one', 'quote': 'tested a revised floor geometry during FP1',
                                  'supports': ['change', 'status']}],
                }],
            }]})
            validated = validate_batch(batch, [source()])
            first = persist_validated(path, [source()], validated.results, provider='deepseek',
                                      model='test', prompt_version='p', pipeline_version='v')
            second = persist_validated(path, [source()], validated.results, provider='deepseek',
                                       model='test', prompt_version='p', pipeline_version='v')
            self.assertEqual(first['inserted'], 1)
            self.assertEqual(second['inserted'], 0)
            pending = review(path, 'list')
            self.assertEqual(len(pending), 1)
            review(path, 'publish', pending[0]['id'])
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM evolution_source_documents').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM upgrades').fetchone()[0], 1)

    def test_identity_uses_anchor_not_model_prose_or_team_alias(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            document = source()
            first, _ = self.persist(path, [document], extraction())
            second, result = self.persist(path, [document], extraction(
                change='A revised floor geometry was tested',
                quote='The team tested a revised floor geometry during FP1.',
                team='Mercedes AMG'))
            self.assertEqual(first.results[0].updates[0].anchors[0].anchor_id,
                             second.results[0].updates[0].anchors[0].anchor_id)
            self.assertEqual(result['inserted'], 0)
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM evolution_claims').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM upgrades').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM claim_observations').fetchone()[0], 2)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM ai_generations').fetchone()[0], 2)

    def test_duplicate_model_updates_share_one_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            document = source()
            validated = validate_batch(extraction(), [document])
            duplicate_results = [validated.results[0], validated.results[0].model_copy(deep=True)]
            result = persist_validated(path, [document], duplicate_results, provider='deepseek',
                                       model='test', prompt_version='p', pipeline_version='v')
            self.assertEqual(result['inserted'], 1)
            self.assertEqual(result['observed'], 1)
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM evolution_claims').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM claim_observations').fetchone()[0], 1)

    def test_source_revisions_and_equal_content_on_different_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            original = source()
            self.persist(path, [original], extraction())
            changed = source(text=original.cleaned_text + '\nA later editorial note.')
            self.persist(path, [changed], extraction())
            other = source('src_other', original.cleaned_text,
                           url='https://www.formula1.com/other')
            self.persist(path, [other], extraction(source_ids=['src_other']))
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM evolution_source_documents').fetchone()[0], 2)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM evolution_source_revisions').fetchone()[0], 3)
            self.assertEqual(canonical_url('https://formula1.com/a/?utm_source=x&round=2#top'),
                             'https://formula1.com/a?round=2')

    def test_two_evidence_lines_are_two_claims_and_component_change_is_conflict(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            text = 'The team tested a revised floor geometry during FP1.\nA second floor edge was added for FP2.'
            document = source(text=text)
            batch = extraction()
            update = batch.results[0].updates[0]
            update.evidence.append(update.evidence[0].model_copy(update={
                'quote': 'A second floor edge was added for FP2.',
            }))
            validated, first = self.persist(path, [document], batch)
            self.assertEqual(len(validated.results[0].updates[0].anchors), 2)
            self.assertEqual(first['inserted'], 2)
            conflict = extraction(component='other')
            _, result = self.persist(path, [document], conflict)
            self.assertEqual(result['conflicts'], 1)
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM evolution_claims').fetchone()[0], 2)
                self.assertEqual(db.execute("SELECT COUNT(*) FROM review_items WHERE issue_type='component_conflict' AND status='pending_review'").fetchone()[0], 1)

    def test_published_and_rejected_claims_are_stable(self):
        for action in ('publish', 'reject'):
            with self.subTest(action=action), tempfile.TemporaryDirectory() as directory:
                path = f'{directory}/db.sqlite'
                setup_database(path)
                document = source()
                self.persist(path, [document], extraction())
                event_id = review(path, 'list')[0]['id']
                review(path, action, event_id)
                with closing(connect(path)) as db:
                    before = db.execute('''SELECT change_description,technical_goal,expected_effect,
                        status,confidence,review_status FROM upgrades WHERE upgrade_id=?''',
                                        (event_id,)).fetchone()
                self.persist(path, [document], extraction(change='Different model wording'))
                with closing(connect(path)) as db:
                    after = db.execute('''SELECT change_description,technical_goal,expected_effect,
                        status,confidence,review_status FROM upgrades WHERE upgrade_id=?''',
                                       (event_id,)).fetchone()
                    self.assertEqual(db.execute('SELECT COUNT(*) FROM upgrades').fetchone()[0], 1)
                self.assertEqual(before, after)
                self.assertEqual(bool(load_evolution(path, 2026).upgrades), action == 'publish')

    def test_manual_multi_source_merge_controls_public_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            first = source('src_one', 'The team tested a revised floor geometry during FP1.')
            second = source('src_two', 'Engineers confirmed the revised floor geometry after the race.',
                            url='https://www.mclaren.com/racing/report', team_ids=['mercedes'])
            batch = ExtractionBatch.model_validate({'results': [{
                'race_id': '2026-1', 'team_id': 'Mercedes', 'updates': [{
                    'component_id': 'floor', 'change': 'Revised floor geometry', 'goal': None,
                    'expected_effect': None, 'status': 'tested', 'evidence_level': 'confirmed',
                    'driver_feedback': [], 'source_ids': ['src_one', 'src_two'], 'confidence': .8,
                    'evidence': [
                        {'source_id': 'src_one', 'quote': first.cleaned_text, 'supports': ['change', 'status']},
                        {'source_id': 'src_two', 'quote': second.cleaned_text, 'supports': ['change']},
                    ],
                }],
            }]})
            self.persist(path, [first, second], batch)
            with closing(connect(path)) as db:
                mappings = db.execute('SELECT claim_id,upgrade_id FROM upgrade_claims ORDER BY claim_id').fetchall()
            review(path, 'publish', mappings[0][1])
            self.assertEqual(len(load_evolution(path, 2026).upgrades[0].sources), 1)
            review(path, 'merge', mappings[1][0], mappings[0][1])
            feed = load_evolution(path, 2026)
            self.assertEqual(len(feed.upgrades), 1)
            self.assertEqual(len(feed.upgrades[0].sources), 2)

    def test_lifecycle_conflict_does_not_duplicate_event_and_review_can_reopen(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            document = source()
            validated, _ = self.persist(path, [document], extraction())
            changed_update = validated.results[0].updates[0].model_copy(
                update={'status': UpgradeStatus.INTRODUCED})
            changed_results = [validated.results[0].model_copy(update={'updates': [changed_update]})]
            persist_validated(path, [document], changed_results, provider='deepseek', model='test',
                              prompt_version='p', pipeline_version='v')
            with closing(connect(path)) as db, db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM upgrade_lifecycle_events').fetchone()[0], 1)
                item = db.execute("SELECT review_id FROM review_items WHERE entity_type='evolution_lifecycle' AND status='pending_review'").fetchone()[0]
                db.execute("UPDATE review_items SET status='published',resolved_at='now' WHERE review_id=?", (item,))
            persist_validated(path, [document], changed_results, provider='deepseek', model='test',
                              prompt_version='p', pipeline_version='v')
            with closing(connect(path)) as db:
                self.assertEqual(db.execute("SELECT COUNT(*) FROM review_items WHERE entity_type='evolution_lifecycle'").fetchone()[0], 2)
                self.assertEqual(db.execute("SELECT COUNT(*) FROM review_items WHERE entity_type='evolution_lifecycle' AND status='pending_review'").fetchone()[0], 1)

    def test_concurrent_claim_write_and_transaction_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            document = source()
            validated = validate_batch(extraction(), [document])
            args = (path, [document], validated.results)
            kwargs = dict(provider='deepseek', model='test', prompt_version='p', pipeline_version='v')
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(persist_validated, *args, **kwargs) for _ in range(2)]
                [future.result() for future in futures]
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM evolution_claims').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM upgrades').fetchone()[0], 1)

            rollback_path = f'{directory}/rollback.sqlite'
            setup_database(rollback_path)
            with patch('app.evolution_worker.persistence._open_review', side_effect=RuntimeError('stop')):
                with self.assertRaises(RuntimeError):
                    persist_validated(rollback_path, [document], validated.results, **kwargs)
            with closing(connect(rollback_path)) as db:
                for table in ('evolution_source_documents', 'evolution_claims', 'upgrades', 'ai_generations'):
                    self.assertEqual(db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0], 0)

    def test_legacy_published_upgrade_migrates_without_reinterpretation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            with closing(sqlite3.connect(path)) as db, db:
                db.execute('PRAGMA foreign_keys=OFF')
                for table in ('claim_observations', 'claim_evidence', 'upgrade_claims',
                              'evolution_claims', 'evidence_anchor_revisions',
                              'evidence_anchors', 'evolution_source_revisions'):
                    db.execute(f'DROP TABLE {table}')
                db.execute('DROP TABLE evolution_source_documents')
                db.execute('''CREATE TABLE evolution_source_documents (
                    source_id TEXT PRIMARY KEY,race_id TEXT NOT NULL,publisher TEXT NOT NULL,
                    source_type TEXT NOT NULL,publication_phase TEXT NOT NULL,url TEXT NOT NULL UNIQUE,
                    published_at TEXT,fetched_at TEXT NOT NULL,cleaned_text TEXT NOT NULL,
                    content_hash TEXT NOT NULL UNIQUE)''')
                race = db.execute('SELECT race_id FROM races').fetchone()[0]
                db.execute("INSERT INTO technical_eras VALUES ('era26','Era',NULL,NULL,NULL,'active')")
                db.execute("INSERT INTO car_component_types(component_type_id,technical_era_id,canonical_name,status) VALUES ('floor','era26','Floor','active')")
                db.execute('''INSERT INTO upgrades
                    (upgrade_id,team_season_id,introduced_race_id,component_type_id,title,
                    change_description,technical_goal,status,confidence,review_status,created_at,updated_at)
                    VALUES ('cadillac-floor','mer26',?,'floor','Floor update',
                    'Added a vane to the diffuser sidewall.','Increase rear load','introduced','0.75',
                    'published','2026-01-01','2026-01-01')''', (race,))
                text = 'Added a vane to the diffuser sidewall. Increase rear load.'
                db.execute('''INSERT INTO evolution_source_documents VALUES
                    ('old-source',?,'formula1.com','formula1_official','pre_race',
                    'https://formula1.com/report/?utm_source=test',NULL,'2026-01-01',?,?)''',
                           (race, text, hashlib.sha256(text.encode()).hexdigest()))
                db.execute("INSERT INTO evolution_upgrade_sources VALUES ('cadillac-floor','old-source')")
            from app.data_schema import migrate
            migrate(path)
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT canonical_url FROM evolution_source_documents').fetchone()[0],
                                 'https://formula1.com/report')
                self.assertEqual(db.execute('SELECT COUNT(*) FROM evolution_source_revisions').fetchone()[0], 1)
                self.assertEqual(db.execute("SELECT status FROM upgrade_claims WHERE upgrade_id='cadillac-floor'").fetchone()[0], 'accepted')
                self.assertEqual(db.execute("SELECT review_status FROM upgrades WHERE upgrade_id='cadillac-floor'").fetchone()[0], 'published')
            feed = load_evolution(path, 2026)
            self.assertEqual(feed.upgrades[0].id, 'cadillac-floor')
            self.assertEqual(feed.upgrades[0].change, 'Added a vane to the diffuser sidewall.')


class EvolutionAutoReviewTests(unittest.IsolatedAsyncioTestCase):
    async def test_model_review_failure_keeps_claim_unpublished(self):
        class FailingReviewer:
            async def review_evolution(self, race_id, claims):
                raise RuntimeError('model unavailable')

        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            document = source()
            validated = validate_batch(extraction(), [document])
            persist_validated(path, [document], validated.results, provider='deepseek',
                              model='test', prompt_version='p', pipeline_version='v')
            with self.assertRaisesRegex(RuntimeError, 'model unavailable'):
                await auto_review_race(path, '2026-1', FailingReviewer())
            with closing(connect(path)) as db:
                self.assertEqual(db.execute("SELECT review_status FROM upgrades").fetchone()[0],
                                 'pending_review')
            self.assertEqual(load_evolution(path, 2026).upgrades, [])

    async def test_differently_worded_second_source_merges_into_published_upgrade(self):
        class Reviewer:
            async def review_evolution(self, race_id, claims):
                claim = claims[0]
                matches = claim['existing_upgrades']
                return ReviewBatch.model_validate({'verdicts': [{
                    'event_id': claim['event_id'], 'category': 'upgrade',
                    'supported': True, 'confidence': .8,
                    'match_event_id': matches[0]['event_id'] if matches else None,
                }]})

        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            first = source()
            persist_validated(path, [first], validate_batch(extraction(), [first]).results,
                              provider='deepseek', model='test', prompt_version='p', pipeline_version='v')
            reviewer = Reviewer()
            self.assertEqual((await auto_review_race(path, '2026-1', reviewer))['published'], 1)
            second = source('src_two')
            different = extraction(change='The team introduced a revised floor specification',
                                   source_ids=['src_two'])
            persist_validated(path, [second], validate_batch(different, [second]).results,
                              provider='deepseek', model='test', prompt_version='p', pipeline_version='v')
            result = await auto_review_race(path, '2026-1', reviewer)
            self.assertEqual(result['merged'], 1)
            feed = load_evolution(path, 2026)
            self.assertEqual(len(feed.upgrades), 1)
            self.assertEqual(len(feed.upgrades[0].sources), 2)

    async def test_conflicted_claim_is_rejected_without_model_guess(self):
        class Reviewer:
            async def review_evolution(self, race_id, claims):
                raise AssertionError('Conflicts must not reach model publication')

        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            document = source()
            first = validate_batch(extraction(), [document])
            persist_validated(path, [document], first.results, provider='deepseek',
                              model='test', prompt_version='p', pipeline_version='v')
            conflicting = validate_batch(extraction(component='other'), [document])
            persist_validated(path, [document], conflicting.results, provider='deepseek',
                              model='test', prompt_version='p', pipeline_version='v')
            result = await auto_review_race(path, '2026-1', Reviewer())
            self.assertEqual(result['rejected'], 1)
            self.assertEqual(result['pending'], 0)
            self.assertEqual(load_evolution(path, 2026).upgrades, [])

    async def test_same_upgrade_from_two_sources_auto_merges(self):
        class Reviewer:
            async def review_evolution(self, race_id, claims):
                return ReviewBatch.model_validate({'verdicts': [
                    {'event_id': item['event_id'], 'category': 'upgrade',
                     'supported': True, 'confidence': .8}
                    for item in claims]})

        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            documents = [source(), source('src_two')]
            validated = validate_batch(extraction(source_ids=['src_one', 'src_two']), documents)
            persist_validated(path, documents, validated.results, provider='deepseek',
                              model='test', prompt_version='p', pipeline_version='v')
            result = await auto_review_race(path, '2026-1', Reviewer())
            self.assertEqual(result['published'], 1)
            self.assertEqual(result['merged'], 1)
            feed = load_evolution(path, 2026)
            self.assertEqual(len(feed.upgrades), 1)
            self.assertEqual(len(feed.upgrades[0].sources), 2)

    async def test_supported_claim_publishes_once_with_lower_review_confidence(self):
        class Reviewer:
            async def review_evolution(self, race_id, claims):
                return ReviewBatch.model_validate({'verdicts': [
                    {'event_id': item['event_id'], 'category': 'upgrade',
                     'supported': True, 'confidence': .62}
                    for item in claims]})

        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            document = source()
            validated = validate_batch(extraction(), [document])
            persist_validated(path, [document], validated.results, provider='deepseek',
                              model='test', prompt_version='p', pipeline_version='v')
            first = await auto_review_race(path, '2026-1', Reviewer())
            second = await auto_review_race(path, '2026-1', Reviewer())
            self.assertEqual(first['published'], 1)
            self.assertEqual(second['reviewed'], 0)
            feed = load_evolution(path, 2026)
            self.assertEqual(len(feed.upgrades), 1)
            self.assertEqual(feed.upgrades[0].confidence, '0.62')

    async def test_unsupported_claim_is_rejected_and_never_reopened(self):
        class Reviewer:
            async def review_evolution(self, race_id, claims):
                return ReviewBatch.model_validate({'verdicts': [
                    {'event_id': item['event_id'], 'category': 'replacement',
                     'supported': True, 'confidence': .2}
                    for item in claims]})

        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            setup_database(path)
            document = source()
            validated = validate_batch(extraction(), [document])
            persist_validated(path, [document], validated.results, provider='deepseek',
                              model='test', prompt_version='p', pipeline_version='v')
            first = await auto_review_race(path, '2026-1', Reviewer())
            self.assertEqual(first['rejected'], 1)
            self.assertEqual((await auto_review_race(path, '2026-1', Reviewer()))['reviewed'], 0)
            self.assertEqual(load_evolution(path, 2026).upgrades, [])


if __name__ == '__main__':
    unittest.main()
