from datetime import datetime, timedelta

from app.models import Race, Session


_DURATION = {
    'practice': timedelta(minutes=90),
    'qualifying': timedelta(minutes=90),
    'sprint_qualifying': timedelta(minutes=90),
    'sprint': timedelta(minutes=90),
    'race': timedelta(hours=4),
}


def _session_status(session: Session, now: datetime) -> str:
    if session.status in {'cancelled', 'delayed', 'rescheduled'}:
        return session.status
    start = session.actual_start or session.starts_at
    if start is None:
        return 'unknown'
    end = session.actual_end or session.scheduled_end or (
        start + _DURATION.get(session.session_type or 'other', timedelta(hours=2))
    )
    if session.actual_end or now >= end:
        return 'completed'
    if session.actual_start or now >= start:
        return 'started'
    return 'scheduled'


def with_lifecycle(race: Race, now: datetime) -> Race:
    """Derive a current read model without mutating historical schedule data."""
    sessions = [
        session.model_copy(update={'status': _session_status(session, now)})
        for session in race.sessions
    ]
    timed = [session for session in sessions if session.starts_at is not None]
    current = next(
        (session for session in timed if session.status in {'started', 'delayed'}),
        None,
    )
    upcoming = next(
        (session for session in timed if session.starts_at > now and session.status != 'cancelled'),
        None,
    )
    first = timed[0] if timed else None
    race_session = next(
        (session for session in reversed(timed) if session.session_type == 'race'),
        None,
    )
    if first is None or now < first.starts_at:
        phase = 'pre_race'
    elif race_session is None or race_session.status != 'completed':
        phase = 'race_weekend'
    else:
        phase = 'post_race'
    status = race.status
    if status != 'cancelled':
        status = {
            'pre_race': 'scheduled',
            'race_weekend': 'ongoing',
            'post_race': 'completed',
        }[phase]
    return race.model_copy(update={
        'sessions': sessions,
        'lifecycle_phase': phase,
        'current_session': current,
        'next_session': upcoming,
        'countdown_target': upcoming.starts_at if upcoming else None,
        'status': status,
    })
