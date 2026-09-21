import json
import os
import socket
import tempfile
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

import httpx

from app.evolution_worker.llm import DeepSeekProvider
from app.evolution_worker.models import ExtractionBatch, SourceDocument
from app.evolution_worker.sources import TrustedUrlProvider, clean_html, deduplicate, validate_public_url
from app.evolution_worker.validator import validate_batch


def public_resolver(host, port):
    return [(socket.AF_INET, socket.SOCK_STREAM, 6, '', ('93.184.216.34', port))]


def source(source_id='src_one', text='The team tested a revised floor geometry during FP1.'):
    return SourceDocument(
        source_id=source_id, race_id='2026-1', publisher='formula1.com',
        source_type='formula1_official', source_tier=2, title='Technical update',
        url=f'https://www.formula1.com/{source_id}', fetched_at=datetime.now(timezone.utc),
        raw_text=text, cleaned_text=text,
        content_hash=f'hash-{source_id}',
    )


class EvolutionSourceTests(unittest.IsolatedAsyncioTestCase):
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


class DeepSeekTests(unittest.IsolatedAsyncioTestCase):
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
        self.assertNotIn('test-secret', json.dumps(seen['body']))


if __name__ == '__main__':
    unittest.main()
