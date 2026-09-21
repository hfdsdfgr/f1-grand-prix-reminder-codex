"""SQLite schema and small shared helpers for the versioned data model."""
import hashlib
import json
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from uuid import uuid4


PROVIDER_ID = 'prv_jolpica'


def new_id(prefix: str) -> str:
    return f'{prefix}_{uuid4().hex}'


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _canonical_evolution_url(url: str) -> str:
    parsed = urlsplit(url)
    tracking = {'fbclid', 'gclid', 'mc_cid', 'mc_eid', 'ref', 'source'}
    query = urlencode([(key, value) for key, value in parse_qsl(parsed.query, keep_blank_values=True)
                       if not key.casefold().startswith('utm_') and key.casefold() not in tracking])
    path = parsed.path or '/'
    if path != '/':
        path = path.rstrip('/')
    return urlunsplit((parsed.scheme.casefold(), parsed.netloc.casefold(), path, query, ''))


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
    status TEXT NOT NULL, confidence TEXT NOT NULL,
    review_status TEXT NOT NULL DEFAULT 'published'
        CHECK(review_status IN ('pending_review','published','rejected')),
    event_fingerprint TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS specification_upgrades (
    specification_id TEXT NOT NULL REFERENCES car_specifications(specification_id),
    upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id),
    status TEXT NOT NULL DEFAULT 'installed', PRIMARY KEY(specification_id, upgrade_id)
);
CREATE TABLE IF NOT EXISTS upgrade_sources (
    source_id TEXT PRIMARY KEY,
    upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id),
    provider TEXT NOT NULL, url TEXT NOT NULL, published_at TEXT,
    retrieved_at TEXT NOT NULL, original_text TEXT NOT NULL,
    UNIQUE(upgrade_id, url)
);
CREATE TABLE IF NOT EXISTS upgrade_lifecycle_events (
    event_id TEXT PRIMARY KEY, upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id),
    race_id TEXT REFERENCES races(race_id), session_id TEXT REFERENCES sessions(session_id),
    event_type TEXT NOT NULL CHECK(event_type IN
        ('introduced','tested','retained','modified','removed','reintroduced','superseded','unknown')),
    timestamp TEXT, source TEXT NOT NULL,
    claim_id TEXT, lifecycle_claim_key TEXT,
    review_status TEXT NOT NULL DEFAULT 'published'
        CHECK(review_status IN ('pending_review','published','rejected'))
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
CREATE TABLE IF NOT EXISTS evolution_source_documents (
    source_id TEXT PRIMARY KEY, canonical_url TEXT NOT NULL UNIQUE,
    publisher TEXT NOT NULL, source_type TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS evolution_source_revisions (
    revision_id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES evolution_source_documents(source_id) ON DELETE CASCADE,
    race_id TEXT NOT NULL REFERENCES races(race_id),
    publication_phase TEXT NOT NULL CHECK(publication_phase IN ('pre_race','weekend','post_race','unknown')),
    published_at TEXT, fetched_at TEXT NOT NULL, cleaned_text TEXT NOT NULL, content_hash TEXT NOT NULL,
    UNIQUE(source_id, content_hash)
);
CREATE TABLE IF NOT EXISTS evidence_anchors (
    anchor_id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES evolution_source_documents(source_id) ON DELETE CASCADE,
    first_revision_id TEXT NOT NULL REFERENCES evolution_source_revisions(revision_id),
    anchor_text TEXT NOT NULL, anchor_hash TEXT NOT NULL,
    UNIQUE(source_id, anchor_hash)
);
CREATE TABLE IF NOT EXISTS evidence_anchor_revisions (
    anchor_id TEXT NOT NULL REFERENCES evidence_anchors(anchor_id) ON DELETE CASCADE,
    revision_id TEXT NOT NULL REFERENCES evolution_source_revisions(revision_id) ON DELETE CASCADE,
    start_offset INTEGER, end_offset INTEGER,
    PRIMARY KEY(anchor_id, revision_id)
);
CREATE TABLE IF NOT EXISTS evolution_claims (
    claim_id TEXT PRIMARY KEY, claim_key TEXT NOT NULL UNIQUE,
    race_id TEXT NOT NULL REFERENCES races(race_id),
    team_season_id TEXT NOT NULL REFERENCES team_seasons(team_season_id),
    component_type_id TEXT NOT NULL REFERENCES car_component_types(component_type_id),
    primary_anchor_id TEXT NOT NULL REFERENCES evidence_anchors(anchor_id),
    proposed_change TEXT NOT NULL, proposed_goal TEXT, proposed_expected_effect TEXT,
    proposed_status TEXT NOT NULL, evidence_level TEXT NOT NULL, confidence TEXT NOT NULL,
    review_status TEXT NOT NULL CHECK(review_status IN ('pending_review','published','rejected')),
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS claim_evidence (
    claim_id TEXT NOT NULL REFERENCES evolution_claims(claim_id) ON DELETE CASCADE,
    anchor_id TEXT NOT NULL REFERENCES evidence_anchors(anchor_id),
    supports_field TEXT NOT NULL CHECK(supports_field IN
        ('change','goal','expected_effect','status','driver_feedback')),
    PRIMARY KEY(claim_id, anchor_id, supports_field)
);
CREATE TABLE IF NOT EXISTS claim_observations (
    observation_id TEXT PRIMARY KEY,
    claim_id TEXT NOT NULL REFERENCES evolution_claims(claim_id) ON DELETE CASCADE,
    generation_id TEXT NOT NULL REFERENCES ai_generations(generation_id),
    proposed_json TEXT NOT NULL, observed_at TEXT NOT NULL,
    UNIQUE(claim_id, generation_id)
);
CREATE TABLE IF NOT EXISTS upgrade_claims (
    upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id) ON DELETE CASCADE,
    claim_id TEXT NOT NULL UNIQUE REFERENCES evolution_claims(claim_id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK(status IN ('pending_review','accepted','rejected')),
    created_at TEXT NOT NULL, reviewed_at TEXT,
    PRIMARY KEY(upgrade_id, claim_id)
);
CREATE TABLE IF NOT EXISTS evolution_upgrade_sources (
    upgrade_id TEXT NOT NULL REFERENCES upgrades(upgrade_id),
    source_id TEXT NOT NULL REFERENCES evolution_source_documents(source_id),
    PRIMARY KEY(upgrade_id, source_id)
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
    race_assessment TEXT, car_strengths TEXT, car_weaknesses TEXT, technical_issues TEXT,
    incidents TEXT, key_quotes TEXT,
    status TEXT NOT NULL, generation_id TEXT NOT NULL REFERENCES ai_generations(generation_id),
    UNIQUE(race_id, generation_id)
);
CREATE TABLE IF NOT EXISTS briefing_evidence (
    race_brief_id TEXT NOT NULL REFERENCES race_briefs(race_brief_id) ON DELETE CASCADE,
    field TEXT NOT NULL, interview_id TEXT NOT NULL REFERENCES interviews(interview_id),
    quote TEXT NOT NULL,
    PRIMARY KEY(race_brief_id, field, interview_id, quote)
);
CREATE TABLE IF NOT EXISTS review_items (
    review_id TEXT PRIMARY KEY, entity_type TEXT NOT NULL, entity_id TEXT,
    issue_type TEXT NOT NULL, description TEXT NOT NULL, confidence TEXT,
    status TEXT NOT NULL, created_at TEXT NOT NULL, resolved_at TEXT
);
CREATE TABLE IF NOT EXISTS post_race_jobs (
    job_id TEXT PRIMARY KEY,
    race_id TEXT NOT NULL REFERENCES races(race_id) ON DELETE CASCADE,
    public_race_id TEXT NOT NULL,
    worker_type TEXT NOT NULL CHECK(worker_type IN ('evolution','briefing')),
    processing_stage TEXT NOT NULL CHECK(processing_stage IN ('initial','supplemental','final')),
    finish_detection_method TEXT NOT NULL CHECK(finish_detection_method IN
        ('provider_confirmed','schedule_fallback','replay')),
    scheduled_at TEXT NOT NULL, next_attempt_at TEXT NOT NULL,
    started_at TEXT, completed_at TEXT,
    status TEXT NOT NULL CHECK(status IN
        ('scheduled','running','completed','failed','retry_pending')),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count >= 0),
    error TEXT, sources_found INTEGER, sources_fetched INTEGER,
    claims_inserted INTEGER, claims_observed INTEGER,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(public_race_id,worker_type,processing_stage)
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
CREATE UNIQUE INDEX IF NOT EXISTS idx_review_pending_entity
    ON review_items(entity_type, entity_id) WHERE entity_id IS NOT NULL AND status='pending_review';
CREATE INDEX IF NOT EXISTS idx_post_race_jobs_due
    ON post_race_jobs(status,next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_briefing_evidence_brief ON briefing_evidence(race_brief_id,field);
'''


def _add_missing_columns(db: sqlite3.Connection, table: str, columns: dict[str, str]) -> None:
    existing = {row[1] for row in db.execute(f'PRAGMA table_info({table})')}
    for name, definition in columns.items():
        if name not in existing:
            db.execute(f'ALTER TABLE {table} ADD COLUMN {name} {definition}')


def _legacy_anchor(text: str, change: str | None) -> tuple[str, int | None, int | None]:
    if change:
        start = text.casefold().find(change.casefold())
        if start >= 0:
            left = text.rfind('\n', 0, start) + 1
            right = text.find('\n', start + len(change))
            right = len(text) if right < 0 else right
            return text[left:right].strip(), left, right
    return (change or '[legacy reviewed Evolution event]'), None, None


def _migrate_evolution_identity(db: sqlite3.Connection, now: str) -> None:
    columns = {row[1] for row in db.execute('PRAGMA table_info(evolution_source_documents)')}
    if 'canonical_url' not in columns:
        old_rows = db.execute('''SELECT source_id,race_id,publisher,source_type,publication_phase,
            url,published_at,fetched_at,cleaned_text,content_hash FROM evolution_source_documents''').fetchall()
        db.execute('''CREATE TABLE evolution_source_documents_v11 (
            source_id TEXT PRIMARY KEY, canonical_url TEXT NOT NULL UNIQUE,
            publisher TEXT NOT NULL, source_type TEXT NOT NULL, created_at TEXT NOT NULL)''')
        for row in old_rows:
            old_source_id, race_id, publisher, source_type, phase, url, published, fetched, text, digest = row
            url = _canonical_evolution_url(url)
            source_id = 'src_' + hashlib.sha256(url.encode()).hexdigest()[:20]
            db.execute('''INSERT INTO evolution_source_documents_v11 VALUES (?,?,?,?,?)
                ON CONFLICT(canonical_url) DO NOTHING''',
                       (source_id, url, publisher, source_type, fetched or now))
            revision_id = 'rev_' + hashlib.sha256(f'{source_id}|{digest}'.encode()).hexdigest()[:24]
            db.execute('''INSERT INTO evolution_source_revisions
                (revision_id,source_id,race_id,publication_phase,published_at,fetched_at,cleaned_text,content_hash)
                VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(source_id,content_hash) DO NOTHING''',
                       (revision_id, source_id, race_id, phase, published, fetched, text, digest))
            if old_source_id != source_id:
                db.execute('UPDATE evolution_upgrade_sources SET source_id=? WHERE source_id=?',
                           (source_id, old_source_id))
        db.execute('DROP TABLE evolution_source_documents')
        db.execute('ALTER TABLE evolution_source_documents_v11 RENAME TO evolution_source_documents')

    _add_missing_columns(db, 'upgrade_lifecycle_events', {
        'claim_id': 'TEXT', 'lifecycle_claim_key': 'TEXT',
        'review_status': "TEXT NOT NULL DEFAULT 'published'",
    })
    db.execute('DROP INDEX IF EXISTS idx_upgrade_fingerprint')
    db.execute('DROP INDEX IF EXISTS idx_review_entity')
    db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_review_pending_entity
        ON review_items(entity_type,entity_id)
        WHERE entity_id IS NOT NULL AND status='pending_review' ''')
    db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_lifecycle_claim
        ON upgrade_lifecycle_events(upgrade_id,lifecycle_claim_key)
        WHERE lifecycle_claim_key IS NOT NULL''')
    db.executescript('''
        CREATE TRIGGER IF NOT EXISTS upgrades_review_status_insert
        BEFORE INSERT ON upgrades WHEN NEW.review_status NOT IN ('pending_review','published','rejected')
        BEGIN SELECT RAISE(ABORT,'invalid upgrade review_status'); END;
        CREATE TRIGGER IF NOT EXISTS upgrades_review_status_update
        BEFORE UPDATE OF review_status ON upgrades WHEN NEW.review_status NOT IN ('pending_review','published','rejected')
        BEGIN SELECT RAISE(ABORT,'invalid upgrade review_status'); END;
        CREATE TRIGGER IF NOT EXISTS lifecycle_type_insert
        BEFORE INSERT ON upgrade_lifecycle_events WHEN NEW.event_type NOT IN
          ('introduced','tested','retained','modified','removed','reintroduced','superseded','unknown')
        BEGIN SELECT RAISE(ABORT,'invalid lifecycle type'); END;
    ''')

    rows = db.execute('''SELECT u.upgrade_id,u.team_season_id,u.introduced_race_id,
        u.component_type_id,u.change_description,u.technical_goal,u.expected_effect,u.status,
        u.confidence,u.review_status,d.source_id,r.revision_id,r.cleaned_text
        FROM upgrades u JOIN evolution_upgrade_sources eus ON eus.upgrade_id=u.upgrade_id
        JOIN evolution_source_documents d ON d.source_id=eus.source_id
        JOIN evolution_source_revisions r ON r.source_id=d.source_id
        WHERE r.rowid=(SELECT r2.rowid FROM evolution_source_revisions r2
            WHERE r2.source_id=d.source_id ORDER BY r2.fetched_at DESC LIMIT 1)''').fetchall()
    for row in rows:
        (upgrade_id, team_season_id, race_id, component_id, change, goal, effect,
         event_type, confidence, review_status, source_id, revision_id, text) = row
        anchor_text, start, end = _legacy_anchor(text, change)
        anchor_hash = hashlib.sha256(' '.join(anchor_text.casefold().split()).encode()).hexdigest()
        anchor_id = 'anc_' + hashlib.sha256(f'{source_id}|{anchor_hash}'.encode()).hexdigest()[:24]
        claim_key = hashlib.sha256(
            f'{race_id}|{team_season_id}|{component_id}|{anchor_id}'.encode()).hexdigest()
        claim_id = 'clm_' + claim_key[:24]
        db.execute('''INSERT INTO evidence_anchors
            (anchor_id,source_id,first_revision_id,anchor_text,anchor_hash) VALUES (?,?,?,?,?)
            ON CONFLICT(anchor_id) DO NOTHING''',
                   (anchor_id, source_id, revision_id, anchor_text, anchor_hash))
        db.execute('''INSERT INTO evidence_anchor_revisions VALUES (?,?,?,?)
            ON CONFLICT(anchor_id,revision_id) DO NOTHING''', (anchor_id, revision_id, start, end))
        db.execute('''INSERT INTO evolution_claims VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(claim_key) DO NOTHING''', (
                claim_id, claim_key, race_id, team_season_id, component_id, anchor_id,
                change or '', goal, effect, event_type, 'reported', confidence,
                review_status, now, now,
            ))
        db.execute('''INSERT INTO claim_evidence VALUES (?,?,?)
            ON CONFLICT(claim_id,anchor_id,supports_field) DO NOTHING''',
                   (claim_id, anchor_id, 'change'))
        mapping_status = {'published': 'accepted', 'rejected': 'rejected'}.get(
            review_status, 'pending_review')
        db.execute('''INSERT INTO upgrade_claims VALUES (?,?,?,?,?)
            ON CONFLICT(claim_id) DO NOTHING''',
                   (upgrade_id, claim_id, mapping_status, now,
                    now if mapping_status != 'pending_review' else None))

    for event_id, upgrade_id, race_id, source in db.execute('''SELECT event_id,upgrade_id,race_id,source
        FROM upgrade_lifecycle_events WHERE lifecycle_claim_key IS NULL''').fetchall():
        key = hashlib.sha256(f'{upgrade_id}|{race_id}|{source}'.encode()).hexdigest()
        claim = db.execute('SELECT claim_id FROM upgrade_claims WHERE upgrade_id=? LIMIT 1',
                           (upgrade_id,)).fetchone()
        db.execute('''UPDATE upgrade_lifecycle_events SET lifecycle_claim_key=?,claim_id=?
            WHERE event_id=?''', (key, claim[0] if claim else None, event_id))

    groups = db.execute('''SELECT upgrade_id,claim_id FROM upgrade_lifecycle_events
        WHERE claim_id IS NOT NULL GROUP BY upgrade_id,claim_id''').fetchall()
    for upgrade_id, claim_id in groups:
        events = db.execute('''SELECT event_id FROM upgrade_lifecycle_events
            WHERE upgrade_id=? AND claim_id=? ORDER BY timestamp,event_id''',
                            (upgrade_id, claim_id)).fetchall()
        keep = events[0][0]
        for duplicate in events[1:]:
            db.execute('DELETE FROM review_items WHERE entity_type=\'evolution_lifecycle\' AND entity_id=?',
                       (duplicate[0],))
            db.execute('DELETE FROM upgrade_lifecycle_events WHERE event_id=?', (duplicate[0],))
        anchor = db.execute('SELECT primary_anchor_id FROM evolution_claims WHERE claim_id=?',
                            (claim_id,)).fetchone()[0]
        key = hashlib.sha256(f'{upgrade_id}|{claim_id}'.encode()).hexdigest()
        db.execute('''UPDATE upgrade_lifecycle_events
            SET lifecycle_claim_key=?,source=? WHERE event_id=?''', (key, anchor, keep))


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
        _add_missing_columns(db, 'upgrades', {
            'review_status': "TEXT NOT NULL DEFAULT 'published'", 'event_fingerprint': 'TEXT',
        })
        _add_missing_columns(db, 'race_briefs', {
            'race_assessment': 'TEXT', 'car_strengths': 'TEXT', 'car_weaknesses': 'TEXT',
            'technical_issues': 'TEXT', 'incidents': 'TEXT', 'key_quotes': 'TEXT',
        })
        _migrate_evolution_identity(db, now)
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
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (9, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (10, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (11, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (12, ?)', (now,))
        db.execute('INSERT OR IGNORE INTO schema_migrations VALUES (13, ?)', (now,))
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
