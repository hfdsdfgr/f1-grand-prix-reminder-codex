"""FastF1 adapter for post-race tyre stint facts."""
import os
from pathlib import Path


SOURCE_URL = 'https://github.com/theOehrly/Fast-F1'
_COMPOUNDS = {'SOFT', 'MEDIUM', 'HARD', 'INTERMEDIATE', 'WET'}
_cache_ready = False


def _known(value) -> bool:
    return value is not None and value == value  # NaN is the only value not equal to itself.


def normalize_laps(laps: list[dict], names: dict[str, str]) -> list[dict]:
    """Turn FastF1 lap records into source-backed stints without inference."""
    grouped: dict[tuple[str, int, str], list[dict]] = {}
    for lap in laps:
        driver, stint, compound = lap.get('Driver'), lap.get('Stint'), lap.get('Compound')
        if not (_known(driver) and _known(stint) and isinstance(compound, str)):
            continue
        compound = compound.upper()
        if compound not in _COMPOUNDS or not _known(lap.get('LapNumber')):
            continue
        grouped.setdefault((driver, int(stint), compound), []).append(lap)
    stints = []
    for (driver, _, compound), rows in sorted(grouped.items()):
        rows.sort(key=lambda row: row['LapNumber'])
        first, last = rows[0], rows[-1]
        pit_laps = [int(row['LapNumber']) for row in rows if _known(row.get('PitInTime'))]
        stints.append({
            'driver': names.get(driver, driver),
            'compound': compound.title(),
            'start_lap': int(first['LapNumber']),
            'end_lap': int(last['LapNumber']),
            'tyre_age_at_start': int(first['TyreLife']) if _known(first.get('TyreLife')) else None,
            'pit_lap': pit_laps[0] if pit_laps else None,
        })
    return stints


def fetch_strategy_rows(season: int, round_number: int) -> list[dict]:
    global _cache_ready
    import fastf1

    if not _cache_ready:
        cache_dir = Path(os.getenv('FASTF1_CACHE_PATH', 'data/fastf1-cache'))
        cache_dir.mkdir(parents=True, exist_ok=True)
        fastf1.Cache.enable_cache(str(cache_dir))
        _cache_ready = True
    session = fastf1.get_session(season, round_number, 'R')
    session.load(telemetry=False, weather=False, messages=False)
    names = {
        row['Abbreviation']: row['FullName']
        for _, row in session.results.iterrows()
        if _known(row.get('Abbreviation')) and _known(row.get('FullName'))
    }
    columns = ['Driver', 'LapNumber', 'Stint', 'Compound', 'TyreLife', 'PitInTime']
    return normalize_laps(session.laps[columns].to_dict('records'), names)
