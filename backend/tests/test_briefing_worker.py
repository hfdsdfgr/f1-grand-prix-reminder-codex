import hashlib
import sqlite3
import tempfile
import unittest
from contextlib import closing
from datetime import datetime, timezone
from unittest.mock import patch

from app.briefing_worker import execute_briefing
from app.data_schema import connect
from app.evolution_worker.models import BriefingBatch, SourceDocument
from app.evolution_worker.sources import CollectionResult, OfficialSourceDiscovery
from app.models import RaceFeed
from app.providers.jolpica import normalize
from app.repositories.schedules import ScheduleRepository
from test_schedules import sample


def document(text='The team said tyre degradation was manageable during the race.'):
    return SourceDocument(
        source_id='src_brief', race_id='2026-1', publisher='formula1.com',
        source_type='formula1_official', source_tier=2, title='Race report',
        url='https://www.formula1.com/en/latest/article/race-report',
        fetched_at=datetime.now(timezone.utc), raw_text=text, cleaned_text=text,
        content_hash=hashlib.sha256(text.encode()).hexdigest())


class FakeBriefingLLM:
    model_name = 'test-model'

    async def extract_briefing(self, race_id, documents):
        return BriefingBatch.model_validate({'facts': [{'field': 'tyres',
            'value': 'Tyre degradation was manageable.', 'evidence': [{
                'source_id': 'src_brief', 'quote': 'tyre degradation was manageable during the race',
            }]}]})


async def collected(self, race_id, urls):
    return CollectionResult([document()], [])


class BriefingWorkerTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = f'{self.directory.name}/brief.db'
        ScheduleRepository(self.path)._persist(RaceFeed(
            races=[normalize(sample())], updated_at=datetime.now(timezone.utc)))

    def tearDown(self):
        self.directory.cleanup()

    async def test_source_backed_brief_is_idempotent(self):
        with patch('app.briefing_worker.TrustedUrlProvider.collect', collected):
            first = await execute_briefing(self.path, '2026-1', ['https://www.formula1.com/en/latest/article/race-report'],
                                           llm_provider=FakeBriefingLLM())
            second = await execute_briefing(self.path, '2026-1', ['https://www.formula1.com/en/latest/article/race-report'])
        self.assertEqual(first['persistence']['status'], 'created')
        self.assertEqual(second['persistence']['status'], 'reused')
        with closing(sqlite3.connect(self.path)) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM race_briefs').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT count(*) FROM briefing_evidence').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT count(*) FROM ai_generations').fetchone()[0], 1)

    async def test_no_source_is_a_successful_empty_result(self):
        result = await execute_briefing(self.path, '2026-1', [])
        self.assertEqual(result['persistence']['status'], 'no_official_source')

    def test_discovery_relevance_requires_race_evidence(self):
        relevant = document('The 2026 Spanish Grand Prix race report says tyre degradation was manageable.')
        unrelated = document('A preview of the Japanese Grand Prix.')
        keywords = OfficialSourceDiscovery._keywords('Spanish Grand Prix', 'Madring', 'Spain', 'Madrid')
        self.assertTrue(OfficialSourceDiscovery._is_relevant(relevant, 'Spanish Grand Prix', keywords, 2026))
        self.assertFalse(OfficialSourceDiscovery._is_relevant(unrelated, 'Spanish Grand Prix', keywords, 2026))
        self.assertFalse(OfficialSourceDiscovery._candidate_matches(
            'https://team.example/2025-spanish-grand-prix', '', keywords, 2026))


if __name__ == '__main__':
    unittest.main()
