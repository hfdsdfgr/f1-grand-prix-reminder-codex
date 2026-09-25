"""Read reviewed media mappings; images never establish technical claims."""
import json
import os
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, HttpUrl, Field, field_validator


class EditorialMedia(BaseModel):
    id: str = Field(min_length=1)
    race_id: str = Field(pattern=r'^(19[5-9][0-9]|20[0-9]{2}|2100)-([1-9][0-9]?)$')
    role: Literal['home', 'briefing', 'story']
    topic: str | None = None
    url: HttpUrl
    source_url: HttpUrl
    credit: str = Field(min_length=1)
    license: str = Field(min_length=1)
    caption: str = Field(min_length=1)
    spoiler: bool = True
    reviewed_by: str = Field(min_length=1)
    reviewed: bool = False

    @field_validator('url', 'source_url')
    @classmethod
    def secure_url(cls, value):
        if value.scheme != 'https':
            raise ValueError('Reviewed media must use HTTPS')
        return value


def load_media(race_id: str) -> list[EditorialMedia]:
    configured = os.getenv('EDITORIAL_MEDIA_PATH')
    if not configured:
        return []
    records = json.loads(Path(configured).read_text(encoding='utf-8'))
    media = [EditorialMedia.model_validate(record) for record in records]
    return [item for item in media if item.reviewed and item.race_id == race_id]
