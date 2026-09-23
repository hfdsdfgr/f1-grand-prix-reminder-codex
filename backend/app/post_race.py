"""Durable, restart-safe post-race job orchestration."""
import asyncio
import hashlib
import inspect
import json
import logging
import os
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Awaitable, Callable

from app.data_schema import connect, migrate
from app.briefing_worker import execute_briefing
from app.evolution_worker.worker import execute_discovered_evolution
from app.evolution_worker.auto_review import auto_review_race
from app.localization_worker import localize_race


logger = logging.getLogger('post_race')
UTC = timezone.utc
STAGES = ('initial', 'supplemental', 'final')
Worker = Callable[[str, str], dict | Awaitable[dict]]


def _parse(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value.replace('Z', '+00:00')) if value else None


def _iso(value: datetime) -> str:
    return value.astimezone(UTC).isoformat()


def _job_id(public_race_id: str, worker_type: str, stage: str) -> str:
    digest = hashlib.sha256(f'{public_race_id}|{worker_type}|{stage}'.encode()).hexdigest()
    return f'prj_{digest[:24]}'


def _safe_error(exc: Exception) -> str:
    message = f'{type(exc).__name__}: {exc}'
    secret = os.getenv('DEEPSEEK_API_KEY')
    if secret:
        message = message.replace(secret, '[REDACTED]')
    return message[:1000]


