from datetime import datetime
from enum import StrEnum

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl


class ComponentId(StrEnum):
    FRONT_WING = 'front_wing'
    NOSE = 'nose'
    FRONT_SUSPENSION = 'front_suspension'
    FRONT_WHEELS = 'front_wheels'
    HALO = 'halo'
    COCKPIT = 'cockpit'
    SIDEPODS = 'sidepods'
    FLOOR = 'floor'
    ENGINE_COVER = 'engine_cover'
    REAR_SUSPENSION = 'rear_suspension'
    REAR_WHEELS = 'rear_wheels'
    BEAM_WING = 'beam_wing'
    REAR_WING = 'rear_wing'
    OTHER = 'other'


class UpgradeStatus(StrEnum):
    INTRODUCED = 'introduced'
    TESTED = 'tested'
    RETAINED = 'retained'
    MODIFIED = 'modified'
    REMOVED = 'removed'
    REINTRODUCED = 'reintroduced'
    SUPERSEDED = 'superseded'
    UNKNOWN = 'unknown'


class EvidenceLevel(StrEnum):
    CONFIRMED = 'confirmed'
    OBSERVED = 'observed'
    REPORTED = 'reported'
    UNVERIFIED = 'unverified'


class SourceDocument(BaseModel):
    model_config = ConfigDict(extra='forbid')

    source_id: str
    race_id: str
    publisher: str
    source_type: str
    source_tier: int = Field(ge=1, le=4)
    title: str
    url: HttpUrl
    published_at: datetime | None = None
    fetched_at: datetime
    publication_phase: Literal['pre_race', 'weekend', 'post_race', 'unknown'] = 'unknown'
    team_ids: list[str] = Field(default_factory=list)
    driver_ids: list[str] = Field(default_factory=list)
    raw_text: str
    cleaned_text: str
    content_hash: str


class ClaimEvidence(BaseModel):
    model_config = ConfigDict(extra='forbid')

    source_id: str
    quote: str = Field(min_length=1, max_length=800)
    supports: list[Literal['change', 'goal', 'expected_effect', 'status', 'driver_feedback']]


class EvidenceAnchor(BaseModel):
    model_config = ConfigDict(extra='forbid')

    anchor_id: str
    source_id: str
    anchor_text: str
    start_offset: int
    end_offset: int
    anchor_hash: str
    supports: list[Literal['change', 'goal', 'expected_effect', 'status', 'driver_feedback']]


class DriverFeedback(BaseModel):
    model_config = ConfigDict(extra='forbid')

    driver_id: str
    summary: str
    source_ids: list[str]


class EvolutionUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid')

    component_id: ComponentId
    change: str = Field(min_length=1)
    goal: str | None = None
    expected_effect: str | None = None
    status: UpgradeStatus = UpgradeStatus.UNKNOWN
    evidence_level: EvidenceLevel = EvidenceLevel.UNVERIFIED
    driver_feedback: list[DriverFeedback] = Field(default_factory=list)
    source_ids: list[str]
    evidence: list[ClaimEvidence]
    anchors: list[EvidenceAnchor] = Field(default_factory=list)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)


class EvolutionExtraction(BaseModel):
    model_config = ConfigDict(extra='forbid')

    race_id: str
    team_id: str
    car_model_id: str | None = None
    specification_id: str | None = None
    updates: list[EvolutionUpdate]


class ExtractionBatch(BaseModel):
    model_config = ConfigDict(extra='forbid')

    results: list[EvolutionExtraction]


class ValidatedBatch(BaseModel):
    results: list[EvolutionExtraction]
    issues: list[str]
    review_status: str = 'pending_review'


class BriefingEvidence(BaseModel):
    model_config = ConfigDict(extra='forbid')

    source_id: str
    quote: str = Field(min_length=1, max_length=800)


class BriefingFact(BaseModel):
    model_config = ConfigDict(extra='forbid')

    field: Literal['race_assessment', 'car_strengths', 'car_weaknesses', 'strategy', 'tyres',
                   'technical_issues', 'upgrade_feedback', 'incidents', 'future_expectations',
                   'key_quotes']
    value: str = Field(min_length=1, max_length=2000)
    evidence: list[BriefingEvidence] = Field(min_length=1)


class BriefingBatch(BaseModel):
    model_config = ConfigDict(extra='forbid')

    facts: list[BriefingFact]
