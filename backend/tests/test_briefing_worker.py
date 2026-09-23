import hashlib
import sqlite3
import tempfile
import unittest
from contextlib import closing
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

from app.briefing_worker import execute_briefing
from app.historical_briefing_backfill import eligible_post_race
from app.data_schema import connect
from app.evolution_worker.models import BriefingBatch, SourceDocument
from app.evolution_worker.sources import CollectionResult, OfficialSourceDiscovery, eligible_race_day_report
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

    async def test_scheduled_race_day_report_is_fetched_and_briefed(self):
        report = document().model_copy(update={
            'title': '2026 Australian Grand Prix race report',
            'published_at': datetime(2026, 3, 8, 6, tzinfo=timezone.utc),
        })
        with patch('app.briefing_worker.OfficialSourceDiscovery.discover',
                   new_callable=AsyncMock, return_value=[str(report.url)]), patch(
                       'app.briefing_worker.TrustedUrlProvider.collect',
                       new_callable=AsyncMock, return_value=CollectionResult([report], [])):
            result = await execute_briefing(
                self.path, '2026-1', allow_race_day_sources=True,
                llm_provider=FakeBriefingLLM())
        self.assertEqual(result['persistence']['status'], 'created')
        self.assertEqual(result['persistence']['inserted'], 1)

    def test_discovery_relevance_requires_race_evidence(self):
        relevant = document('The 2026 Spanish Grand Prix race report says tyre degradation was manageable.')
        unrelated = document('A preview of the Japanese Grand Prix.')
        keywords = OfficialSourceDiscovery._keywords('Spanish Grand Prix', 'Madring', 'Spain', 'Madrid')
        self.assertTrue(OfficialSourceDiscovery._is_relevant(relevant, 'Spanish Grand Prix', keywords, 2026))
        self.assertFalse(OfficialSourceDiscovery._is_relevant(unrelated, 'Spanish Grand Prix', keywords, 2026))
        self.assertFalse(OfficialSourceDiscovery._candidate_matches(
            'https://team.example/2025-spanish-grand-prix', '', keywords, 2026))

    def test_historical_backfill_requires_dated_matching_post_race_source(self):
        start = datetime(2026, 9, 6, 13, tzinfo=timezone.utc)
        end = datetime(2026, 9, 6, 17, tzinfo=timezone.utc)
        report = document().model_copy(update={
            'title': '2026 Italian Grand Prix Race Report',
            'published_at': datetime(2026, 9, 6, 17, 30, tzinfo=timezone.utc),
        })
        self.assertTrue(eligible_post_race(report, 'Italian Grand Prix', start, end))
        self.assertFalse(eligible_post_race(report.model_copy(update={'published_at': None}),
                                            'Italian Grand Prix', start, end))
        self.assertFalse(eligible_post_race(report.model_copy(update={
            'published_at': datetime(2026, 9, 6, 12, tzinfo=timezone.utc)}),
            'Italian Grand Prix', start, end))
        self.assertFalse(eligible_post_race(report.model_copy(update={
            'title': 'Spanish Grand Prix preview after Monza success'}),
            'Italian Grand Prix', start, end))
        self.assertFalse(eligible_post_race(report.model_copy(update={
            'title': 'Win an Italian Grand Prix signed team tee',
            'url': 'https://www.mercedesamgf1.com/news/win-italian-grand-prix-tee'}),
            'Italian Grand Prix', start, end))
        self.assertFalse(eligible_post_race(report.model_copy(update={
            'title': 'Quiz: How well do you remember the Italian Grand Prix?'}),
            'Italian Grand Prix', start, end))
        self.assertTrue(eligible_race_day_report(report.model_copy(update={
            'published_at': datetime(2026, 9, 6, 15, tzinfo=timezone.utc)}),
            'Italian Grand Prix', 2026, start))
        self.assertFalse(eligible_race_day_report(report.model_copy(update={
            'title': '2026 Spanish Grand Prix race report'}),
            'Italian Grand Prix', 2026, start))
        italy_quotes = report.model_copy(update={
            'title': 'What the teams said – Race day in Italy',
            'url': 'https://www.formula1.com/en/latest/article/what-the-teams-said-race-day-in-italy-2026',
        })
        self.assertTrue(eligible_race_day_report(
            italy_quotes, 'Italian Grand Prix', 2026, start, ('Italy', 'Monza')))


if __name__ == '__main__':
    unittest.main()
