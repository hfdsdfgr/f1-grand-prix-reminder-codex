"""Read the season's upgrade archive with per-upgrade source attribution."""
import sqlite3
from contextlib import closing
from datetime import datetime, timezone

from pydantic import BaseModel, HttpUrl, ValidationError

from app.data_schema import connect


class UpgradeSource(BaseModel):
    provider: str
    url: HttpUrl
    published_at: datetime | None = None


class UpgradeRead(BaseModel):
    id: str
    team_id: str
    team: str
    race_id: str | None
    race: str | None
    round: int | None
    component_id: str
    component: str
    title: str
    change: str | None
    goal: str | None
    expected_effect: str | None
    status: str
    confidence: str
    sources: list[UpgradeSource]


class EvolutionTimelineEvent(BaseModel):
    race_id: str
    race: str
    round: int
    upgrade_ids: list[str]


class EvolutionFeed(BaseModel):
    season: int
    upgrades: list[UpgradeRead]
    timeline: list[EvolutionTimelineEvent]
    updated_at: datetime
    stale: bool = False


class EvolutionRaceDetail(BaseModel):
    race_id: str
    upgrades: list[UpgradeRead]


def load_evolution(path: str, season: int) -> EvolutionFeed:
    with closing(connect(path)) as db:
        db.row_factory = sqlite3.Row
        rows = db.execute('''SELECT u.*,ts.team_id,ts.display_name AS team,
            r.display_name AS race,r.round,c.canonical_name AS component
            FROM upgrades u JOIN team_seasons ts ON ts.team_season_id=u.team_season_id
            JOIN seasons s ON s.season_id=ts.season_id
            JOIN car_component_types c ON c.component_type_id=u.component_type_id
            LEFT JOIN races r ON r.race_id=u.introduced_race_id AND r.season_id=ts.season_id
            WHERE s.year=? AND u.review_status='published'
            AND (u.introduced_race_id IS NULL OR r.race_id IS NOT NULL)
            ORDER BY r.round IS NULL,r.round,u.created_at,u.upgrade_id''', (season,)).fetchall()
        source_rows = db.execute('''SELECT DISTINCT uc.upgrade_id,d.publisher AS provider,
            d.canonical_url AS url,(SELECT r.published_at FROM evolution_source_revisions r
                WHERE r.source_id=d.source_id AND r.published_at IS NOT NULL
                ORDER BY r.fetched_at DESC LIMIT 1) AS published_at
            FROM upgrade_claims uc
            JOIN evolution_claims c ON c.claim_id=uc.claim_id
            JOIN claim_evidence ce ON ce.claim_id=c.claim_id
            JOIN evidence_anchors a ON a.anchor_id=ce.anchor_id
            JOIN evolution_source_documents d ON d.source_id=a.source_id
            JOIN upgrades u ON u.upgrade_id=uc.upgrade_id
            JOIN team_seasons ts ON ts.team_season_id=u.team_season_id
            JOIN seasons s ON s.season_id=ts.season_id
            WHERE s.year=? AND u.review_status='published' AND c.review_status='published'
            AND uc.status='accepted' ORDER BY d.canonical_url''', (season,)).fetchall()
        race_rows = db.execute('''SELECT r.display_name AS race,r.round
            FROM races r JOIN seasons s ON s.season_id=r.season_id
            WHERE s.year=? AND r.round IS NOT NULL ORDER BY r.round''', (season,)).fetchall()
    sources = {}
    for row in source_rows:
        try:
            source = UpgradeSource(provider=row['provider'], url=row['url'],
                                   published_at=row['published_at'])
        except ValidationError:
            continue
        sources.setdefault(row['upgrade_id'], []).append(source)
    upgrades = [UpgradeRead(
        id=row['upgrade_id'], team_id=row['team_id'], team=row['team'],
        race_id=f"{season}-{row['round']}" if row['round'] is not None else None,
        race=row['race'], round=row['round'], component_id=row['component_type_id'],
        component=row['component'], title=row['title'], change=row['change_description'],
        goal=row['technical_goal'], expected_effect=row['expected_effect'],
        status=row['status'], confidence=row['confidence'], sources=sources[row['upgrade_id']],
    ) for row in rows if row['upgrade_id'] in sources]
    upgrade_ids = {}
    for upgrade in upgrades:
        if upgrade.race_id is not None:
            upgrade_ids.setdefault(upgrade.race_id, []).append(upgrade.id)
    timeline = [EvolutionTimelineEvent(
        race_id=f"{season}-{row['round']}", race=row['race'], round=row['round'],
        upgrade_ids=upgrade_ids.get(f"{season}-{row['round']}", []),
    ) for row in race_rows]
    return EvolutionFeed(season=season, upgrades=upgrades, timeline=timeline,
                         updated_at=datetime.now(timezone.utc))


def load_race_evolution(path: str, race_id: str) -> EvolutionRaceDetail:
    season, _ = map(int, race_id.split('-'))
    feed = load_evolution(path, season)
    return EvolutionRaceDetail(
        race_id=race_id, upgrades=[item for item in feed.upgrades if item.race_id == race_id],
    )
