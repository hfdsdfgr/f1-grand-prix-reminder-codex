"""Report and verify the non-destructive Phase C identity migration."""
import argparse
import json
import os
import sqlite3

from app.data_schema import migrate


TABLES = (
    'evolution_source_documents', 'evolution_source_revisions', 'evidence_anchors',
    'evolution_claims', 'claim_evidence', 'claim_observations', 'upgrade_claims',
    'upgrade_lifecycle_events', 'review_items',
)


def report(path: str) -> dict:
    with sqlite3.connect(path) as db:
        existing = {row[0] for row in db.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        result = {'schema': 'identity-v11' if 'evolution_source_revisions' in existing else 'legacy'}
        result['counts'] = {
            table: db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
            for table in TABLES if table in existing
        }
        if 'upgrades' in existing:
            upgrade_columns = {row[1] for row in db.execute('PRAGMA table_info(upgrades)')}
            status = "review_status" if 'review_status' in upgrade_columns else "'legacy'"
            where = "WHERE review_status='published'" if status == 'review_status' else ''
            result['published_upgrades'] = [dict(zip(
                ('upgrade_id', 'component_id', 'change', 'review_status'), row
            )) for row in db.execute(f'''SELECT upgrade_id,component_type_id,change_description,{status}
                FROM upgrades {where}
                ORDER BY upgrade_id''')]
        if 'evolution_source_documents' in existing:
            result['source_columns'] = [row[1] for row in db.execute(
                'PRAGMA table_info(evolution_source_documents)')]
        return result


def main() -> None:
    parser = argparse.ArgumentParser(description='Phase C identity migration')
    parser.add_argument('action', choices=('report', 'migrate', 'verify'))
    parser.add_argument('--database', default=os.getenv('DATABASE_PATH', 'data/schedules.db'))
    args = parser.parse_args()
    before = report(args.database)
    if args.action == 'migrate':
        migrate(args.database)
    after = report(args.database)
    print(json.dumps({'before': before, 'after': after}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
