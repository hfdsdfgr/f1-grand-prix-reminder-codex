import os
from typing import Annotated
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Query, Path
from fastapi.middleware.cors import CORSMiddleware

from app.models import (
    NextRace, ProviderHealthRead, RaceFeed, Race, ScheduleRevisionRead,
)
from app.lifecycle import with_lifecycle
from app.results import ResultsRepository, ResultsFeed, RaceStory, build_race_story
from app.repositories.schedules import ScheduleRepository


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.schedules = ScheduleRepository(os.getenv('DATABASE_PATH', 'data/schedules.db'))
    app.state.results = ResultsRepository(app.state.schedules.path)
    yield


app = FastAPI(title='GrandPrixReminder', version='0.1.0', lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv('CORS_ORIGINS', 'http://localhost:3000,http://127.0.0.1:3000').split(','),
    allow_methods=['GET'], allow_headers=['Accept', 'Content-Type'],
)


@app.get('/health')
def health():
    return {'status': 'ok'}


def schedule(season: int) -> RaceFeed:
    try:
        feed = app.state.schedules.season(season)
        now = datetime.now(timezone.utc)
        return feed.model_copy(update={
            'races': [with_lifecycle(race, now) for race in feed.races],
        })
    except Exception as exc:
        raise HTTPException(503, 'Race data is temporarily unavailable. Please retry.') from exc


@app.get('/api/v1/races', response_model=RaceFeed)
def races(
    season: int = Query(default=datetime.now(timezone.utc).year, ge=1950, le=2100),
    summaries: bool = Query(default=True),
):
    feed = schedule(season)
    if not summaries:
        return feed
    summary_feed = app.state.results.summaries(season)
    return feed.model_copy(update={
        'races': [race.model_copy(update={
            'summary': summary_feed.summaries.get(race.round),
        }) for race in feed.races],
        'summaries_stale': summary_feed.stale,
    })


@app.get('/api/v1/seasons', response_model=list[int])
def seasons():
    return list(range(datetime.now(timezone.utc).year, 1949, -1))


@app.get('/api/v1/next-race', response_model=NextRace)
def next_race():
    now = datetime.now(timezone.utc)
    feed = schedule(now.year)
    for race in feed.races:
        if race.lifecycle_phase != 'post_race' and race.status != 'cancelled':
            return NextRace(race=race, updated_at=feed.updated_at, stale=feed.stale)
    upcoming = schedule(now.year + 1)
    return NextRace(
        race=next(iter(upcoming.races), None),
        updated_at=min(feed.updated_at, upcoming.updated_at),
        stale=feed.stale or upcoming.stale,
    )


@app.get('/api/v1/data-health', response_model=list[ProviderHealthRead])
def data_health():
    return [app.state.schedules.health()]


RaceId = Annotated[str, Path(pattern=r'^(19[5-9][0-9]|20[0-9]{2}|2100)-([1-9][0-9]?)$')]


@app.get('/api/v1/races/{race_id}', response_model=Race)
def race_detail(race_id: RaceId):
    season, _ = map(int, race_id.split('-'))
    race = next((r for r in schedule(season).races if r.id == race_id), None)
    if race is None:
        raise HTTPException(404, 'Race not found')
    return race


@app.get('/api/v1/races/{race_id}/schedule-revisions',
         response_model=list[ScheduleRevisionRead])
def schedule_revisions(race_id: RaceId):
    race_detail(race_id)
    return app.state.schedules.revisions(race_id)


def session_results(race_id: str, kind: str) -> ResultsFeed:
    race = race_detail(race_id)
    try:
        return app.state.results.load(race.season, race.round, kind)
    except Exception as exc:
        raise HTTPException(503, 'Results are temporarily unavailable. Please retry.') from exc


@app.get('/api/v1/races/{race_id}/results', response_model=ResultsFeed)
def results(race_id: RaceId):
    return session_results(race_id, 'results')


@app.get('/api/v1/races/{race_id}/qualifying', response_model=ResultsFeed)
def qualifying(race_id: RaceId):
    return session_results(race_id, 'qualifying')


@app.get('/api/v1/races/{race_id}/story', response_model=RaceStory)
def race_story(race_id: RaceId):
    race = race_detail(race_id)
    try:
        feed = app.state.results.load(race.season, race.round, 'results')
        return build_race_story(feed)
    except Exception as exc:
        raise HTTPException(503, 'Race story is temporarily unavailable. Please retry.') from exc
