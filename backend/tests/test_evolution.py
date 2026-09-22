import tempfile
import unittest
from contextlib import closing
from datetime import datetime, timezone

from app.data_schema import connect
from app.evolution import load_evolution
from app.localization import upsert_translation
from app.models import RaceFeed
from app.providers.jolpica import normalize
from app.repositories.schedules import ScheduleRepository
from test_schedules import sample


class EvolutionTests(unittest.TestCase):
    def test_sources_belong_to_upgrade_and_season(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            ScheduleRepository(path)._persist(RaceFeed(
                races=[normalize(sample())], updated_at=datetime.now(timezone.utc)))
            with closing(connect(path)) as db, db:
                season = db.execute('SELECT season_id FROM seasons').fetchone()[0]
                race = db.execute('SELECT race_id FROM races').fetchone()[0]
                db.execute("INSERT INTO teams(team_id,canonical_name,status,created_at,updated_at) VALUES ('t','Test','active','2026-01-01','2026-01-01')")
                db.execute("INSERT INTO team_seasons(team_season_id,team_id,season_id,display_name,car_name) VALUES ('ts','t',?,'Mercedes','W17')", (season,))
                db.execute("INSERT INTO car_models(car_model_id,team_season_id,name,season_id) VALUES ('car_2026_mercedes','ts','W17',?)", (season,))
                db.execute("INSERT INTO technical_eras(technical_era_id,name) VALUES ('era','Test')")
                db.execute("INSERT INTO car_component_types(component_type_id,technical_era_id,canonical_name) VALUES ('floor','era','Floor')")
                for uid in ('sourced', 'unsourced'):
                    db.execute('''INSERT INTO upgrades(upgrade_id,team_season_id,introduced_race_id,
                        component_type_id,title,status,confidence,created_at,updated_at)
                        VALUES (?,'ts',?,'floor','Test floor','tested','high','2026-01-01','2026-01-01')''', (uid, race))
                db.execute("INSERT INTO evolution_source_documents VALUES ('source','https://example.com/test','Test','team_official','2026-01-01')")
                db.execute("INSERT INTO evolution_source_revisions VALUES ('revision','source',?,'post_race',NULL,'2026-01-01','Original text','hash')", (race,))
                db.execute("INSERT INTO evidence_anchors VALUES ('anchor','source','revision','Original text','anchor-hash')")
                db.execute("INSERT INTO evolution_claims VALUES ('claim','claim-key',?,'ts','floor','anchor','Test floor',NULL,NULL,'tested','confirmed','1','published','2026-01-01','2026-01-01')", (race,))
                db.execute("INSERT INTO claim_evidence VALUES ('claim','anchor','change')")
                db.execute("INSERT INTO upgrade_claims VALUES ('sourced','claim','accepted','2026-01-01','2026-01-01')")
            feed = load_evolution(path, 2026)
            self.assertEqual([u.id for u in feed.upgrades], ['sourced'])
            self.assertEqual(feed.upgrades[0].race_id, '2026-1')
            self.assertEqual(feed.upgrades[0].status, 'tested')
            self.assertEqual(feed.upgrades[0].component_id, 'floor')
            self.assertEqual(feed.timeline[0].race_id, '2026-1')
            self.assertEqual(feed.timeline[0].upgrade_ids, ['sourced'])
            self.assertEqual(feed.cars[0].car_name, 'W17')
            self.assertEqual(str(feed.cars[0].source_url), 'https://www.formula1.com/en/teams/mercedes')
            with closing(connect(path)) as db, db:
                upsert_translation(db, 'upgrade', 'sourced', 'title', 'zh-CN', '已验证的底板升级', 'test')
            chinese = load_evolution(path, 2026, 'zh-CN')
            self.assertEqual(chinese.upgrades[0].id, feed.upgrades[0].id)
            self.assertEqual(chinese.upgrades[0].status, feed.upgrades[0].status)
            self.assertEqual(chinese.upgrades[0].title, '已验证的底板升级')
            self.assertIsNone(chinese.upgrades[0].change)
            self.assertIsNone(chinese.upgrades[0].goal)
            self.assertEqual(load_evolution(path, 2025).upgrades, [])
            with closing(connect(path)) as db, db:
                db.execute("UPDATE evolution_source_documents SET canonical_url='javascript:alert(1)'")
            self.assertEqual(load_evolution(path, 2026).upgrades, [])
