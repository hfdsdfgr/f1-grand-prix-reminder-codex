"""SQLite schema and small shared helpers for the versioned data model."""
import hashlib
import json
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4


PROVIDER_ID = 'prv_jolpica'


def new_id(prefix: str) -> str:
    return f'{prefix}_{uuid4().hex}'


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def connect(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path)
    db.execute('PRAGMA foreign_keys = ON')
    return db


SCHEMA = r'''
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS schedules (
    season INTEGER PRIMARY KEY, payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS result_cache (
    key TEXT PRIMARY KEY, payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS season_summary_cache (
    season INTEGER PRIMARY KEY, payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS season_roster_cache (
    season INTEGER PRIMARY KEY, payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS strategy_cache (
    key TEXT PRIMARY KEY, payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS championship_impact_cache (
    key TEXT PRIMARY KEY, payload TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS providers (
    provider_id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, type TEXT NOT NULL,
    base_url TEXT NOT NULL, priority INTEGER NOT NULL, status TEXT NOT NULL,
    created_at TEXT, updated_at TEXT
);
CREATE TABLE IF NOT EXISTS provider_health (
    provider_id TEXT PRIMARY KEY REFERENCES providers(provider_id),
    last_success TEXT, last_failure TEXT, consecutive_failures INTEGER NOT NULL DEFAULT 0,
    parser_version TEXT NOT NULL, schema_version TEXT NOT NULL, status TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS raw_source_records (
    raw_record_id TEXT PRIMARY KEY, provider_id TEXT NOT NULL REFERENCES providers(provider_id),
    external_id TEXT NOT NULL, retrieved_at TEXT NOT NULL, content_hash TEXT NOT NULL,
    raw_payload TEXT NOT NULL, parser_version TEXT NOT NULL,
    UNIQUE(provider_id, external_id, content_hash)
);
CREATE TABLE IF NOT EXISTS seasons (
    season_id TEXT PRIMARY KEY, year INTEGER NOT NULL UNIQUE, start_date TEXT, end_date TEXT,
    status TEXT NOT NULL, regulation_set_id TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS regulation_sets (
    regulation_set_id TEXT PRIMARY KEY, season_id TEXT NOT NULL REFERENCES seasons(season_id),
    sporting_version TEXT, technical_version TEXT, effective_from TEXT, effective_to TEXT,
    source TEXT, status TEXT NOT NULL DEFAULT 'unknown'
);
CREATE TABLE IF NOT EXISTS scoring_rules (
    scoring_rule_id TEXT PRIMARY KEY,
    regulation_set_id TEXT NOT NULL REFERENCES regulation_sets(regulation_set_id),
    event_type TEXT NOT NULL, position INTEGER NOT NULL, points REAL NOT NULL,
    valid_from TEXT, valid_to TEXT, UNIQUE(regulation_set_id, event_type, position)
);
CREATE TABLE IF NOT EXISTS drivers (
    driver_id TEXT PRIMARY KEY, full_name TEXT NOT NULL, given_name TEXT, family_name TEXT,
    nationality TEXT, date_of_birth TEXT, permanent_number TEXT,
    status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS driver_external_identities (
    provider_id TEXT NOT NULL REFERENCES providers(provider_id), external_id TEXT NOT NULL,
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), external_name TEXT,
    first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, last_verified_at TEXT,
    confidence TEXT NOT NULL, status TEXT NOT NULL,
    PRIMARY KEY(provider_id, external_id)
);
CREATE TABLE IF NOT EXISTS teams (
    team_id TEXT PRIMARY KEY, canonical_name TEXT NOT NULL, country TEXT,
    status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS team_external_identities (
    provider_id TEXT NOT NULL REFERENCES providers(provider_id), external_id TEXT NOT NULL,
    team_id TEXT NOT NULL REFERENCES teams(team_id), external_name TEXT,
    first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, last_verified_at TEXT,
    confidence TEXT NOT NULL, status TEXT NOT NULL,
    PRIMARY KEY(provider_id, external_id)
);
CREATE TABLE IF NOT EXISTS power_unit_manufacturers (
    pu_manufacturer_id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, country TEXT,
    status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS team_seasons (
    team_season_id TEXT PRIMARY KEY, team_id TEXT NOT NULL REFERENCES teams(team_id),
    season_id TEXT NOT NULL REFERENCES seasons(season_id), display_name TEXT NOT NULL,
    constructor_name TEXT, car_name TEXT, team_color TEXT, valid_from TEXT, valid_to TEXT,
    status TEXT NOT NULL DEFAULT 'active', UNIQUE(team_id, season_id)
);
CREATE TABLE IF NOT EXISTS power_unit_assignments (
    power_unit_assignment_id TEXT PRIMARY KEY,
    team_season_id TEXT NOT NULL REFERENCES team_seasons(team_season_id),
    pu_manufacturer_id TEXT NOT NULL REFERENCES power_unit_manufacturers(pu_manufacturer_id),
    valid_from TEXT, valid_to TEXT, status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS driver_team_assignments (
    assignment_id TEXT PRIMARY KEY, driver_id TEXT NOT NULL REFERENCES drivers(driver_id),
    team_id TEXT NOT NULL REFERENCES teams(team_id), season_id TEXT NOT NULL REFERENCES seasons(season_id),
    car_number TEXT, role TEXT, valid_from TEXT, valid_to TEXT,
    race_from INTEGER, race_to INTEGER, status TEXT NOT NULL DEFAULT 'active',
    CHECK(race_from IS NULL OR race_to IS NULL OR race_from <= race_to)
);
CREATE TABLE IF NOT EXISTS circuits (
    circuit_id TEXT PRIMARY KEY, canonical_name TEXT NOT NULL, country TEXT, city TEXT,
    latitude REAL, longitude REAL, track_length REAL,
    status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS circuit_external_identities (
    provider_id TEXT NOT NULL REFERENCES providers(provider_id), external_id TEXT NOT NULL,
    circuit_id TEXT NOT NULL REFERENCES circuits(circuit_id), external_name TEXT,
    first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, last_verified_at TEXT,
    confidence TEXT NOT NULL, status TEXT NOT NULL,
    PRIMARY KEY(provider_id, external_id)
);
CREATE TABLE IF NOT EXISTS circuit_layouts (
    layout_id TEXT PRIMARY KEY, circuit_id TEXT NOT NULL REFERENCES circuits(circuit_id),
    valid_from INTEGER, valid_to INTEGER, asset_path TEXT NOT NULL,
    view_box TEXT NOT NULL DEFAULT '0 0 500 500', turns INTEGER,
    source_url TEXT NOT NULL, source_license TEXT NOT NULL, verified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS circuit_annotations (
    annotation_id TEXT PRIMARY KEY,
    layout_id TEXT NOT NULL REFERENCES circuit_layouts(layout_id),
    turn_number INTEGER, display_name TEXT NOT NULL,
    label_x REAL NOT NULL, label_y REAL NOT NULL, is_notable INTEGER NOT NULL DEFAULT 0,
    source_url TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS races (
    race_id TEXT PRIMARY KEY, season_id TEXT NOT NULL REFERENCES seasons(season_id),
    circuit_id TEXT NOT NULL REFERENCES circuits(circuit_id), round INTEGER NOT NULL,
    display_name TEXT NOT NULL, official_name TEXT, scheduled_start TEXT, scheduled_end TEXT,
    status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(season_id, round)
);
CREATE TABLE IF NOT EXISTS race_external_identities (
    provider_id TEXT NOT NULL REFERENCES providers(provider_id), external_id TEXT NOT NULL,
    race_id TEXT NOT NULL REFERENCES races(race_id), external_name TEXT,
    first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, last_verified_at TEXT,
    confidence TEXT NOT NULL, status TEXT NOT NULL,
    PRIMARY KEY(provider_id, external_id)
);
CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY, race_id TEXT NOT NULL REFERENCES races(race_id),
    session_type TEXT NOT NULL, display_name TEXT NOT NULL,
    scheduled_start TEXT, scheduled_end TEXT, actual_start TEXT, actual_end TEXT,
    status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(race_id, display_name)
);
CREATE TABLE IF NOT EXISTS schedule_revisions (
    revision_id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(session_id),
    previous_start TEXT, new_start TEXT, reason TEXT,
    source_provider_id TEXT NOT NULL REFERENCES providers(provider_id), created_at TEXT NOT NULL,
    UNIQUE(session_id, previous_start, new_start)
);
CREATE TABLE IF NOT EXISTS race_entries (
    race_entry_id TEXT PRIMARY KEY, race_id TEXT NOT NULL REFERENCES races(race_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), team_id TEXT NOT NULL REFERENCES teams(team_id),
    car_number TEXT, entry_status TEXT NOT NULL DEFAULT 'confirmed',
    UNIQUE(race_id, driver_id)
);
CREATE TABLE IF NOT EXISTS session_entries (
    session_entry_id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(session_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), team_id TEXT NOT NULL REFERENCES teams(team_id),
    car_number TEXT, entry_status TEXT NOT NULL DEFAULT 'confirmed',
    UNIQUE(session_id, driver_id)
);
CREATE TABLE IF NOT EXISTS qualifying_results (
    qualifying_result_id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(session_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), position INTEGER,
    q1 TEXT, q2 TEXT, q3 TEXT, status TEXT, result_status TEXT NOT NULL,
    source_provider_id TEXT NOT NULL REFERENCES providers(provider_id), updated_at TEXT NOT NULL,
    UNIQUE(session_id, driver_id)
);
CREATE TABLE IF NOT EXISTS starting_grids (
    starting_grid_id TEXT PRIMARY KEY, race_id TEXT NOT NULL REFERENCES races(race_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), qualifying_position INTEGER,
    grid_position INTEGER, penalty_applied INTEGER, reason TEXT,
    source_provider_id TEXT NOT NULL REFERENCES providers(provider_id), updated_at TEXT NOT NULL,
    UNIQUE(race_id, driver_id)
);
CREATE TABLE IF NOT EXISTS race_results (
    race_result_id TEXT PRIMARY KEY, race_id TEXT NOT NULL REFERENCES races(race_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), team_id TEXT NOT NULL REFERENCES teams(team_id),
    grid_position INTEGER, finish_position INTEGER, classification TEXT,
    laps_completed INTEGER, time TEXT, gap TEXT, fastest_lap INTEGER,
    fastest_lap_time TEXT, points REAL, classification_status TEXT,
    result_status TEXT NOT NULL, source_provider_id TEXT NOT NULL REFERENCES providers(provider_id),
    updated_at TEXT NOT NULL, UNIQUE(race_id, driver_id)
);
CREATE TABLE IF NOT EXISTS result_revisions (
    revision_id TEXT PRIMARY KEY, race_id TEXT NOT NULL REFERENCES races(race_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), previous_position INTEGER,
    new_position INTEGER, previous_points REAL, new_points REAL, reason TEXT,
    decision_source TEXT, effective_at TEXT NOT NULL,
    UNIQUE(race_id, driver_id, previous_position, new_position, previous_points, new_points)
);
CREATE TABLE IF NOT EXISTS penalties (
    penalty_id TEXT PRIMARY KEY, race_id TEXT REFERENCES races(race_id),
    session_id TEXT REFERENCES sessions(session_id), driver_id TEXT REFERENCES drivers(driver_id),
    team_id TEXT REFERENCES teams(team_id), penalty_type TEXT NOT NULL,
    description TEXT, effect TEXT, issued_at TEXT, source TEXT,
    status TEXT NOT NULL DEFAULT 'unknown'
);
CREATE TABLE IF NOT EXISTS laps (
    lap_id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(session_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), lap_number INTEGER NOT NULL,
    lap_time TEXT, sector_1 TEXT, sector_2 TEXT, sector_3 TEXT, position INTEGER,
    source_provider_id TEXT REFERENCES providers(provider_id),
    UNIQUE(session_id, driver_id, lap_number)
);
CREATE TABLE IF NOT EXISTS tyre_stints (
    stint_id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(session_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), compound TEXT,
    start_lap INTEGER, end_lap INTEGER, tyre_age_at_start INTEGER,
    source_provider_id TEXT REFERENCES providers(provider_id)
);
CREATE TABLE IF NOT EXISTS pit_stops (
    pit_stop_id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(session_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), lap INTEGER,
    duration TEXT, timestamp TEXT, source_provider_id TEXT REFERENCES providers(provider_id)
);
CREATE TABLE IF NOT EXISTS technical_eras (
    technical_era_id TEXT PRIMARY KEY, name TEXT NOT NULL, valid_from TEXT,
    valid_to TEXT, regulation_reference TEXT, status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS car_component_types (
    component_type_id TEXT PRIMARY KEY,
    technical_era_id TEXT NOT NULL REFERENCES technical_eras(technical_era_id),
    canonical_name TEXT NOT NULL, category TEXT,
    parent_component_id TEXT REFERENCES car_component_types(component_type_id), description TEXT,
    status TEXT NOT NULL DEFAULT 'active', UNIQUE(technical_era_id, canonical_name)
);
CREATE TABLE IF NOT EXISTS car_models (
    car_model_id TEXT PRIMARY KEY, team_season_id TEXT NOT NULL REFERENCES team_seasons(team_season_id),
    name TEXT NOT NULL, season_id TEXT NOT NULL REFERENCES seasons(season_id),
    base_3d_model_id TEXT, status TEXT NOT NULL DEFAULT 'active'
);
CREATE TABLE IF NOT EXISTS component_3d_mappings (
    component_mapping_id TEXT PRIMARY KEY,
    component_type_id TEXT NOT NULL REFERENCES car_component_types(component_type_id),
    model_id TEXT NOT NULL, mesh_name TEXT NOT NULL, anchor_x REAL, anchor_y REAL,
    anchor_z REAL, camera_target TEXT, status TEXT NOT NULL DEFAULT 'active',
    UNIQUE(component_type_id, model_id, mesh_name)
);
CREATE TABLE IF NOT EXISTS car_specifications (
    specification_id TEXT PRIMARY KEY, car_model_id TEXT NOT NULL REFERENCES car_models(car_model_id),
    race_id TEXT REFERENCES races(race_id), session_id TEXT REFERENCES sessions(session_id),
    driver_id TEXT REFERENCES drivers(driver_id), valid_from TEXT, valid_to TEXT,
    status TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS upgrades (
    upgrade_id TEXT PRIMARY KEY, team_season_id TEXT NOT NULL REFERENCES team_seasons(team_season_id),
    car_model_id TEXT REFERENCES car_models(car_model_id),
    introduced_race_id TEXT REFERENCES races(race_id),
    component_type_id TEXT NOT NULL REFERENCES car_component_types(component_type_id),
    title TEXT NOT NULL, change_description TEXT, technical_goal TEXT, expected_effect TEXT,
    status TEXT NOT NULL, confidence TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS specification_upgrades (
    specification_id TEXT NOT NULL REFERENCES car_specifications(specification_id),
    upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id),
    status TEXT NOT NULL DEFAULT 'installed', PRIMARY KEY(specification_id, upgrade_id)
);
CREATE TABLE IF NOT EXISTS upgrade_lifecycle_events (
    event_id TEXT PRIMARY KEY, upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id),
    race_id TEXT REFERENCES races(race_id), session_id TEXT REFERENCES sessions(session_id),
    event_type TEXT NOT NULL, timestamp TEXT, source TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS upgrade_relations (
    upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id),
    related_upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id), relation_type TEXT NOT NULL,
    PRIMARY KEY(upgrade_id, related_upgrade_id, relation_type), CHECK(upgrade_id <> related_upgrade_id)
);
CREATE TABLE IF NOT EXISTS interviews (
    interview_id TEXT PRIMARY KEY, race_id TEXT REFERENCES races(race_id),
    session_id TEXT REFERENCES sessions(session_id), driver_id TEXT REFERENCES drivers(driver_id),
    team_id_at_time TEXT REFERENCES teams(team_id), source_provider TEXT,
    source_url TEXT, published_at TEXT, retrieved_at TEXT NOT NULL,
    original_text TEXT, status TEXT NOT NULL, content_hash TEXT
);
CREATE TABLE IF NOT EXISTS interview_sources (
    interview_source_id TEXT PRIMARY KEY, interview_id TEXT NOT NULL REFERENCES interviews(interview_id),
    provider TEXT NOT NULL, url TEXT NOT NULL, published_at TEXT, source_type TEXT,
    UNIQUE(interview_id, url)
);
CREATE TABLE IF NOT EXISTS source_snapshots (
    snapshot_id TEXT PRIMARY KEY, created_at TEXT NOT NULL,
    content_hash TEXT NOT NULL UNIQUE, source_count INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS source_snapshot_items (
    snapshot_id TEXT NOT NULL REFERENCES source_snapshots(snapshot_id),
    entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, content_hash TEXT NOT NULL,
    PRIMARY KEY(snapshot_id, entity_type, entity_id)
);
CREATE TABLE IF NOT EXISTS ai_generations (
    generation_id TEXT PRIMARY KEY, provider TEXT NOT NULL, model TEXT NOT NULL,
    prompt_version TEXT NOT NULL, pipeline_version TEXT NOT NULL, generated_at TEXT,
    source_snapshot_id TEXT NOT NULL REFERENCES source_snapshots(snapshot_id), status TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS driver_briefs (
    driver_brief_id TEXT PRIMARY KEY, race_id TEXT NOT NULL REFERENCES races(race_id),
    driver_id TEXT NOT NULL REFERENCES drivers(driver_id), team_id_at_race TEXT REFERENCES teams(team_id),
    race_assessment TEXT, car_strengths TEXT, car_weaknesses TEXT, strategy TEXT,
    tyres TEXT, technical_issues TEXT, upgrade_feedback TEXT, future_expectations TEXT,
    status TEXT NOT NULL, generation_id TEXT NOT NULL REFERENCES ai_generations(generation_id),
    UNIQUE(race_id, driver_id, generation_id)
);
CREATE TABLE IF NOT EXISTS race_briefs (
    race_brief_id TEXT PRIMARY KEY, race_id TEXT NOT NULL REFERENCES races(race_id),
    technical_themes TEXT, team_performance TEXT, tyre_issues TEXT, strategy_issues TEXT,
    upgrade_feedback TEXT, driver_concerns TEXT, next_race_expectations TEXT,
    status TEXT NOT NULL, generation_id TEXT NOT NULL REFERENCES ai_generations(generation_id),
    UNIQUE(race_id, generation_id)
);
CREATE TABLE IF NOT EXISTS review_items (
    review_id TEXT PRIMARY KEY, entity_type TEXT NOT NULL, entity_id TEXT,
    issue_type TEXT NOT NULL, description TEXT NOT NULL, confidence TEXT,
    status TEXT NOT NULL, created_at TEXT NOT NULL, resolved_at TEXT
);
CREATE TABLE IF NOT EXISTS audit_log (
    audit_id TEXT PRIMARY KEY, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
    action TEXT NOT NULL, previous_value TEXT, new_value TEXT,
    source TEXT, timestamp TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_race_start ON sessions(race_id, scheduled_start);
CREATE INDEX IF NOT EXISTS idx_assignments_driver_season
    ON driver_team_assignments(driver_id, season_id, race_from, race_to);
CREATE INDEX IF NOT EXISTS idx_result_revisions_race ON result_revisions(race_id, effective_at);
CREATE INDEX IF NOT EXISTS idx_raw_source_lookup
    ON raw_source_records(provider_id, external_id, retrieved_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_interview_dedup
    ON interviews(driver_id, race_id, content_hash) WHERE content_hash IS NOT NULL;
'''


