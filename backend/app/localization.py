"""Presentation-only localization for validated content.

These helpers intentionally know nothing about Claim or Upgrade identity.  They
only read/write wording keyed by an already-existing entity and field.
"""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone

SUPPORTED_LANGUAGES = {'en', 'zh-CN'}


def requested_language(language: str | None) -> str:
    return language if language in SUPPORTED_LANGUAGES else 'en'


def text(db: sqlite3.Connection, entity_type: str, entity_id: str, field: str,
         language: str | None, canonical: str | None) -> str | None:
    if canonical is None:
        return None
    language = requested_language(language)
    row = db.execute('''SELECT text FROM content_localizations
        WHERE entity_type=? AND entity_id=? AND field=? AND language IN (?, 'en')
        ORDER BY CASE language WHEN ? THEN 0 ELSE 1 END LIMIT 1''',
        (entity_type, entity_id, field, language, language)).fetchone()
    return row[0] if row else canonical


def seed_canonical(db: sqlite3.Connection, entity_type: str, entity_id: str,
                   values: dict[str, str | None]) -> None:
    now = datetime.now(timezone.utc).isoformat()
    for field, value in values.items():
        if value is None:
            continue
        db.execute('''INSERT INTO content_localizations
            (entity_type,entity_id,field,language,text,provider,created_at,updated_at)
            VALUES (?,?,?,?,?,'canonical',?,?)
            ON CONFLICT(entity_type,entity_id,field,language) DO NOTHING''',
            (entity_type, entity_id, field, 'en', value, now, now))


def upsert_translation(db: sqlite3.Connection, entity_type: str, entity_id: str,
                       field: str, language: str, value: str | None,
                       provider: str = 'deepseek') -> None:
    if value is None or language not in SUPPORTED_LANGUAGES:
        return
    now = datetime.now(timezone.utc).isoformat()
    db.execute('''INSERT INTO content_localizations
        (entity_type,entity_id,field,language,text,provider,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,?)
        ON CONFLICT(entity_type,entity_id,field,language) DO UPDATE SET
          text=excluded.text,provider=excluded.provider,updated_at=excluded.updated_at''',
        (entity_type, entity_id, field, language, value, provider, now, now))
