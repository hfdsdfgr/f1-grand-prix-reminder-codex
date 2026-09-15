"""Normalized race/qualifying results, with independent persistent caches."""
import json
from contextlib import closing
from datetime import datetime, timezone
from typing import Literal

import httpx
from pydantic import BaseModel, Field, HttpUrl

from app.data_schema import (
    PROVIDER_ID, connect, migrate, new_id, record_provider_health, store_raw,
)
from app.models import RaceSummary
from app.providers.fastf1 import SOURCE_URL as FASTF1_SOURCE_URL, fetch_strategy_rows
from app.providers.jolpica import BASE_URL, fetch_driver_standings


class Result(BaseModel):
    internal_id: str | None = None
    driver_id: str | None = None
    team_id: str | None = None
    position: int
    classification: str
    driver: str
    team: str
    grid: int | None = None
    points: float | None = None
    time: str | None = None
    status: str | None = None
    q1: str | None = None
    q2: str | None = None
    q3: str | None = None
    laps_completed: int | None = None
    fastest_lap_number: int | None = None
    fastest_lap_time: str | None = None
    result_status: Literal['provisional', 'official', 'revised', 'unknown'] = 'unknown'
    driver_external_id: str | None = Field(default=None, exclude=True)
    team_external_id: str | None = Field(default=None, exclude=True)
    given_name: str | None = Field(default=None, exclude=True)
    family_name: str | None = Field(default=None, exclude=True)
    nationality: str | None = Field(default=None, exclude=True)
    date_of_birth: str | None = Field(default=None, exclude=True)
    permanent_number: str | None = Field(default=None, exclude=True)


class FastestLap(BaseModel):
    driver: str
    lap: int
    time: str


class ResultsFeed(BaseModel):
    entries: list[Result]
    fastest_lap: FastestLap | None = None
    source: HttpUrl
    updated_at: datetime
    stale: bool = False
    raw_rows: list[dict] | None = Field(default=None, exclude=True)


class RaceStoryEvent(BaseModel):
    kind: Literal['finish', 'gain', 'loss', 'fastest_lap']
    driver: str
    grid_position: int | None = None
    finish_position: int | None = None
    lap: int | None = None
    time: str | None = None


class RaceStory(BaseModel):
    events: list[RaceStoryEvent]
    source: HttpUrl
    updated_at: datetime
    stale: bool = False


class SeasonSummaryFeed(BaseModel):
    summaries: dict[int, RaceSummary]
    updated_at: datetime
    stale: bool = False
    winner_races: list[dict] | None = Field(default=None, exclude=True)
    fastest_races: list[dict] | None = Field(default=None, exclude=True)


class SeasonRosterEntry(BaseModel):
    driver_id: str
    driver: str
    team_id: str
    team: str


class SeasonRosterFeed(BaseModel):
    entries: list[SeasonRosterEntry]
    source: HttpUrl
    updated_at: datetime
    stale: bool = False
    raw_rows: list[dict] | None = Field(default=None, exclude=True)


class StrategyStint(BaseModel):
    compound: Literal['Soft', 'Medium', 'Hard', 'Intermediate', 'Wet']
    start_lap: int
    end_lap: int
    tyre_age_at_start: int | None = None
    pit_lap: int | None = None


class DriverStrategy(BaseModel):
    driver: str
    stints: list[StrategyStint]


class StrategyFeed(BaseModel):
    drivers: list[DriverStrategy]
    source: HttpUrl
    updated_at: datetime
    stale: bool = False


def normalize_results(rows: list[dict], source: str, kind: str) -> ResultsFeed:
    entries = []
    fastest = None
    for row in rows:
        driver_data = row['Driver']
        team_data = row.get('Constructor') or {}
        driver = f"{driver_data['givenName']} {driver_data['familyName']}"
        lap = row.get('FastestLap', {})
        entries.append(Result(
            position=int(row['position']), classification=row.get('positionText', row['position']),
            driver=driver, team=team_data.get('name') or 'Unknown team',
            grid=int(row['grid']) if row.get('grid') is not None else None,
            points=float(row['points']) if row.get('points') is not None else None,
            time=row.get('Time', {}).get('time'), status=row.get('status'),
            q1=row.get('Q1') or None, q2=row.get('Q2') or None, q3=row.get('Q3') or None,
            laps_completed=int(row['laps']) if row.get('laps') is not None else None,
            fastest_lap_number=int(lap['lap']) if lap.get('lap') else None,
            fastest_lap_time=lap.get('Time', {}).get('time'),
            driver_external_id=driver_data.get('driverId'),
            team_external_id=team_data.get('constructorId'),
            given_name=driver_data.get('givenName'), family_name=driver_data.get('familyName'),
            nationality=driver_data.get('nationality'),
            date_of_birth=driver_data.get('dateOfBirth'),
            permanent_number=driver_data.get('permanentNumber'),
        ))
        if kind == 'results' and str(lap.get('rank')) == '1' and lap.get('Time', {}).get('time') and lap.get('lap'):
            fastest = FastestLap(driver=driver, lap=int(lap['lap']), time=lap['Time']['time'])
    return ResultsFeed(entries=sorted(entries, key=lambda r: r.position), fastest_lap=fastest,
                       source=source, updated_at=datetime.now(timezone.utc), raw_rows=rows)