def _add_missing_columns(db: sqlite3.Connection, table: str, columns: dict[str, str]) -> None:
    existing = {row[1] for row in db.execute(f'PRAGMA table_info({table})')}
    for name, definition in columns.items():
        if name not in existing:
            db.execute(f'ALTER TABLE {table} ADD COLUMN {name} {definition}')


def migrate(path: str) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    now = utc_now()
    # Foreign keys are disabled only while rebuilding the two v1 tables whose
    # time columns were incorrectly NOT NULL. All rows are copied transactionally.
    with closing(sqlite3.connect(path)) as db, db:
        db.executescript(SCHEMA)
        session_start = next(
            row for row in db.execute('PRAGMA table_info(sessions)')
            if row[1] == 'scheduled_start'
        )
        if session_start[3]:
            db.executescript('''
                CREATE TABLE sessions_v3 (
                    session_id TEXT PRIMARY KEY, race_id TEXT NOT NULL REFERENCES races(race_id),
                    session_type TEXT NOT NULL, display_name TEXT NOT NULL,
                    scheduled_start TEXT, scheduled_end TEXT, actual_start TEXT, actual_end TEXT,
                    status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                    UNIQUE(race_id, display_name)
                );
                INSERT INTO sessions_v3 SELECT * FROM sessions;
                DROP TABLE sessions;
                ALTER TABLE sessions_v3 RENAME TO sessions;
                CREATE TABLE schedule_revisions_v3 (
                    revision_id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL REFERENCES sessions(session_id),
                    previous_start TEXT, new_start TEXT, reason TEXT,
                    source_provider_id TEXT NOT NULL REFERENCES providers(provider_id),
                    created_at TEXT NOT NULL,
                    UNIQUE(session_id, previous_start, new_start)
                );
                INSERT INTO schedule_revisions_v3 SELECT * FROM schedule_revisions;
                DROP TABLE schedule_revisions;
                ALTER TABLE schedule_revisions_v3 RENAME TO schedule_revisions;
            ''')
        # Version 1 databases were created before the complete architecture.
        _add_missing_columns(db, 'providers', {'created_at': 'TEXT', 'updated_at': 'TEXT'})
        _add_missing_columns(db, 'seasons', {
            'start_date': 'TEXT', 'end_date': 'TEXT', 'regulation_set_id': 'TEXT',
        })
        _add_missing_columns(db, 'circuits', {
            'city': 'TEXT', 'latitude': 'REAL', 'longitude': 'REAL',
            'track_length': 'REAL', 'status': "TEXT NOT NULL DEFAULT 'active'",
        })
        _add_missing_columns(db, 'races', {
            'official_name': 'TEXT', 'scheduled_end': 'TEXT',
        })
        _add_missing_columns(db, 'circuit_external_identities', {
            'external_name': 'TEXT', 'last_verified_at': 'TEXT',
        })
        _add_missing_columns(db, 'race_external_identities', {
            'external_name': 'TEXT', 'last_verified_at': 'TEXT',
        })
        db.execute('''INSERT OR IGNORE INTO providers
            (provider_id,name,type,base_url,priority,status,created_at,updated_at)
            VALUES (?,?,?,?,?,?,?,?)''', (
                PROVIDER_ID, 'Jolpica F1', 'race_data',
                'https://api.jolpi.ca/ergast/f1', 100, 'unknown', now, now,
            ))
        db.execute('''INSERT OR IGNORE INTO provider_health VALUES
            (?,NULL,NULL,0,'jolpica-v1','ergast-v1','unknown')''', (PROVIDER_ID,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (1, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (2, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (3, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (4, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (5, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (6, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (7, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (8, ?)', (now,))
        db.execute('PRAGMA foreign_keys = ON')


def store_raw(db: sqlite3.Connection, external_id: str, payload) -> None:
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    digest = hashlib.sha256(raw.encode()).hexdigest()
    db.execute('''INSERT OR IGNORE INTO raw_source_records VALUES (?,?,?,?,?,?,?)''', (
        new_id('raw'), PROVIDER_ID, external_id, utc_now(), digest, raw, 'jolpica-v1',
    ))


def record_provider_health(path: str, success: bool, *, schema_changed: bool = False) -> None:
    now = utc_now()
    with closing(connect(path)) as db, db:
        if success:
            db.execute('''UPDATE provider_health SET last_success=?, consecutive_failures=0,
                status='healthy' WHERE provider_id=?''', (now, PROVIDER_ID))
        else:
            db.execute('''UPDATE provider_health SET last_failure=?,
                consecutive_failures=consecutive_failures+1,
                status=CASE WHEN ? THEN 'schema_changed'
                    WHEN consecutive_failures >= 2 THEN 'unavailable' ELSE 'degraded' END
                WHERE provider_id=?''', (now, schema_changed, PROVIDER_ID))
        db.execute('''UPDATE providers SET status=(SELECT status FROM provider_health
            WHERE provider_id=?), updated_at=? WHERE provider_id=?''',
            (PROVIDER_ID, now, PROVIDER_ID))
