import unittest

from app.localization_worker import _protect_proper_names, _restore_proper_names


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


if __name__ == '__main__':
    unittest.main()
