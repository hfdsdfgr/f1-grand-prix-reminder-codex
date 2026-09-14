from contextlib import closing
from datetime import datetime, timezone

from app.data_schema import (
    PROVIDER_ID, connect, migrate, new_id, record_provider_health, store_raw,
)
from app.models import RaceFeed
from app.circuit_layouts import circuit_layout
from app.providers.jolpica import fetch_season


class ScheduleRepository:
    """Persist normalized schedules; serve marked stale data during outages."""

    def __init__(self, path: str):
        self.path = path
        migrate(path)
        self._backfill_cache()

    @staticmethod
    def _iso(value):
        return value.astimezone(timezone.utc).isoformat() if value else None

    def _backfill_cache(self) -> None:
        # ponytail: an F1 cache has at most one small row per season; an
        # idempotent backfill is simpler than maintaining a second migration tool.
        with closing(connect(self.path)) as db:
            rows = list(db.execute('SELECT season, payload FROM schedules'))
        for season, payload in rows:
            feed = self._persist(RaceFeed.model_validate_json(payload))
            with closing(connect(self.path)) as db, db:
                db.execute('UPDATE schedules SET payload=? WHERE season=?',
                           (feed.model_dump_json(), season))

    def _persist(self, feed: RaceFeed) -> RaceFeed:
        """Upsert current entities and append schedule history; keep API shape stable."""
        now = datetime.now(timezone.utc).isoformat()
        hydrated = []
        with closing(connect(self.path)) as db, db:
            for race in feed.races:
                season_row = db.execute(
                    'SELECT season_id FROM seasons WHERE year=?', (race.season,),
                ).fetchone()
                season_id = season_row[0] if season_row else new_id('sea')
                season_status = 'active' if race.season == datetime.now(timezone.utc).year else (
                    'completed' if race.season < datetime.now(timezone.utc).year else 'upcoming'
                )
                db.execute('''INSERT INTO seasons
                    (season_id,year,status,created_at,updated_at) VALUES (?,?,?,?,?)
                    ON CONFLICT(year) DO UPDATE SET status=excluded.status, updated_at=excluded.updated_at''',
                    (season_id, race.season, season_status, now, now))

                external_race = race.provider_external_id or race.id
                identity = db.execute('''SELECT race_id FROM race_external_identities
                    WHERE provider_id='prv_jolpica' AND external_id=?''', (external_race,)).fetchone()
                same_round = db.execute('''SELECT race_id FROM races
                    WHERE season_id=? AND round=?''', (season_id, race.round)).fetchone()
                race_id = identity[0] if identity else (
                    same_round[0] if same_round else new_id('rac')
                )
                existing_race = db.execute(
                    'SELECT circuit_id FROM races WHERE race_id=?', (race_id,),
                ).fetchone()

                external_circuit = race.circuit_external_id
                if external_circuit is None and race.circuit_id:
                    known = db.execute('''SELECT external_id
                        FROM circuit_external_identities
                        WHERE provider_id=? AND circuit_id=?''',
                        (PROVIDER_ID, race.circuit_id)).fetchone()
                    external_circuit = known[0] if known else None
                circuit_identity = db.execute('''SELECT circuit_id FROM circuit_external_identities
                    WHERE provider_id='prv_jolpica' AND external_id=?''',
                    (external_circuit,),).fetchone() if external_circuit else None
                circuit_id = circuit_identity[0] if circuit_identity else (
                    existing_race[0] if existing_race else new_id('cir')
                )
                db.execute('''INSERT INTO circuits
                    (circuit_id,canonical_name,country,created_at,updated_at) VALUES (?,?,?,?,?)
                    ON CONFLICT(circuit_id) DO UPDATE SET canonical_name=excluded.canonical_name,
                    country=excluded.country, updated_at=excluded.updated_at''',
                    (circuit_id, race.circuit, race.country, now, now))
                if external_circuit:
                    db.execute('''INSERT INTO circuit_external_identities
                        (provider_id,external_id,circuit_id,first_seen_at,last_seen_at,confidence,status)
                        VALUES (?,?,?,?,?,?,?) ON CONFLICT(provider_id, external_id)
                        DO UPDATE SET last_seen_at=excluded.last_seen_at''',
                        (PROVIDER_ID, external_circuit, circuit_id, now, now, 'high', 'active'))
                layout = circuit_layout(external_circuit, race.season) or race.circuit_layout
                if layout:
                    db.execute('''INSERT INTO circuit_layouts
                        (layout_id,circuit_id,valid_from,valid_to,asset_path,view_box,
                         turns,source_url,source_license,verified_at)
                        VALUES (?,?,?,?,?,'0 0 500 500',?,?,?,?)
                        ON CONFLICT(layout_id) DO UPDATE SET
                        circuit_id=excluded.circuit_id, asset_path=excluded.asset_path,
                        turns=excluded.turns, source_url=excluded.source_url,
                        source_license=excluded.source_license,
                        verified_at=excluded.verified_at''',
                        (layout.id, circuit_id, layout.valid_from, None,
                         layout.asset_path, layout.turns, str(layout.source),
                         layout.license, now))

                db.execute('''INSERT INTO races
                    (race_id,season_id,circuit_id,round,display_name,scheduled_start,status,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(race_id) DO UPDATE SET circuit_id=excluded.circuit_id,
                    round=excluded.round, display_name=excluded.display_name,
                    scheduled_start=excluded.scheduled_start, status=excluded.status,
                    updated_at=excluded.updated_at''',
                    (race_id, season_id, circuit_id, race.round, race.name,
                     self._iso(race.starts_at), race.status, now, now))
                db.execute('''INSERT INTO race_external_identities
                    (provider_id,external_id,race_id,first_seen_at,last_seen_at,confidence,status)
                    VALUES (?,?,?,?,?,?,?) ON CONFLICT(provider_id, external_id)
                    DO UPDATE SET last_seen_at=excluded.last_seen_at''',
                    (PROVIDER_ID, external_race, race_id, now, now, 'high', 'active'))
                if race.raw_payload is not None:
                    store_raw(db, f'race:{external_race}', race.raw_payload)

                sessions = []
                for session in race.sessions:
                    old = db.execute('''SELECT session_id, scheduled_start FROM sessions
                        WHERE race_id=? AND display_name=?''', (race_id, session.kind)).fetchone()
                    session_id = old[0] if old else new_id('ses')
                    new_start = self._iso(session.starts_at)
                    if old and old[1] != new_start:
                        db.execute('''INSERT OR IGNORE INTO schedule_revisions VALUES
                            (?,?,?,?,?,?,?)''',
                            (new_id('rev'), session_id, old[1], new_start,
                             'provider_schedule_update', PROVIDER_ID, now))
                    db.execute('''INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(session_id) DO UPDATE SET
                        session_type=excluded.session_type, display_name=excluded.display_name,
                        scheduled_start=excluded.scheduled_start,
                        scheduled_end=excluded.scheduled_end, actual_start=excluded.actual_start,
                        actual_end=excluded.actual_end, status=excluded.status,
                        updated_at=excluded.updated_at''',
                        (session_id, race_id, session.session_type or 'other',
                         session.display_name or session.kind, new_start,
                         self._iso(session.scheduled_end), self._iso(session.actual_start),
                         self._iso(session.actual_end), session.status, now, now))
                    sessions.append(session.model_copy(update={
                        'internal_id': session_id,
                        'session_type': session.session_type or 'other',
                        'display_name': session.display_name or session.kind,
                    }))
                hydrated.append(race.model_copy(update={
                    'internal_id': race_id, 'circuit_id': circuit_id, 'sessions': sessions,
                    'circuit_layout': layout,
                }))
        return feed.model_copy(update={'races': hydrated})

    def season(self, season: int) -> RaceFeed:
        with closing(connect(self.path)) as db:
            row = db.execute('SELECT payload FROM schedules WHERE season = ?', (season,)).fetchone()
        cached = RaceFeed.model_validate_json(row[0]) if row else None
        now = datetime.now(timezone.utc)
        ttl = 3600 if season >= now.year else 86400
        if cached and (now - cached.updated_at).total_seconds() < ttl:
            return self._persist(cached)
        try:
            feed = RaceFeed(races=fetch_season(season), updated_at=now)
        except Exception as exc:
            record_provider_health(
                self.path, False,
                schema_changed=isinstance(exc, (KeyError, TypeError, ValueError)),
            )
            if cached:
                return self._persist(cached).model_copy(update={'stale': True})
            raise
        record_provider_health(self.path, True)
        feed = self._persist(feed)
        with closing(connect(self.path)) as db, db:
            db.execute('INSERT OR REPLACE INTO schedules VALUES (?, ?)', (season, feed.model_dump_json()))
        return feed

    def health(self):
        with closing(connect(self.path)) as db:
            row = db.execute('''SELECT p.provider_id,p.name,h.status,h.last_success,
                h.last_failure,h.consecutive_failures,h.parser_version,h.schema_version
                FROM providers p JOIN provider_health h USING(provider_id)
                WHERE p.provider_id=?''', (PROVIDER_ID,)).fetchone()
        return dict(zip((
            'provider_id', 'name', 'status', 'last_success', 'last_failure',
            'consecutive_failures', 'parser_version', 'schema_version',
        ), row))

    def revisions(self, public_race_id: str):
        with closing(connect(self.path)) as db:
            rows = db.execute('''SELECT sr.revision_id,sr.session_id,s.display_name,
                sr.previous_start,sr.new_start,sr.reason,sr.source_provider_id,sr.created_at
                FROM schedule_revisions sr JOIN sessions s USING(session_id)
                JOIN race_external_identities rei USING(race_id)
                WHERE rei.provider_id=? AND rei.external_id=? ORDER BY sr.created_at''',
                (PROVIDER_ID, public_race_id)).fetchall()
        keys = ('revision_id', 'session_id', 'session', 'previous_start', 'new_start',
                'reason', 'source_provider_id', 'created_at')
        return [dict(zip(keys, row)) for row in rows]
