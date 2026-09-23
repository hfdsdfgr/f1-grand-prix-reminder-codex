from datetime import date, datetime
from typing import Literal

from pydantic import AwareDatetime, BaseModel, Field, HttpUrl


class Session(BaseModel):
    internal_id: str | None = None
    kind: str
    starts_at: AwareDatetime | None
    session_type: str | None = None
    display_name: str | None = None
    scheduled_end: AwareDatetime | None = None
    actual_start: AwareDatetime | None = None
    actual_end: AwareDatetime | None = None
    status: Literal[
        'scheduled', 'delayed', 'started', 'completed',
        'cancelled', 'rescheduled', 'unknown',
    ] = 'unknown'


class RaceSummary(BaseModel):
    winner: str | None = None
    winner_team: str | None = None
    fastest_lap_driver: str | None = None
    fastest_lap_time: str | None = None
    fastest_lap_number: int | None = None


class CircuitCorner(BaseModel):
    turn_number: int = Field(ge=1)
    name: str
    x: float = Field(ge=0, le=500)
    y: float = Field(ge=0, le=500)
    source: HttpUrl


class CircuitLayout(BaseModel):
    id: str
    asset_path: str
    valid_from: int
    turns: int | None = None
    source: HttpUrl
    license: str
    corners: list[CircuitCorner] = Field(default_factory=list)


class Race(BaseModel):
    internal_id: str | None = None
    id: str
    season: int
    round: int
    name: str
    circuit: str
    country: str
    date: date
    starts_at: AwareDatetime | None
    sessions: list[Session]
    source: HttpUrl
    circuit_id: str | None = None
    status: Literal[
        'scheduled', 'rescheduled', 'ongoing', 'completed', 'cancelled', 'unknown',
    ] = 'unknown'
    provider_external_id: str | None = Field(default=None, exclude=True)
    circuit_external_id: str | None = Field(default=None, exclude=True)
    raw_payload: dict | None = Field(default=None, exclude=True)
    summary: RaceSummary | None = None
    circuit_layout: CircuitLayout | None = None
    lifecycle_phase: Literal['pre_race', 'race_weekend', 'post_race'] = 'pre_race'
    current_session: Session | None = None
    next_session: Session | None = None
    countdown_target: AwareDatetime | None = None


class RaceFeed(BaseModel):
    races: list[Race]
    updated_at: datetime
    stale: bool = False
    summaries_stale: bool = False


class NextRace(BaseModel):
    race: Race | None
    updated_at: datetime
    stale: bool = False


class ProviderHealthRead(BaseModel):
    provider_id: str
    name: str
    status: str
    last_success: datetime | None
    last_failure: datetime | None
    consecutive_failures: int
    parser_version: str
    schema_version: str


class ScheduleRevisionRead(BaseModel):
    revision_id: str
    session_id: str
    session: str
    previous_start: AwareDatetime | None
    new_start: AwareDatetime | None
    reason: str | None
    source_provider_id: str
    created_at: datetime
