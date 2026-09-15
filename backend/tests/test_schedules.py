import tempfile
import unittest
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.lifecycle import with_lifecycle
from app.models import RaceFeed
from app.providers.jolpica import normalize
from app.repositories.schedules import ScheduleRepository


def sample():
    return {
        'season': '2026', 'round': '1', 'raceName': 'Test Grand Prix',
        'date': '2026-03-08', 'time': '04:00:00Z',
        'Circuit': {'circuitName': 'Test Circuit', 'Location': {'country': 'Australia'}},
        'Qualifying': {'date': '2026-03-07', 'time': '05:00:00Z'},
    }


class ScheduleTests(unittest.TestCase):
    def test_lifecycle_uses_session_times_without_changing_schedule(self):
        raw = sample()
        raw['FirstPractice'] = {'date': '2026-03-06', 'time': '02:00:00Z'}
        race = normalize(raw)
        pre = with_lifecycle(race, datetime(2026, 3, 5, tzinfo=timezone.utc))
        weekend = with_lifecycle(race, datetime(2026, 3, 6, 2, 30, tzinfo=timezone.utc))
        post = with_lifecycle(race, datetime(2026, 3, 8, 8, 1, tzinfo=timezone.utc))
        self.assertEqual(pre.lifecycle_phase, 'pre_race')
        self.assertEqual(weekend.lifecycle_phase, 'race_weekend')
        self.assertEqual(weekend.current_session.kind, 'FP1')
        self.assertEqual(post.lifecycle_phase, 'post_race')
        self.assertEqual(post.status, 'completed')
        self.assertEqual(race.status, 'unknown')

    def test_delayed_session_remains_current_in_weekend_hub(self):
        raw = sample()
        raw['FirstPractice'] = {'date': '2026-03-06', 'time': '02:00:00Z'}
        race = normalize(raw)
        delayed = race.model_copy(update={
            'sessions': [
                race.sessions[0].model_copy(update={'status': 'delayed'}),
                *race.sessions[1:],
            ],
        })
        weekend = with_lifecycle(
            delayed, datetime(2026, 3, 6, 2, 30, tzinfo=timezone.utc),
        )
        self.assertEqual(weekend.current_session.kind, 'FP1')
        self.assertEqual(weekend.current_session.status, 'delayed')

    def test_versioned_circuit_layout_is_attached_and_persisted(self):
        with tempfile.TemporaryDirectory() as directory:
            raw = sample()
            raw['Circuit']['circuitId'] = 'suzuka'
            repo = ScheduleRepository(f'{directory}/cache.db')
            feed = repo._persist(RaceFeed(
                races=[normalize(raw)], updated_at=datetime.now(timezone.utc),
            ))
            layout = feed.races[0].circuit_layout
            self.assertEqual(layout.id, 'suzuka-2')
            self.assertEqual(layout.valid_from, 2022)
            with closing(sqlite3.connect(repo.path)) as db:
                stored = db.execute('''SELECT source_license, turns
                    FROM circuit_layouts WHERE layout_id='suzuka-2' ''').fetchone()
            self.assertEqual(stored, ('CC BY 4.0', 18))

    def test_normalization_and_unknown_time(self):
        race = normalize(sample())
        self.assertEqual([s.kind for s in race.sessions], ['Qualifying', 'Race'])
        self.assertEqual(race.starts_at.utcoffset(), timedelta(0))
        raw = sample()
        del raw['time']
        self.assertIsNone(normalize(raw).starts_at)
        raw = sample()
        del raw['Qualifying']['time']
        qualifying = next(s for s in normalize(raw).sessions if s.kind == 'Qualifying')
        self.assertIsNone(qualifying.starts_at)
        raw['time'] = '04:00:00'
        with self.assertRaises(ValueError):
            normalize(raw)

    def test_cache_and_stale_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = ScheduleRepository(f'{directory}/cache.db')
            with patch('app.repositories.schedules.fetch_season', return_value=[normalize(sample())]) as fetch:
                repo.season(2026)
                repo.season(2026)
                self.assertEqual(fetch.call_count, 1)
            future = datetime.now(timezone.utc) + timedelta(days=2)
            with patch('app.repositories.schedules.datetime') as clock, patch('app.repositories.schedules.fetch_season', side_effect=RuntimeError):
                clock.now.return_value = future
                self.assertTrue(repo.season(2026).stale)
            with closing(sqlite3.connect(repo.path)) as db:
                health = db.execute(
                    "SELECT status, consecutive_failures FROM provider_health WHERE provider_id='prv_jolpica'",
                ).fetchone()
            self.assertEqual(health, ('degraded', 1))
            with patch('app.repositories.schedules.datetime') as clock, patch(
                'app.repositories.schedules.fetch_season', side_effect=ValueError,
            ):
                clock.now.return_value = future
                self.assertTrue(repo.season(2026).stale)
            self.assertEqual(repo.health()['status'], 'schema_changed')

    def test_internal_identity_and_schedule_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = ScheduleRepository(f'{directory}/cache.db')
            first = repo._persist(RaceFeed(
                races=[normalize(sample())], updated_at=datetime.now(timezone.utc),
            ))
            changed = sample()
            changed['Qualifying']['time'] = '06:00:00Z'
            second = repo._persist(RaceFeed(
                races=[normalize(changed)], updated_at=datetime.now(timezone.utc),
            ))
            self.assertTrue(first.races[0].internal_id.startswith('rac_'))
            self.assertEqual(first.races[0].internal_id, second.races[0].internal_id)
            self.assertEqual(
                first.races[0].sessions[0].internal_id,
                second.races[0].sessions[0].internal_id,
            )
            with closing(sqlite3.connect(repo.path)) as db:
                revision = db.execute('''SELECT previous_start, new_start
                    FROM schedule_revisions''').fetchone()
                identities = db.execute(
                    'SELECT COUNT(*) FROM race_external_identities',
                ).fetchone()[0]
                tables = {row[0] for row in db.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'",
                )}
                versions = [row[0] for row in db.execute(
                    'SELECT version FROM schema_migrations ORDER BY version',
                )]
                foreign_key_errors = list(db.execute('PRAGMA foreign_key_check'))
            self.assertIn('05:00:00', revision[0])
            self.assertIn('06:00:00', revision[1])
            self.assertEqual(identities, 1)
            self.assertTrue({
                'raw_source_records', 'driver_team_assignments', 'starting_grids',
                'result_revisions', 'penalties', 'laps', 'car_specifications',
                'upgrade_lifecycle_events', 'interviews', 'source_snapshots',
                'ai_generations', 'driver_briefs', 'race_briefs', 'review_items',
                'audit_log',
            }.issubset(tables))
            self.assertEqual(versions, [1, 2, 3, 4, 5, 6, 7, 8, 9])
            self.assertEqual(foreign_key_errors, [])

    def test_api_failure_validation_and_rollover(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict('os.environ', {'DATABASE_PATH': f'{directory}/cache.db'}), TestClient(app) as client:
            self.assertEqual(client.get('/health').status_code, 200)
            self.assertEqual(client.get('/api/v1/data-health').status_code, 200)
            seasons = client.get('/api/v1/seasons').json()
            self.assertEqual(seasons[-1], 1950)
            self.assertEqual(client.get('/api/v1/races?season=1800').status_code, 422)
            with patch.object(app.state.schedules, 'season', side_effect=RuntimeError):
                self.assertEqual(client.get('/api/v1/next-race').status_code, 503)
            empty = RaceFeed(races=[], updated_at=datetime.now(timezone.utc))
            with patch.object(app.state.schedules, 'season', return_value=empty) as fetch:
                self.assertIsNone(client.get('/api/v1/next-race').json()['race'])
                self.assertEqual(fetch.call_count, 2)
            with patch.object(app.state.schedules, 'season', return_value=RaceFeed(
                races=[normalize(sample())], updated_at=datetime.now(timezone.utc),
            )):
                response = client.get('/api/v1/races/2026-1/schedule-revisions')
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.json(), [])


if __name__ == '__main__':
    unittest.main()