def build_race_story(feed: ResultsFeed) -> RaceStory:
    """Derive only facts supported by final classification and fastest-lap data."""
    events = []
    winner = next((entry for entry in feed.entries if entry.position == 1), None)
    if winner:
        events.append(RaceStoryEvent(
            kind='finish', driver=winner.driver, grid_position=winner.grid,
            finish_position=winner.position,
        ))
    grid_entries = [
        entry for entry in feed.entries
        if entry.grid is not None and entry.grid > 0 and entry.position > 0
    ]
    if grid_entries:
        gain = max(grid_entries, key=lambda entry: entry.grid - entry.position)
        if gain.grid > gain.position:
            events.append(RaceStoryEvent(
                kind='gain', driver=gain.driver, grid_position=gain.grid,
                finish_position=gain.position,
            ))
        loss = max(grid_entries, key=lambda entry: entry.position - entry.grid)
        if loss.position > loss.grid:
            events.append(RaceStoryEvent(
                kind='loss', driver=loss.driver, grid_position=loss.grid,
                finish_position=loss.position,
            ))
    if feed.fastest_lap:
        events.append(RaceStoryEvent(
            kind='fastest_lap', driver=feed.fastest_lap.driver,
            lap=feed.fastest_lap.lap, time=feed.fastest_lap.time,
        ))
    return RaceStory(
        events=events, source=feed.source, updated_at=feed.updated_at, stale=feed.stale,
    )


def fetch_results(season: int, round_number: int, kind: str) -> ResultsFeed:
    source = f'{BASE_URL}/{season}/{round_number}/{kind}/'
    response = httpx.get(source, params={'limit': 100}, timeout=15)
    response.raise_for_status()
    races = response.json()['MRData']['RaceTable']['Races']
    rows = races[0]['Results' if kind == 'results' else 'QualifyingResults'] if races else []
    return normalize_results(rows, source, kind)


def fetch_season_summaries(season: int) -> SeasonSummaryFeed:
    def request(path: str) -> list[dict]:
        response = httpx.get(f'{BASE_URL}/{season}/{path}/', params={'limit': 100}, timeout=15)
        response.raise_for_status()
        return response.json()['MRData']['RaceTable']['Races']

    winner_races = request('results/1')
    fastest_races = request('fastest/1/results')
    summaries = {}
    for race in winner_races:
        rows = race.get('Results') or []
        if not rows:
            continue
        row = rows[0]
        driver = row['Driver']
        summaries[int(race['round'])] = RaceSummary(
            winner=f"{driver['givenName']} {driver['familyName']}",
            winner_team=(row.get('Constructor') or {}).get('name'),
        )
    for race in fastest_races:
        rows = race.get('Results') or []
        if not rows:
            continue
        row = rows[0]
        driver = row['Driver']
        lap = row.get('FastestLap') or {}
        previous = summaries.get(int(race['round']), RaceSummary())
        summaries[int(race['round'])] = previous.model_copy(update={
            'fastest_lap_driver': f"{driver['givenName']} {driver['familyName']}",
            'fastest_lap_time': (lap.get('Time') or {}).get('time'),
            'fastest_lap_number': int(lap['lap']) if lap.get('lap') else None,
        })
    return SeasonSummaryFeed(
        summaries=summaries, updated_at=datetime.now(timezone.utc),
        winner_races=winner_races, fastest_races=fastest_races,
    )


def normalize_roster(rows: list[dict], season: int) -> SeasonRosterFeed:
    """Keep only driver/team pairs explicitly published in season standings."""
    return SeasonRosterFeed(
        entries=[],
        source=f'{BASE_URL}/{season}/driverstandings/',
        updated_at=datetime.now(timezone.utc),
        raw_rows=rows,
    )


