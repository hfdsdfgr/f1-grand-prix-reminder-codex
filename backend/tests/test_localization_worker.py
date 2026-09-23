import unittest
import tempfile
from unittest.mock import patch

from app.data_schema import migrate
from app.localization_worker import _protect_proper_names, _proper_names, _restore_proper_names, localize_race


class LocalizationWorkerTest(unittest.TestCase):
    def test_proper_names_are_hidden_from_translation_and_restored(self):
        items = [{'entity_type': 'brief_fact', 'entity_id': 'brief-1',
                  'field': 'race_assessment',
                  'text': 'Kimi Antonelli won for Mercedes.'}]

        protected, tokens, required = _protect_proper_names(
            items, ['Kimi Antonelli', 'Mercedes'])

        self.assertNotIn('Kimi Antonelli', protected[0]['text'])
        self.assertNotIn('Mercedes', protected[0]['text'])
        self.assertEqual(len(required[('brief_fact', 'brief-1', 'race_assessment')]), 2)
        translated = protected[0]['text'].replace('won for', '代表').replace('.', '夺冠。')
        restored = _restore_proper_names(translated, tokens)
        self.assertIn('Kimi Antonelli', restored)
        self.assertIn('Mercedes', restored)


class LocalizationJobTest(unittest.IsolatedAsyncioTestCase):
    async def test_translates_in_small_batches_and_skips_existing_fields(self):
        class Translator:
            calls = []

            async def localize(self, items, language):
                self.calls.append(len(items))
                return [{**item, 'text': '中文 ' + item['text']} for item in items]

        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            migrate(path)
            items = [{'entity_type': 'brief_fact', 'entity_id': 'brief-1',
                      'field': f'field_{index}', 'text': f'fact {index}'} for index in range(7)]
            translator = Translator()
            with patch('app.localization_worker._items', return_value=items), patch(
                    'app.localization_worker._proper_names', return_value=[]):
                first = await localize_race(path, '2026-1', provider=translator)
                second = await localize_race(path, '2026-1', provider=translator)
            self.assertEqual(first['stored'], 7)
            self.assertEqual(second['candidates'], 0)
            self.assertEqual(translator.calls, [6, 1])

    async def test_driver_surname_and_unaccented_alias_are_protected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = f'{directory}/db.sqlite'
            migrate(path)
            from app.data_schema import connect
            from contextlib import closing
            with closing(connect(path)) as db, db:
                db.execute("INSERT INTO drivers(driver_id,full_name,created_at,updated_at) VALUES ('d1','Nico Hülkenberg','2026-01-01','2026-01-01')")
            names = _proper_names(path)
            self.assertIn('Hulkenberg', names)
            protected, _, _ = _protect_proper_names([{'entity_type': 'brief_fact',
                'entity_id': 'brief-1', 'field': 'race_assessment',
                'text': 'Hulkenberg finished ahead.'}], names)
            self.assertNotIn('Hulkenberg', protected[0]['text'])


if __name__ == '__main__':
    unittest.main()
