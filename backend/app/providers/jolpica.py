from datetime import datetime, timezone

import httpx

from app.models import Race, Session

BASE_URL = 'https://api.jolpi.ca/ergast/f1'
HEADERS = {'User-Agent': 'GrandPrixReminder/0.1.0'}
SESSION_KEYS = {
    'FirstPractice': 'FP1',
    'SecondPractice': 'FP2',
    'ThirdPractice': 'FP3',
    'SprintQualifying': 'Sprint Qualifying',
    'Sprint': 'Sprint',
    'Qualifying': 'Qualifying',
}
SESSION_TYPES = {
    'FP1': 'practice', 'FP2': 'practice', 'FP3': 'practice',
    'Sprint Qualifying': 'sprint_qualifying', 'Sprint': 'sprint',
    'Qualifying': 'qualifying', 'Race': 'race',
}


def timestamp(value: dict) -> datetime | None:
    # Unknown start times remain unknown; never turn a date into midnight.
    if not value.get('time'):
        return None
    parsed = datetime.fromisoformat(
        f"{value['date']}T{value['time']}".replace('Z', '+00:00'),
    )
    if parsed.tzinfo is None:
        raise ValueError('Provider timestamp must include a timezone')
    return parsed


def normalize(raw: dict) -> Race:
    sessions = []
    for key, label in SESSION_KEYS.items():
        value = raw.get(key)
        if value:
            start = timestamp(value)
            sessions.append(Session(
                kind=label, starts_at=start, session_type=SESSION_TYPES[label],
                display_name=label,
                status=('scheduled' if start and start > datetime.now(timezone.utc)
                        else 'unknown'),
            ))
    start = timestamp(raw)
    if start:
        sessions.append(Session(
            kind='Race', starts_at=start, session_type='race', display_name='Race',
            status='scheduled' if start > datetime.now(timezone.utc) else 'unknown',
        ))
    return Race(
        id=f"{raw['season']}-{raw['round']}",
        season=int(raw['season']), round=int(raw['round']),
        name=raw['raceName'], circuit=raw['Circuit']['circuitName'],
        country=raw['Circuit']['Location']['country'], date=raw['date'],
        starts_at=start,
        sessions=sorted(
            sessions,
            key=lambda item: item.starts_at or datetime.max.replace(tzinfo=timezone.utc),
        ),
        source=f"{BASE_URL}/{raw['season']}/{raw['round']}/",
        provider_external_id=f"{raw['season']}-{raw['round']}",
        circuit_external_id=raw['Circuit'].get('circuitId'),
        status='scheduled' if start and start > datetime.now(timezone.utc) else 'unknown',
        raw_payload=raw,
    )


def fetch_season(season: int) -> list[Race]:
    response = httpx.get(
        f'{BASE_URL}/{season}/', params={'limit': 100}, headers=HEADERS, timeout=15,
    )
    response.raise_for_status()
    return [normalize(row) for row in response.json()['MRData']['RaceTable']['Races']]


def fetch_driver_standings(season: int) -> list[dict]:
    """Return source rows that explicitly associate each driver with a constructor."""
    response = httpx.get(
        f'{BASE_URL}/{season}/driverstandings/',
        params={'limit': 100}, headers=HEADERS, timeout=15,
    )
    response.raise_for_status()
    standings = response.json()['MRData']['StandingsTable'].get('StandingsLists') or []
    return (standings[0].get('DriverStandings') or []) if standings else []
