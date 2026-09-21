import argparse
import json
import os

from app.evolution_worker.persistence import review


def main() -> None:
    parser = argparse.ArgumentParser(description='Review pending Evolution events')
    parser.add_argument('action', choices=('list', 'publish', 'reject'))
    parser.add_argument('event_id', nargs='?')
    parser.add_argument('--database', default=os.getenv('DATABASE_PATH', 'data/schedules.db'))
    args = parser.parse_args()
    print(json.dumps(review(args.database, args.action, args.event_id), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
