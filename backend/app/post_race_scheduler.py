"""Command-line process for durable post-race automation."""
import argparse
import asyncio
import json
import logging
import os
from datetime import datetime, timezone

from app.post_race import PostRaceOrchestrator, STAGES
from app.repositories.schedules import ScheduleRepository


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description='Run post-race automation')
    result.add_argument('--database', default=os.getenv('DATABASE_PATH', 'data/schedules.db'))
    result.add_argument('--once', action='store_true')
    result.add_argument('--replay-race')
    result.add_argument('--replay-stage', choices=STAGES)
    result.add_argument('--interval', type=int, default=int(os.getenv('POST_RACE_INTERVAL', '300')))
    return result


async def run(args) -> None:
    orchestrator = PostRaceOrchestrator(args.database)
    while True:
        if not args.replay_race:
            ScheduleRepository(args.database).season(datetime.now(timezone.utc).year)
        report = await orchestrator.tick(
            replay_race=args.replay_race, only_stage=args.replay_stage)
        print(json.dumps(report))
        if args.once or args.replay_race:
            return
        await asyncio.sleep(max(args.interval, 30))


def main() -> None:
    args = parser().parse_args()
    if args.replay_stage and not args.replay_race:
        parser().error('--replay-stage requires --replay-race')
    logging.basicConfig(level=logging.INFO, format='%(message)s')
    asyncio.run(run(args))


if __name__ == '__main__':
    main()

