import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from pydantic import ValidationError
from app.editorial_media import EditorialMedia, load_media


class EditorialMediaTests(unittest.TestCase):
    def test_only_reviewed_matching_race_is_published(self):
        record = dict(id='image', race_id='2026-1', role='home',
                      url='https://example.com/image.jpg', source_url='https://example.com/source',
                      credit='Test photographer', license='CC BY 4.0', caption='Test image',
                      reviewed_by='Test reviewer', reviewed=True)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'media.json'
            path.write_text(json.dumps([record, {**record, 'id': 'pending', 'reviewed': False},
                                        {**record, 'id': 'other-race', 'race_id': '2026-2'}]))
            with patch.dict(os.environ, {'EDITORIAL_MEDIA_PATH': str(path)}):
                self.assertEqual([item.id for item in load_media('2026-1')], ['image'])
                self.assertEqual(load_media('2026-3'), [])
        self.assertTrue(EditorialMedia.model_validate(record).spoiler)
        with self.assertRaises(ValidationError):
            EditorialMedia.model_validate({**record, 'url': 'http://example.com/image.jpg'})
        with self.assertRaises(ValidationError):
            EditorialMedia.model_validate({**record, 'license': ''})
