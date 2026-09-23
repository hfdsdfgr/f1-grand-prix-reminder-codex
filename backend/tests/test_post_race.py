import sqlite3
import tempfile
import unittest
from contextlib import closing
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch

from app.data_schema import connect
from app.models import RaceFeed
from app.post_race import PostRaceOrchestrator
from app.providers.jolpica import normalize
from app.repositories.schedules import ScheduleRepository
from test_schedules import sample


UTC = timezone.utc


def database(path: str, *, start='2026-03-08T04:00:00+00:00', completed=False):
    ScheduleRepository(path)._persist(RaceFeed(
        races=[normalize(sample())], updated_at=datetime.now(UTC)))
    with closing(connect(path)) as db, db:
        db.execute("UPDATE sessions SET scheduled_start=? WHERE session_type='race'", (start,))
        if completed:
            db.execute("""UPDATE sessions SET status='completed',actual_end=?
                WHERE session_type='race'""", ('2026-03-08T06:00:00+00:00',))


def jobs(path: str):
    with closing(sqlite3.connect(path)) as db:
        return db.execute('''SELECT worker_type,processing_stage,status,attempt_count,error
            FROM post_race_jobs ORDER BY worker_type,processing_stage''').fetchall()


class PostRaceTests(unittest.IsolatedAsyncioTestCase):
    async def test_default_workers_use_discovery_and_model_review(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, completed=True)
            orchestrator = PostRaceOrchestrator(path)
            with patch('app.post_race.execute_discovered_evolution', new_callable=AsyncMock,
                       return_value={'sources': []}) as evolution, patch(
                           'app.post_race.auto_review_race', new_callable=AsyncMock,
                           return_value={'published': 0}) as reviewer, patch(
                           'app.post_race.execute_briefing', new_callable=AsyncMock,
                           return_value={'sources': []}) as briefing:
                await orchestrator._run_evolution('2026-1', 'initial')
                await orchestrator._run_briefing('2026-1', 'initial')
            evolution.assert_awaited_once_with(path, '2026-1')
            reviewer.assert_awaited_once_with(path, '2026-1')
            briefing.assert_awaited_once_with(path, '2026-1', allow_race_day_sources=True)

    async def test_unfinished_race_does_not_create_jobs(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, start='2026-10-08T04:00:00+00:00')
            runner = lambda race, stage: {}
            report = await PostRaceOrchestrator(path, {'evolution': runner}).tick(
                datetime(2026, 10, 8, 5, tzinfo=UTC))
            self.assertEqual(report, {'jobs_created': 0, 'jobs_recovered': 0, 'jobs_processed': 0})

    async def test_finished_race_creates_three_jobs_and_repeat_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, completed=True)
            calls = []
            runner = lambda race, stage: calls.append((race, stage)) or {}
            orchestrator = PostRaceOrchestrator(path, {'evolution': runner})
            now = datetime(2026, 3, 10, tzinfo=UTC)
            first = await orchestrator.tick(now, replay_race='2026-1')
            second = await orchestrator.tick(now, replay_race='2026-1')
            self.assertEqual(first['jobs_created'], 3)
            self.assertEqual(first['jobs_processed'], 3)
            self.assertEqual(second['jobs_created'], 0)
            self.assertEqual(second['jobs_processed'], 0)
            self.assertEqual(len(calls), 3)
            self.assertTrue(all(row[2] == 'completed' for row in jobs(path)))

    async def test_fallback_finish_and_schedule_revision_keep_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path)
            runner = lambda race, stage: {}
            now = datetime(2026, 3, 10, tzinfo=UTC)
            orchestrator = PostRaceOrchestrator(path, {'evolution': runner})
            await orchestrator.tick(now)
            with closing(connect(path)) as db, db:
                db.execute("UPDATE sessions SET scheduled_start='2026-03-08T05:00:00+00:00'")
            await orchestrator.tick(now)
            self.assertEqual(len(jobs(path)), 3)
            with closing(connect(path)) as db:
                methods = {r[0] for r in db.execute(
                    'SELECT finish_detection_method FROM post_race_jobs')}
            self.assertEqual(methods, {'schedule_fallback'})

    async def test_failure_retries_then_becomes_terminal(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, completed=True)
            def broken(race, stage):
                raise ValueError('provider unavailable')
            orchestrator = PostRaceOrchestrator(
                path, {'evolution': broken}, retry_delays=(timedelta(0), timedelta(0)))
            await orchestrator.tick(datetime(2026, 3, 10, tzinfo=UTC), replay_race='2026-1')
            rows = jobs(path)
            self.assertTrue(all(row[2] == 'failed' and row[3] == 3 for row in rows))
            self.assertTrue(all('provider unavailable' in row[4] for row in rows))

    async def test_stale_running_job_is_recovered(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, completed=True)
            runner = lambda race, stage: {}
            orchestrator = PostRaceOrchestrator(path, {'evolution': runner})
            now = datetime(2026, 3, 10, tzinfo=UTC)
            orchestrator.ensure_jobs(now, replay_race='2026-1')
            with closing(connect(path)) as db, db:
                db.execute("""UPDATE post_race_jobs SET status='running',attempt_count=1,
                    started_at='2026-03-09T00:00:00+00:00' WHERE processing_stage='initial'""")
            report = await PostRaceOrchestrator(path, {'evolution': runner}).tick(
                now, replay_race='2026-1')
            self.assertEqual(report['jobs_recovered'], 1)
            self.assertTrue(all(row[2] == 'completed' for row in jobs(path)))

    async def test_worker_failure_does_not_block_other_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, completed=True)
            def broken(race, stage):
                raise RuntimeError('broken')
            good = lambda race, stage: {'sources': [{'url': 'x'}]}
            orchestrator = PostRaceOrchestrator(
                path, {'briefing': broken, 'evolution': good}, retry_delays=())
            await orchestrator.tick(datetime(2026, 3, 10, tzinfo=UTC), replay_race='2026-1')
            rows = jobs(path)
            self.assertEqual(sum(row[2] == 'failed' for row in rows), 3)
            self.assertEqual(sum(row[2] == 'completed' for row in rows), 3)

    async def test_replay_stages_survive_new_process_instances(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, completed=True)
            calls = []
            runner = lambda race, stage: calls.append(stage) or {}
            now = datetime(2026, 3, 10, tzinfo=UTC)
            for stage in ('initial', 'supplemental', 'final'):
                await PostRaceOrchestrator(path, {'evolution': runner}).tick(
                    now, replay_race='2026-1', only_stage=stage)
            self.assertEqual(calls, ['initial', 'supplemental', 'final'])
            self.assertTrue(all(row[2] == 'completed' for row in jobs(path)))

    async def test_two_races_have_independent_jobs(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, completed=True)
            raw = sample()
            raw.update({'round': '2', 'raceName': 'Second Grand Prix',
                        'date': '2026-03-15', 'time': '04:00:00Z'})
            ScheduleRepository(path)._persist(RaceFeed(
                races=[normalize(raw)], updated_at=datetime.now(UTC)))
            with closing(connect(path)) as db, db:
                db.execute("""UPDATE sessions SET status='completed',actual_end=scheduled_start
                    WHERE race_id=(SELECT race_id FROM race_external_identities
                    WHERE external_id='2026-2') AND session_type='race'""")
            orchestrator = PostRaceOrchestrator(path, {'evolution': lambda race, stage: {}})
            orchestrator.ensure_jobs(datetime(2026, 3, 20, tzinfo=UTC), replay_race='2026-1')
            orchestrator.ensure_jobs(datetime(2026, 3, 20, tzinfo=UTC), replay_race='2026-2')
            self.assertEqual(len(jobs(path)), 6)

    async def test_scheduler_does_not_publish_review_items(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            database(path, completed=True)
            def runner(race, stage):
                with closing(connect(path)) as db, db:
                    db.execute('''INSERT OR IGNORE INTO review_items VALUES
                        ('review-test','evolution_claim',NULL,'source_check','manual review',
                         'medium','pending_review','2026-03-10T00:00:00+00:00',NULL)''')
                return {}
            await PostRaceOrchestrator(path, {'evolution': runner}).tick(
                datetime(2026, 3, 10, tzinfo=UTC), replay_race='2026-1')
            with closing(connect(path)) as db:
                status = db.execute(
                    "SELECT status FROM review_items WHERE review_id='review-test'").fetchone()[0]
            self.assertEqual(status, 'pending_review')


if __name__ == '__main__':
    unittest.main()