class PostRaceOrchestrator:
    def __init__(self, path: str, runners: dict[str, Worker] | None = None, *,
                 retry_delays: tuple[timedelta, ...] = (
                     timedelta(minutes=5), timedelta(minutes=30)),
                 catchup_window: timedelta = timedelta(hours=72),
                 running_timeout: timedelta = timedelta(minutes=30)):
        self.path = path
        migrate(path)
        self.runners = runners or {'evolution': self._run_evolution, 'briefing': self._run_briefing}
        self.retry_delays = retry_delays
        self.max_attempts = len(retry_delays) + 1
        self.catchup_window = catchup_window
        self.running_timeout = running_timeout

    @staticmethod
    def _stage_times(finished_at: datetime) -> dict[str, datetime]:
        next_day = (finished_at + timedelta(days=1)).date()
        final = datetime.combine(next_day, datetime.min.time(), UTC).replace(hour=10)
        return {
            'initial': finished_at + timedelta(hours=2),
            'supplemental': finished_at + timedelta(hours=8),
            'final': max(finished_at + timedelta(hours=8), final),
        }

    def _finished_races(self, now: datetime, public_race_id: str | None = None):
        params: list[object] = []
        where = "s.session_type='race'"
        if public_race_id:
            where += ' AND rei.external_id=?'
            params.append(public_race_id)
        with closing(connect(self.path)) as db:
            rows = db.execute(f'''SELECT r.race_id,rei.external_id,r.status,
                s.status,s.scheduled_start,s.scheduled_end,s.actual_end
                FROM races r JOIN race_external_identities rei ON rei.race_id=r.race_id
                JOIN sessions s ON s.race_id=r.race_id
                WHERE rei.provider_id='prv_jolpica' AND {where}''', params).fetchall()
        result = []
        for race_id, public_id, race_status, session_status, start, scheduled_end, actual_end in rows:
            if race_status == 'cancelled' or session_status == 'cancelled':
                continue
            confirmed = actual_end or (
                scheduled_end if race_status == 'completed' or session_status == 'completed' else None)
            if confirmed:
                finished_at, method = _parse(confirmed), 'provider_confirmed'
            else:
                started = _parse(start)
                if not started or now < started + timedelta(hours=4):
                    continue
                finished_at, method = started + timedelta(hours=4), 'schedule_fallback'
            result.append((race_id, public_id, finished_at, method))
        return result

    def ensure_jobs(self, now: datetime | None = None, *, replay_race: str | None = None) -> int:
        now = (now or datetime.now(UTC)).astimezone(UTC)
        created = 0
        races = self._finished_races(now, replay_race)
        with closing(connect(self.path)) as db, db:
            for race_id, public_id, finished_at, method in races:
                if not replay_race and now - finished_at > self.catchup_window:
                    continue
                if replay_race:
                    method = 'replay'
                for worker_type in self.runners:
                    for stage, scheduled_at in self._stage_times(finished_at).items():
                        before = db.total_changes
                        db.execute('''INSERT INTO post_race_jobs
                            (job_id,race_id,public_race_id,worker_type,processing_stage,
                             finish_detection_method,scheduled_at,next_attempt_at,status,
                             attempt_count,created_at,updated_at)
                            VALUES (?,?,?,?,?,?,?,?, 'scheduled',0,?,?)
                            ON CONFLICT(public_race_id,worker_type,processing_stage) DO NOTHING''',
                            (_job_id(public_id, worker_type, stage), race_id, public_id,
                             worker_type, stage, method, _iso(scheduled_at),
                             _iso(scheduled_at), _iso(now), _iso(now)))
                        created += db.total_changes - before
        return created

    def recover_stale(self, now: datetime | None = None) -> int:
        now = (now or datetime.now(UTC)).astimezone(UTC)
        cutoff = _iso(now - self.running_timeout)
        with closing(connect(self.path)) as db, db:
            rows = db.execute('''SELECT job_id,attempt_count FROM post_race_jobs
                WHERE status='running' AND started_at<?''', (cutoff,)).fetchall()
            for job_id, attempts in rows:
                status = 'failed' if attempts >= self.max_attempts else 'retry_pending'
                db.execute('''UPDATE post_race_jobs SET status=?,next_attempt_at=?,
                    error='Interrupted while running',updated_at=? WHERE job_id=?''',
                           (status, _iso(now), _iso(now), job_id))
        return len(rows)

    def _claim(self, now: datetime, only_stage: str | None = None):
        db = connect(self.path)
        try:
            db.execute('BEGIN IMMEDIATE')
            stage_sql = ' AND processing_stage=?' if only_stage else ''
            params: list[object] = [_iso(now)]
            if only_stage:
                params.append(only_stage)
            row = db.execute(f'''SELECT job_id,public_race_id,worker_type,processing_stage
                FROM post_race_jobs WHERE status IN ('scheduled','retry_pending')
                AND next_attempt_at<=? {stage_sql}
                ORDER BY next_attempt_at,created_at LIMIT 1''', params).fetchone()
            if not row:
                db.commit()
                return None
            updated = db.execute('''UPDATE post_race_jobs SET status='running',started_at=?,
                attempt_count=attempt_count+1,error=NULL,updated_at=?
                WHERE job_id=? AND status IN ('scheduled','retry_pending')''',
                                 (_iso(now), _iso(now), row[0])).rowcount
            db.commit()
            return row if updated else None
        finally:
            db.close()

    async def _run_evolution(self, public_race_id: str, stage: str) -> dict:
        result = await execute_discovered_evolution(self.path, public_race_id)
        result['auto_review'] = await auto_review_race(self.path, public_race_id)
        result['localization'] = await localize_race(self.path, public_race_id)
        return result

    async def _run_briefing(self, public_race_id: str, stage: str) -> dict:
        result = await execute_briefing(self.path, public_race_id,
                                        allow_race_day_sources=True)
        result['localization'] = await localize_race(self.path, public_race_id)
        return result

    async def _execute(self, job, now: datetime) -> None:
        job_id, public_id, worker_type, stage = job
        try:
            result = self.runners[worker_type](public_id, stage)
            if inspect.isawaitable(result):
                result = await result
            persistence = result.get('persistence', {}) if isinstance(result, dict) else {}
            metrics = (
                len(result.get('sources', [])) if isinstance(result, dict) else 0,
                len(result.get('sources', [])) - len(result.get('provider_failures', []))
                if isinstance(result, dict) else 0,
                persistence.get('inserted', 0),
                persistence.get('observed', 0),
            )
            with closing(connect(self.path)) as db, db:
                db.execute('''UPDATE post_race_jobs SET status='completed',completed_at=?,
                    error=NULL,sources_found=?,sources_fetched=?,claims_inserted=?,
                    claims_observed=?,updated_at=? WHERE job_id=?''',
                           (_iso(now), *metrics, _iso(now), job_id))
            self._log(job_id, metrics=metrics)
        except Exception as exc:
            error = _safe_error(exc)
            with closing(connect(self.path)) as db, db:
                attempts = db.execute('SELECT attempt_count FROM post_race_jobs WHERE job_id=?',
                                      (job_id,)).fetchone()[0]
                if attempts >= self.max_attempts:
                    status, next_at = 'failed', now
                else:
                    status = 'retry_pending'
                    next_at = now + self.retry_delays[attempts - 1]
                db.execute('''UPDATE post_race_jobs SET status=?,next_attempt_at=?,error=?,
                    updated_at=? WHERE job_id=?''',
                           (status, _iso(next_at), error, _iso(now), job_id))
            self._log(job_id)

    def _log(self, job_id: str, **extra) -> None:
        with closing(connect(self.path)) as db:
            row = db.execute('''SELECT public_race_id,worker_type,processing_stage,
                scheduled_at,started_at,completed_at,status,attempt_count,error,
                sources_found,sources_fetched,claims_inserted,claims_observed
                FROM post_race_jobs WHERE job_id=?''', (job_id,)).fetchone()
        keys = ('race_id', 'worker_type', 'stage', 'scheduled_at', 'started_at',
                'completed_at', 'status', 'attempt', 'error', 'sources_found',
                'sources_fetched', 'claims_inserted', 'claims_observed')
        payload = {'event': 'post_race_job', 'job_id': job_id,
                   **dict(zip(keys, row)), **extra}
        logger.info(json.dumps(payload, ensure_ascii=False, default=str))

    async def tick(self, now: datetime | None = None, *, replay_race: str | None = None,
                   only_stage: str | None = None) -> dict:
        now = (now or datetime.now(UTC)).astimezone(UTC)
        recovered = self.recover_stale(now)
        created = self.ensure_jobs(now, replay_race=replay_race)
        processed = 0
        while job := self._claim(now, only_stage):
            await self._execute(job, now)
            processed += 1
        return {'jobs_created': created, 'jobs_recovered': recovered, 'jobs_processed': processed}
