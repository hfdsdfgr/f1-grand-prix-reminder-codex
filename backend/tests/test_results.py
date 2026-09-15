import tempfile
import unittest
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from app.main import app
from app.models import RaceFeed
from app.providers.jolpica import normalize
from app.results import (
    ResultsRepository, build_race_story, fetch_season_summaries, normalize_results,
    SeasonRosterEntry, SeasonRosterFeed,
)
from app.repositories.schedules import ScheduleRepository
from test_schedules import sample


def row(**overrides):
    return dict({'position': '1', 'positionText': '1', 'Driver': {'givenName': 'Test', 'familyName': 'Driver'},
                 'Constructor': {'name': 'Test Team'}, 'grid': '0', 'points': '0.5', 'status': 'Finished'}, **overrides)


class ResultsTests(unittest.TestCase):
    def test_source_roster_uses_result_identity_and_falls_back_to_cache(self):
        standings = [{
            'Driver': {
                'driverId': 'test-driver', 'givenName': 'Test', 'familyName': 'Driver',
                'nationality': 'Test', 'dateOfBirth': '2000-01-01', 'permanentNumber': '42',
            },
            'Constructors': [{'constructorId': 'test-team', 'name': 'Test Team'}],
        }]
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/data.db'
            ScheduleRepository(path)._persist(RaceFeed(
                races=[normalize(sample())], updated_at=datetime.now(timezone.utc),
            ))
            repo = ResultsRepository(path)
            result = repo._persist(2026, 1, 'results', normalize_results([
                row(Driver={
                    'driverId': 'test-driver', 'givenName': 'Test', 'familyName': 'Driver',
                }, Constructor={'constructorId': 'test-team', 'name': 'Test Team'}),
            ], 'https://example.com/results', 'results'))
            with patch('app.results.fetch_driver_standings', return_value=standings) as fetch:
                first = repo.roster(2026)
                second = repo.roster(2026)
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(first.entries[0].driver_id, result.entries[0].driver_id)
            self.assertEqual(first.entries[0].team_id, result.entries[0].team_id)
            self.assertEqual(second.entries[0].driver, 'Test Driver')
            with patch('app.results.datetime') as clock, \
                    patch('app.results.fetch_driver_standings', side_effect=RuntimeError):
                clock.now.return_value = datetime.now(timezone.utc) + timedelta(minutes=16)
                self.assertTrue(repo.roster(2026).stale)

    def test_roster_endpoint_returns_normalized_entries(self):
        roster = SeasonRosterFeed(
            entries=[SeasonRosterEntry(
                driver_id='drv_driver', driver='Test Driver',
                team_id='tea_team', team='Test Team',
            )],
            source='https://api.jolpi.ca/ergast/f1/2026/driverstandings/',
            updated_at=datetime.now(timezone.utc),
        )
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict('os.environ', {'DATABASE_PATH': f'{directory}/cache.db'}), \
                TestClient(app) as client:
            with patch.object(app.state.schedules, 'season', return_value=RaceFeed(
                races=[normalize(sample())], updated_at=datetime.now(timezone.utc),
            )), patch.object(app.state.results, 'roster', return_value=roster):
                response = client.get('/api/v1/seasons/2026/roster')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['entries'][0]['driver_id'], 'drv_driver')

    def test_season_summaries_are_batched_and_cached(self):
        driver = {'driverId': 'driver', 'givenName': 'Test', 'familyName': 'Winner'}
        result = {
            'position': '1', 'positionText': '1', 'points': '25',
            'Driver': driver, 'Constructor': {'constructorId': 'team', 'name': 'Test Team'},
            'FastestLap': {'rank': '1', 'lap': '42', 'Time': {'time': '1:20.000'}},
        }
        responses = []
        for payload in (
            [{'round': '1', 'Results': [result]}],
            [{'round': '1', 'Results': [result]}],
        ):
            response = Mock()
            response.json.return_value = {'MRData': {'RaceTable': {'Races': payload}}}
            responses.append(response)
        with patch('app.results.httpx.get', side_effect=responses) as request:
            summary = fetch_season_summaries(2026)
        self.assertEqual(request.call_count, 2)
        self.assertEqual(summary.summaries[1].winner, 'Test Winner')
        self.assertEqual(summary.summaries[1].fastest_lap_time, '1:20.000')
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/data.db'
            ScheduleRepository(path)._persist(RaceFeed(
                races=[normalize(sample())], updated_at=datetime.now(timezone.utc),
            ))
            repo = ResultsRepository(path)
            with patch('app.results.fetch_season_summaries', return_value=summary) as fetch:
                first = repo.summaries(2026)
                second = repo.summaries(2026)
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(first.summaries, second.summaries)

    def test_missing_fields_and_fastest_not_winner(self):
        feed = normalize_results([
            row(position='2', positionText='2', FastestLap={'rank': '1', 'lap': '12', 'Time': {'time': '1:20.123'}}),
            row(position='1', positionText='D', Constructor=None),
        ], 'https://example.com/results', 'results')
        self.assertEqual([r.position for r in feed.entries], [1, 2])
        self.assertEqual(feed.entries[0].classification, 'D')
        self.assertEqual(feed.entries[0].team, 'Unknown team')
        self.assertEqual(feed.entries[0].points, 0.5)
        self.assertIsNone(feed.entries[0].time)
        self.assertEqual(feed.fastest_lap.lap, 12)
        qualifying = normalize_results([row(Q1='1:20.000')], 'https://example.com/qualifying', 'qualifying')
        self.assertIsNone(qualifying.entries[0].q2)
        self.assertIsNone(qualifying.fastest_lap)

    def test_race_story_contains_only_supported_result_facts(self):
        feed = normalize_results([
            row(position='1', grid='4', Driver={'givenName': 'Winner', 'familyName': 'Driver'}),
            row(position='2', grid='10', Driver={'givenName': 'Gained', 'familyName': 'Driver'},
                FastestLap={'rank': '1', 'lap': '35', 'Time': {'time': '1:20.123'}}),
            row(position='12', grid='3', Driver={'givenName': 'Lost', 'familyName': 'Driver'}),
        ], 'https://example.com/results', 'results')
        story = build_race_story(feed)
        self.assertEqual([event.kind for event in story.events], [
            'finish', 'gain', 'loss', 'fastest_lap',
        ])
        self.assertEqual(story.events[1].driver, 'Gained Driver')
        self.assertEqual(story.events[-1].lap, 35)

    def test_independent_cache_and_outage(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = ResultsRepository(f'{directory}/cache.db')
            feed = normalize_results([row()], 'https://example.com', 'results')
            with patch('app.results.fetch_results', return_value=feed) as fetch:
                repo.load(2024, 1, 'results')
                repo.load(2024, 1, 'results')
                repo.load(2024, 1, 'qualifying')
                self.assertEqual(fetch.call_count, 2)
            with patch('app.results.datetime') as clock, patch('app.results.fetch_results', side_effect=RuntimeError):
                clock.now.return_value = datetime.now(timezone.utc) + timedelta(days=2)
                self.assertTrue(repo.load(2024, 1, 'results').stale)
                with self.assertRaises(RuntimeError):
                    repo.load(2024, 2, 'results')

    def test_empty_cache_expires_and_api_states(self):
        empty = normalize_results([], 'https://example.com', 'results')
        with tempfile.TemporaryDirectory() as directory, patch.dict('os.environ', {'DATABASE_PATH': f'{directory}/cache.db'}), TestClient(app) as client:
            repo = app.state.results
            with patch('app.results.fetch_results', return_value=empty) as fetch:
                repo.load(2024, 1, 'results')
                with patch('app.results.datetime') as clock:
                    clock.now.return_value = datetime.now(timezone.utc) + timedelta(minutes=6)
                    repo.load(2024, 1, 'results')
                self.assertEqual(fetch.call_count, 2)
            self.assertEqual(client.get('/api/v1/races/invalid/results').status_code, 422)
            with patch.object(app.state.schedules, 'season', return_value=RaceFeed(races=[normalize(sample())], updated_at=datetime.now(timezone.utc))):
                self.assertEqual(client.get('/api/v1/races/2026-99/results').status_code, 404)
                with patch.object(repo, 'load', return_value=empty):
                    self.assertEqual(client.get('/api/v1/races/2026-1/results').json()['entries'], [])
                with patch.object(repo, 'load', side_effect=RuntimeError):
                    self.assertEqual(client.get('/api/v1/races/2026-1/qualifying').status_code, 503)

    def test_identity_grid_and_result_revision_are_separate(self):
        driver = {
            'driverId': 'test-driver', 'givenName': 'Test', 'familyName': 'Driver',
            'nationality': 'Test', 'dateOfBirth': '2000-01-01',
            'permanentNumber': '42',
        }
        team = {'constructorId': 'test-team', 'name': 'Test Team'}
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/data.db'
            schedules = ScheduleRepository(path)
            schedules._persist(RaceFeed(
                races=[normalize(sample())], updated_at=datetime.now(timezone.utc),
            ))
            repo = ResultsRepository(path)
            qualifying = repo._persist(2026, 1, 'qualifying', normalize_results([
                row(position='3', Driver={'givenName': 'Test', 'familyName': 'Driver'},
                    Constructor={'name': 'Test Team'},
                    Q1='1:20.0', Q2='1:19.5', Q3='1:19.0'),
            ], 'https://example.com/qualifying', 'qualifying'))
            race = repo._persist(2026, 1, 'results', normalize_results([
                row(position='2', grid='8', points='18', Driver=driver,
                    Constructor=team, laps='58'),
            ], 'https://example.com/results', 'results'))
            revised = repo._persist(2026, 1, 'results', normalize_results([
                row(position='20', positionText='D', grid='8', points='0',
                    Driver=driver, Constructor=team, laps='58', status='Disqualified'),
            ], 'https://example.com/results', 'results'))
            self.assertEqual(qualifying.entries[0].driver_id, race.entries[0].driver_id)
            self.assertEqual(race.entries[0].driver_id, revised.entries[0].driver_id)
            with closing(sqlite3.connect(path)) as db:
                grid = db.execute('''SELECT qualifying_position,grid_position
                    FROM starting_grids''').fetchone()
                result = db.execute('''SELECT finish_position,classification,result_status
                    FROM race_results''').fetchone()
                revision = db.execute('''SELECT previous_position,new_position,
                    previous_points,new_points FROM result_revisions''').fetchone()
                counts = tuple(db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
                               for table in ('drivers', 'teams', 'team_seasons',
                                             'driver_team_assignments', 'raw_source_records'))
            self.assertEqual(grid, (3, 8))
            self.assertEqual(result, (20, 'D', 'unknown'))
            self.assertEqual(revision, (2, 20, 18.0, 0.0))
            self.assertEqual(counts[:4], (1, 1, 1, 1))
            self.assertEqual(counts[4], 4)


if __name__ == '__main__':
    unittest.main()
