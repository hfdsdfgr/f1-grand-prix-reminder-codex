"""Validate captured public API responses against the server's read schemas."""
import json
from pathlib import Path
import unittest

from app.evolution import EvolutionFeed, EvolutionRaceDetail


FIXTURES = Path(__file__).resolve().parents[2] / 'mobile/test/fixtures/evolution'


class EvolutionPayloadContractTests(unittest.TestCase):
    def test_live_and_historical_payloads_preserve_confidence_and_boolean_types(self):
        for path in sorted(FIXTURES.glob('*.json')):
            with self.subTest(payload=path.name):
                payload = json.loads(path.read_text(encoding='utf-8'))
                schema = EvolutionRaceDetail if 'race_id' in payload else EvolutionFeed
                parsed = schema.model_validate(payload)
                if 'stale' in payload:
                    self.assertIs(type(payload['stale']), bool)
                    self.assertEqual(parsed.stale, payload['stale'])
                for raw, upgrade in zip(payload['upgrades'], parsed.upgrades):
                    self.assertIs(type(raw['confidence']), str)
                    self.assertEqual(upgrade.confidence, raw['confidence'])
                    self.assertEqual(upgrade.id, raw['id'])
                    self.assertEqual(len(upgrade.sources), len(raw['sources']))
                    self.assertNotIn('low_confidence', raw)

    def test_translations_keep_the_same_evidence_contract(self):
        for scope in ['2026', '2025', '2026-1', '2026-22']:
            payloads = [json.loads((FIXTURES / f'{scope}-{lang}.json').read_text(
                encoding='utf-8')) for lang in ['en', 'zh-CN']]
            project = lambda payload: [(u['id'], u['confidence'], u['status'],
                u['sources']) for u in payload['upgrades']]
            self.assertEqual(project(payloads[0]), project(payloads[1]))
