import tempfile
import unittest
from contextlib import closing

from app.car_catalog import _store, chassis_name, team_profile_url
from app.data_schema import connect, migrate


class CarCatalogTests(unittest.TestCase):
    def test_official_chassis_is_parsed_and_stored_as_one_season_car(self):
        self.assertEqual(chassis_name('Team Profile Chassis MCL40 Power Unit Mercedes'), 'MCL40')
        self.assertEqual(chassis_name('Technical ChiefNameChassisMCL40Power UnitMercedes'),
                         'MCL40')
        self.assertEqual(team_profile_url('McLaren'),
                         'https://www.formula1.com/en/teams/mclaren')
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            migrate(path)
            with closing(connect(path)) as db, db:
                db.execute("""INSERT INTO seasons
                    (season_id,year,status,created_at,updated_at)
                    VALUES ('sea_2026',2026,'active','now','now')""")
                db.execute("INSERT INTO teams VALUES ('mclaren','McLaren',NULL,'active','now','now')")
                db.execute("INSERT INTO team_seasons(team_season_id,team_id,season_id,display_name) VALUES ('mclaren26','mclaren','sea_2026','McLaren')")
            stored = _store(path, 2026, {'mclaren': (
                'MCL40', 'https://www.formula1.com/en/teams/mclaren')})
            self.assertEqual(stored[0]['car_name'], 'MCL40')
            with closing(connect(path)) as db:
                self.assertEqual(db.execute('SELECT car_name FROM team_seasons').fetchone()[0], 'MCL40')
                self.assertEqual(db.execute('SELECT name FROM car_models').fetchone()[0], 'MCL40')

    def test_team_aliases_use_the_same_official_profile(self):
        self.assertEqual(team_profile_url('Haas F1 Team'),
                         'https://www.formula1.com/en/teams/haas')
        self.assertEqual(team_profile_url('Red Bull Racing'),
                         'https://www.formula1.com/en/teams/red-bull-racing')


if __name__ == '__main__':
    unittest.main()