def normalize_strategy(rows: list[dict]) -> StrategyFeed:
    drivers: dict[str, list[StrategyStint]] = {}
    for row in rows:
        driver = row.get('driver')
        if not driver:
            continue
        try:
            stint = StrategyStint.model_validate(row)
        except (TypeError, ValueError):
            continue
        drivers.setdefault(driver, []).append(stint)
    return StrategyFeed(
        drivers=[DriverStrategy(driver=driver, stints=stints)
                 for driver, stints in drivers.items()],
        source=FASTF1_SOURCE_URL,
        updated_at=datetime.now(timezone.utc),
    )


class ResultsRepository:
    def __init__(self, path: str):
        self.path = path
        migrate(path)
        self._backfill_cache()

    def _backfill_cache(self) -> None:
        with closing(connect(self.path)) as db:
            rows = list(db.execute('SELECT key, payload FROM result_cache'))
        for key, payload in rows:
            race_key, kind = key.rsplit('-', 1)
            season, round_number = map(int, race_key.split('-'))
            feed = self._persist(
                season, round_number, kind, ResultsFeed.model_validate_json(payload),
            )
            with closing(connect(self.path)) as db, db:
                db.execute('UPDATE result_cache SET payload=? WHERE key=?',
                           (feed.model_dump_json(), key))

    @staticmethod
    def _identity(
        db, entity: str, external_id: str | None, name: str,
        entry: Result, race_id: str, now: str,
    ) -> str:
        known = entry.driver_id if entity == 'driver' else entry.team_id
        if known:
            table_name = 'drivers' if entity == 'driver' else 'teams'
            known_row = db.execute(
                f'SELECT status FROM {table_name} WHERE {entity}_id=?', (known,),
            ).fetchone()
            if known_row and known_row[0] not in ('merged', 'inactive'):
                return known
        table = f'{entity}_external_identities'
        id_column = f'{entity}_id'
        if external_id:
            row = db.execute(
                f'SELECT {id_column} FROM {table} WHERE provider_id=? AND external_id=?',
                (PROVIDER_ID, external_id),
            ).fetchone()
            if row:
                return row[0]
        name_column = 'full_name' if entity == 'driver' else 'canonical_name'
        entity_table = 'drivers' if entity == 'driver' else 'teams'
        candidates = list(db.execute(f'''SELECT DISTINCT e.{id_column}
            FROM race_entries e JOIN {entity_table} x ON x.{id_column}=e.{id_column}
            WHERE e.race_id=? AND x.{name_column}=?''', (race_id, name)))
        if candidates:
            return candidates[0][0]
        if not external_id:
            # No name-only automatic merge: unresolved identities stay isolated and reviewable.
            internal_id = new_id('drv' if entity == 'driver' else 'tea')
            db.execute('''INSERT INTO review_items
                (review_id,entity_type,entity_id,issue_type,description,confidence,status,created_at)
                VALUES (?,?,?,?,?,?,?,?)''', (
                new_id('rvw'), entity, internal_id, f'{entity}_identity',
                f'Missing provider identity for {name}', 'low', 'open', now,
            ))
            return internal_id
        return new_id('drv' if entity == 'driver' else 'tea')

    @staticmethod
    def _merge_unverified(db, entity: str, canonical_id: str, name: str,
                          race_id: str, season_id: str, round_number: int, now: str) -> None:
        id_column = f'{entity}_id'
        entity_table = 'drivers' if entity == 'driver' else 'teams'
        name_column = 'full_name' if entity == 'driver' else 'canonical_name'
        identity_table = f'{entity}_external_identities'
        duplicates = [row[0] for row in db.execute(f'''SELECT DISTINCT e.{id_column}
            FROM race_entries e JOIN {entity_table} x ON x.{id_column}=e.{id_column}
            WHERE e.race_id=? AND x.{name_column}=? AND e.{id_column}<>?
            AND NOT EXISTS (SELECT 1 FROM {identity_table} i
                            WHERE i.{id_column}=e.{id_column})''',
            (race_id, name, canonical_id))]
        session_ids = [row[0] for row in db.execute(
            'SELECT session_id FROM sessions WHERE race_id=?', (race_id,))]
        for duplicate in duplicates:
            if entity == 'driver':
                for session_id in session_ids:
                    for table in ('session_entries', 'qualifying_results', 'laps',
                                  'tyre_stints', 'pit_stops'):
                        db.execute(f'''UPDATE OR IGNORE {table} SET driver_id=?
                            WHERE driver_id=? AND session_id=?''',
                            (canonical_id, duplicate, session_id))
                        db.execute(f'''DELETE FROM {table}
                            WHERE driver_id=? AND session_id=?''', (duplicate, session_id))
                for table in ('race_entries', 'starting_grids', 'race_results',
                              'result_revisions'):
                    db.execute(f'''UPDATE OR IGNORE {table} SET driver_id=?
                        WHERE driver_id=? AND race_id=?''',
                        (canonical_id, duplicate, race_id))
                    db.execute(f'''DELETE FROM {table} WHERE driver_id=? AND race_id=?''',
                               (duplicate, race_id))
                db.execute('''UPDATE driver_team_assignments SET driver_id=?
                    WHERE driver_id=? AND season_id=? AND race_from=? AND race_to=?''',
                    (canonical_id, duplicate, season_id, round_number, round_number))
            else:
                for session_id in session_ids:
                    db.execute('''UPDATE OR IGNORE session_entries SET team_id=?
                        WHERE team_id=? AND session_id=?''',
                        (canonical_id, duplicate, session_id))
                for table in ('race_entries', 'race_results'):
                    db.execute(f'''UPDATE OR IGNORE {table} SET team_id=?
                        WHERE team_id=? AND race_id=?''',
                        (canonical_id, duplicate, race_id))
                db.execute('''UPDATE driver_team_assignments SET team_id=?
                    WHERE team_id=? AND season_id=? AND race_from=? AND race_to=?''',
                    (canonical_id, duplicate, season_id, round_number, round_number))
            db.execute(f"UPDATE {entity_table} SET status='merged',updated_at=? WHERE {id_column}=?",
                       (now, duplicate))
            db.execute('''INSERT INTO audit_log VALUES (?,?,?,?,?,?,?,?)''', (
                new_id('aud'), entity, duplicate, 'merged', duplicate,
                canonical_id, 'verified_provider_identity', now,
            ))

    def _persist(self, season: int, round_number: int, kind: str, feed: ResultsFeed) -> ResultsFeed:
        now = datetime.now(timezone.utc).isoformat()
        hydrated = []
        with closing(connect(self.path)) as db, db:
            context = db.execute('''SELECT r.race_id, r.season_id FROM races r
                JOIN seasons s ON s.season_id=r.season_id WHERE s.year=? AND r.round=?''',
                (season, round_number)).fetchone()
            if not context:
                return feed
            race_id, season_id = context
            session = db.execute('''SELECT session_id FROM sessions WHERE race_id=?
                AND session_type=? ORDER BY scheduled_start DESC LIMIT 1''',
                (race_id, 'qualifying' if kind == 'qualifying' else 'race')).fetchone()
            session_id = session[0] if session else None
            if feed.raw_rows is not None:
                store_raw(db, f'{kind}:{season}-{round_number}', feed.raw_rows)
            for entry in feed.entries:
                driver_id = self._identity(
                    db, 'driver', entry.driver_external_id, entry.driver,
                    entry, race_id, now,
                )
                team_id = self._identity(
                    db, 'team', entry.team_external_id, entry.team,
                    entry, race_id, now,
                )
                db.execute('''INSERT INTO drivers
                    (driver_id,full_name,given_name,family_name,nationality,date_of_birth,
                     permanent_number,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(driver_id) DO UPDATE SET full_name=excluded.full_name,
                    given_name=COALESCE(excluded.given_name,drivers.given_name),
                    family_name=COALESCE(excluded.family_name,drivers.family_name),
                    nationality=COALESCE(excluded.nationality,drivers.nationality),
                    date_of_birth=COALESCE(excluded.date_of_birth,drivers.date_of_birth),
                    permanent_number=COALESCE(excluded.permanent_number,drivers.permanent_number),
                    updated_at=excluded.updated_at''',
                    (driver_id, entry.driver, entry.given_name, entry.family_name,
                     entry.nationality, entry.date_of_birth, entry.permanent_number,
                     'active', now, now))
                db.execute('''INSERT INTO teams
                    (team_id,canonical_name,status,created_at,updated_at) VALUES (?,?,?,?,?)
                    ON CONFLICT(team_id) DO UPDATE SET canonical_name=excluded.canonical_name,
                    updated_at=excluded.updated_at''',
                    (team_id, entry.team, 'active', now, now))
                if entry.driver_external_id:
                    db.execute('''INSERT INTO driver_external_identities
                        (provider_id,external_id,driver_id,external_name,first_seen_at,last_seen_at,
                         last_verified_at,confidence,status) VALUES (?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(provider_id,external_id) DO UPDATE SET
                        last_seen_at=excluded.last_seen_at,last_verified_at=excluded.last_verified_at''',
                        (PROVIDER_ID, entry.driver_external_id, driver_id, entry.driver,
                         now, now, now, 'high', 'active'))
                if entry.team_external_id:
                    db.execute('''INSERT INTO team_external_identities
                        (provider_id,external_id,team_id,external_name,first_seen_at,last_seen_at,
                         last_verified_at,confidence,status) VALUES (?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(provider_id,external_id) DO UPDATE SET
                        last_seen_at=excluded.last_seen_at,last_verified_at=excluded.last_verified_at''',
                        (PROVIDER_ID, entry.team_external_id, team_id, entry.team,
                         now, now, now, 'high', 'active'))
                if entry.driver_external_id:
                    self._merge_unverified(
                        db, 'driver', driver_id, entry.driver,
                        race_id, season_id, round_number, now,
                    )
                if entry.team_external_id:
                    self._merge_unverified(
                        db, 'team', team_id, entry.team,
                        race_id, season_id, round_number, now,
                    )
                team_season = db.execute('''SELECT team_season_id FROM team_seasons
                    WHERE team_id=? AND season_id=?''', (team_id, season_id)).fetchone()
                team_season_id = team_season[0] if team_season else new_id('tse')
                db.execute('''INSERT INTO team_seasons
                    (team_season_id,team_id,season_id,display_name,status) VALUES (?,?,?,?,?)
                    ON CONFLICT(team_id,season_id) DO UPDATE SET display_name=excluded.display_name''',
                    (team_season_id, team_id, season_id, entry.team, 'active'))
                assignment = db.execute('''SELECT assignment_id FROM driver_team_assignments
                    WHERE driver_id=? AND team_id=? AND season_id=? AND race_from=? AND race_to=?''',
                    (driver_id, team_id, season_id, round_number, round_number)).fetchone()
                if not assignment:
                    db.execute('''INSERT INTO driver_team_assignments
                        (assignment_id,driver_id,team_id,season_id,car_number,role,
                         race_from,race_to,status) VALUES (?,?,?,?,?,?,?,?,?)''',
                        (new_id('asg'), driver_id, team_id, season_id,
                         entry.permanent_number, None, round_number, round_number, 'observed'))
                db.execute('''INSERT INTO race_entries
                    (race_entry_id,race_id,driver_id,team_id,car_number,entry_status)
                    VALUES (?,?,?,?,?,?) ON CONFLICT(race_id,driver_id) DO UPDATE SET
                    team_id=excluded.team_id,car_number=excluded.car_number''',
                    (new_id('ren'), race_id, driver_id, team_id,
                     entry.permanent_number, 'confirmed'))
                if session_id:
                    db.execute('''INSERT INTO session_entries
                        (session_entry_id,session_id,driver_id,team_id,car_number,entry_status)
                        VALUES (?,?,?,?,?,?) ON CONFLICT(session_id,driver_id) DO UPDATE SET
                        team_id=excluded.team_id,car_number=excluded.car_number''',
                        (new_id('sen'), session_id, driver_id, team_id,
                         entry.permanent_number, 'confirmed'))

                if kind == 'qualifying' and session_id:
                    old = db.execute('''SELECT position,q1,q2,q3,status FROM qualifying_results
                        WHERE session_id=? AND driver_id=?''', (session_id, driver_id)).fetchone()
                    current = (entry.position, entry.q1, entry.q2, entry.q3, entry.status)
                    if old and tuple(old) != current:
                        db.execute('''INSERT INTO audit_log VALUES (?,?,?,?,?,?,?,?)''', (
                            new_id('aud'), 'qualifying_result', f'{session_id}:{driver_id}',
                            'revised', json.dumps(tuple(old)), json.dumps(current),
                            PROVIDER_ID, now,
                        ))
                    result_id = (db.execute('''SELECT qualifying_result_id FROM qualifying_results
                        WHERE session_id=? AND driver_id=?''', (session_id, driver_id)).fetchone()
                        or (new_id('qre'),))[0]
                    db.execute('''INSERT INTO qualifying_results VALUES (?,?,?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(session_id,driver_id) DO UPDATE SET position=excluded.position,
                        q1=excluded.q1,q2=excluded.q2,q3=excluded.q3,status=excluded.status,
                        result_status=excluded.result_status,updated_at=excluded.updated_at''',
                        (result_id, session_id, driver_id, entry.position, entry.q1,
                         entry.q2, entry.q3, entry.status, entry.result_status,
                         PROVIDER_ID, now))
                elif kind == 'results':
                    old = db.execute('''SELECT finish_position,points FROM race_results
                        WHERE race_id=? AND driver_id=?''', (race_id, driver_id)).fetchone()
                    if old and (old[0], old[1]) != (entry.position, entry.points):
                        db.execute('''INSERT OR IGNORE INTO result_revisions VALUES
                            (?,?,?,?,?,?,?,?,?,?)''', (
                            new_id('rrv'), race_id, driver_id, old[0], entry.position,
                            old[1], entry.points, 'provider_result_update', str(feed.source), now,
                        ))
                    result_id = (db.execute('''SELECT race_result_id FROM race_results
                        WHERE race_id=? AND driver_id=?''', (race_id, driver_id)).fetchone()
                        or (new_id('rre'),))[0]
                    db.execute('''INSERT INTO race_results VALUES
                        (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(race_id,driver_id) DO UPDATE SET team_id=excluded.team_id,
                        grid_position=excluded.grid_position,finish_position=excluded.finish_position,
                        classification=excluded.classification,laps_completed=excluded.laps_completed,
                        time=excluded.time,fastest_lap=excluded.fastest_lap,
                        fastest_lap_time=excluded.fastest_lap_time,points=excluded.points,
                        classification_status=excluded.classification_status,
                        result_status=excluded.result_status,updated_at=excluded.updated_at''',
                        (result_id, race_id, driver_id, team_id, entry.grid, entry.position,
                         entry.classification, entry.laps_completed, entry.time, None,
                         entry.fastest_lap_number, entry.fastest_lap_time, entry.points,
                         entry.status, entry.result_status, PROVIDER_ID, now))
                    qualifying_position = db.execute('''SELECT qr.position FROM qualifying_results qr
                        JOIN sessions s ON s.session_id=qr.session_id
                        WHERE s.race_id=? AND qr.driver_id=? ORDER BY s.scheduled_start DESC LIMIT 1''',
                        (race_id, driver_id)).fetchone()
                    grid_id = (db.execute('''SELECT starting_grid_id FROM starting_grids
                        WHERE race_id=? AND driver_id=?''', (race_id, driver_id)).fetchone()
                        or (new_id('grd'),))[0]
                    db.execute('''INSERT INTO starting_grids VALUES (?,?,?,?,?,?,?,?,?)
                        ON CONFLICT(race_id,driver_id) DO UPDATE SET
                        qualifying_position=excluded.qualifying_position,
                        grid_position=excluded.grid_position,updated_at=excluded.updated_at''',
                        (grid_id, race_id, driver_id,
                         qualifying_position[0] if qualifying_position else None,
                         entry.grid, None, None, PROVIDER_ID, now))
                else:
                    continue
                hydrated.append(entry.model_copy(update={
                    'internal_id': result_id, 'driver_id': driver_id, 'team_id': team_id,
                }))
            for entity in ('driver', 'team'):
                table = 'drivers' if entity == 'driver' else 'teams'
                id_column = f'{entity}_id'
                identity_table = f'{entity}_external_identities'
                db.execute(f'''UPDATE {table} SET status='inactive',updated_at=?
                    WHERE status='active'
                    AND NOT EXISTS (SELECT 1 FROM {identity_table} i
                                    WHERE i.{id_column}={table}.{id_column})
                    AND NOT EXISTS (SELECT 1 FROM race_entries e
                                    WHERE e.{id_column}={table}.{id_column})''', (now,))
        return feed.model_copy(update={'entries': hydrated})

    def summaries(self, season: int) -> SeasonSummaryFeed:
        with closing(connect(self.path)) as db:
            row = db.execute(
                'SELECT payload FROM season_summary_cache WHERE season=?', (season,),
            ).fetchone()
        cached = SeasonSummaryFeed.model_validate_json(row[0]) if row else None
        now = datetime.now(timezone.utc)
        ttl = 900 if season >= now.year else 30 * 86400
        if cached and (now - cached.updated_at).total_seconds() < ttl:
            return cached
        try:
            feed = fetch_season_summaries(season)
        except Exception as exc:
            record_provider_health(
                self.path, False,
                schema_changed=isinstance(exc, (KeyError, TypeError, ValueError)),
            )
            return (cached or SeasonSummaryFeed(
                summaries={}, updated_at=now,
            )).model_copy(update={'stale': True})
        record_provider_health(self.path, True)
        with closing(connect(self.path)) as db, db:
            store_raw(db, f'season-winners:{season}', feed.winner_races or [])
            store_raw(db, f'season-fastest:{season}', feed.fastest_races or [])
        by_round = {}
        for race in (feed.winner_races or []) + (feed.fastest_races or []):
            rows = by_round.setdefault(int(race['round']), {})
            for result in race.get('Results') or []:
                driver = result.get('Driver') or {}
                rows[driver.get('driverId') or str(result)] = result
        for round_number, rows in by_round.items():
            self._persist(
                season, round_number, 'results',
                normalize_results(
                    list(rows.values()), f'{BASE_URL}/{season}/{round_number}/results/', 'results',
                ),
            )
        with closing(connect(self.path)) as db, db:
            db.execute('INSERT OR REPLACE INTO season_summary_cache VALUES (?,?)',
                       (season, feed.model_dump_json()))
        return feed

    def roster(self, season: int) -> SeasonRosterFeed:
        with closing(connect(self.path)) as db:
            row = db.execute(
                'SELECT payload FROM season_roster_cache WHERE season=?', (season,),
            ).fetchone()
        cached = SeasonRosterFeed.model_validate_json(row[0]) if row else None
        now = datetime.now(timezone.utc)
        ttl = 900 if season >= now.year else 30 * 86400
        if cached and (now - cached.updated_at).total_seconds() < ttl:
            return cached
        try:
            feed = normalize_roster(fetch_driver_standings(season), season)
        except Exception as exc:
            record_provider_health(
                self.path, False,
                schema_changed=isinstance(exc, (KeyError, TypeError, ValueError)),
            )
            if cached:
                return cached.model_copy(update={'stale': True})
            raise
        record_provider_health(self.path, True)
        hydrated = self._persist_roster(season, feed)
        with closing(connect(self.path)) as db, db:
            db.execute('INSERT OR REPLACE INTO season_roster_cache VALUES (?,?)',
                       (season, hydrated.model_dump_json()))
        return hydrated

    def strategy(self, season: int, round_number: int) -> StrategyFeed:
        key = f'{season}-{round_number}'
        with closing(connect(self.path)) as db:
            row = db.execute('SELECT payload FROM strategy_cache WHERE key=?', (key,)).fetchone()
        cached = StrategyFeed.model_validate_json(row[0]) if row else None
        now = datetime.now(timezone.utc)
        ttl = 300 if not cached or not cached.drivers else (86400 if season < now.year else 900)
        if cached and (now - cached.updated_at).total_seconds() < ttl:
            return cached
        try:
            feed = normalize_strategy(fetch_strategy_rows(season, round_number))
        except Exception:
            if cached:
                return cached.model_copy(update={'stale': True})
            raise
        with closing(connect(self.path)) as db, db:
            db.execute('INSERT OR REPLACE INTO strategy_cache VALUES (?,?)',
                       (key, feed.model_dump_json()))
        return feed

    def _persist_roster(self, season: int, feed: SeasonRosterFeed) -> SeasonRosterFeed:
        """Persist provider identities so roster and results share stable local IDs."""
        now = datetime.now(timezone.utc).isoformat()
        entries = []
        with closing(connect(self.path)) as db, db:
            season_row = db.execute('SELECT season_id FROM seasons WHERE year=?', (season,)).fetchone()
            if not season_row:
                return feed
            season_id = season_row[0]
            if feed.raw_rows is not None:
                store_raw(db, f'season-roster:{season}', feed.raw_rows)
            for row in feed.raw_rows or []:
                driver = row.get('Driver') or {}
                teams = row.get('Constructors') or []
                team = teams[0] if teams else {}
                driver_external_id = driver.get('driverId')
                team_external_id = team.get('constructorId')
                given_name, family_name = driver.get('givenName'), driver.get('familyName')
                driver_name = ' '.join(part for part in (given_name, family_name) if part)
                team_name = team.get('name')
                if not (driver_external_id and team_external_id and driver_name and team_name):
                    continue
                driver_row = db.execute('''SELECT driver_id FROM driver_external_identities
                    WHERE provider_id=? AND external_id=?''',
                    (PROVIDER_ID, driver_external_id)).fetchone()
                driver_id = driver_row[0] if driver_row else new_id('drv')
                team_row = db.execute('''SELECT team_id FROM team_external_identities
                    WHERE provider_id=? AND external_id=?''',
                    (PROVIDER_ID, team_external_id)).fetchone()
                team_id = team_row[0] if team_row else new_id('tea')
                db.execute('''INSERT INTO drivers
                    (driver_id,full_name,given_name,family_name,nationality,date_of_birth,
                     permanent_number,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(driver_id) DO UPDATE SET full_name=excluded.full_name,
                    given_name=COALESCE(excluded.given_name,drivers.given_name),
                    family_name=COALESCE(excluded.family_name,drivers.family_name),
                    nationality=COALESCE(excluded.nationality,drivers.nationality),
                    date_of_birth=COALESCE(excluded.date_of_birth,drivers.date_of_birth),
                    permanent_number=COALESCE(excluded.permanent_number,drivers.permanent_number),
                    status='active',updated_at=excluded.updated_at''',
                    (driver_id, driver_name, given_name, family_name, driver.get('nationality'),
                     driver.get('dateOfBirth'), driver.get('permanentNumber'), 'active', now, now))
                db.execute('''INSERT INTO teams (team_id,canonical_name,status,created_at,updated_at)
                    VALUES (?,?,?,?,?) ON CONFLICT(team_id) DO UPDATE SET
                    canonical_name=excluded.canonical_name,status='active',updated_at=excluded.updated_at''',
                    (team_id, team_name, 'active', now, now))
                db.execute('''INSERT INTO driver_external_identities
                    (provider_id,external_id,driver_id,external_name,first_seen_at,last_seen_at,
                     last_verified_at,confidence,status) VALUES (?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(provider_id,external_id) DO UPDATE SET driver_id=excluded.driver_id,
                    external_name=excluded.external_name,last_seen_at=excluded.last_seen_at,
                    last_verified_at=excluded.last_verified_at,status='active' ''',
                    (PROVIDER_ID, driver_external_id, driver_id, driver_name, now, now, now, 'high', 'active'))
                db.execute('''INSERT INTO team_external_identities
                    (provider_id,external_id,team_id,external_name,first_seen_at,last_seen_at,
                     last_verified_at,confidence,status) VALUES (?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(provider_id,external_id) DO UPDATE SET team_id=excluded.team_id,
                    external_name=excluded.external_name,last_seen_at=excluded.last_seen_at,
                    last_verified_at=excluded.last_verified_at,status='active' ''',
                    (PROVIDER_ID, team_external_id, team_id, team_name, now, now, now, 'high', 'active'))
                team_season = db.execute('''SELECT team_season_id FROM team_seasons
                    WHERE team_id=? AND season_id=?''', (team_id, season_id)).fetchone()
                db.execute('''INSERT INTO team_seasons
                    (team_season_id,team_id,season_id,display_name,status) VALUES (?,?,?,?,?)
                    ON CONFLICT(team_id,season_id) DO UPDATE SET display_name=excluded.display_name,
                    status='active' ''',
                    ((team_season[0] if team_season else new_id('tse')), team_id, season_id, team_name, 'active'))
                assignment = db.execute('''SELECT assignment_id FROM driver_team_assignments
                    WHERE driver_id=? AND team_id=? AND season_id=?
                    AND race_from IS NULL AND race_to IS NULL''',
                    (driver_id, team_id, season_id)).fetchone()
                if not assignment:
                    db.execute('''INSERT INTO driver_team_assignments
                        (assignment_id,driver_id,team_id,season_id,car_number,role,
                         race_from,race_to,status) VALUES (?,?,?,?,?,?,?,?,?)''',
                        (new_id('asg'), driver_id, team_id, season_id,
                         driver.get('permanentNumber'), None, None, None, 'confirmed'))
                entries.append(SeasonRosterEntry(
                    driver_id=driver_id, driver=driver_name, team_id=team_id, team=team_name,
                ))
        return feed.model_copy(update={'entries': entries})

    def load(self, season: int, round_number: int, kind: str) -> ResultsFeed:
        if kind not in ('results', 'qualifying'):
            raise ValueError('Unsupported session')
        key = f'{season}-{round_number}-{kind}'
        with closing(connect(self.path)) as db:
            row = db.execute('SELECT payload FROM result_cache WHERE key=?', (key,)).fetchone()
        cached = ResultsFeed.model_validate_json(row[0]) if row else None
        now = datetime.now(timezone.utc)
        # Empty results must be retried soon, including missing historical data.
        ttl = 300 if not cached or not cached.entries else (86400 if season < now.year else 900)
        if cached and (now - cached.updated_at).total_seconds() < ttl:
            return self._persist(season, round_number, kind, cached)
        try:
            feed = fetch_results(season, round_number, kind)
        except Exception as exc:
            record_provider_health(
                self.path, False,
                schema_changed=isinstance(exc, (KeyError, TypeError, ValueError)),
            )
            if cached:
                return self._persist(
                    season, round_number, kind, cached,
                ).model_copy(update={'stale': True})
            raise
        record_provider_health(self.path, True)
        feed = self._persist(season, round_number, kind, feed)
        with closing(connect(self.path)) as db, db:
            db.execute('INSERT OR REPLACE INTO result_cache VALUES (?,?)', (key, feed.model_dump_json()))
        return feed
