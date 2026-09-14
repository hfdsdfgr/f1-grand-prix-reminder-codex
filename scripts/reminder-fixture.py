"""Local emulator-only schedule. Never used by the production backend.

Default one-hour reminders fire 180 and 240 seconds after the first request.
Run this on port 8001 and build with API_BASE_URL=http://10.0.2.2:8001.
"""
import json
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

epoch = None


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global epoch
        epoch = epoch or datetime.now(timezone.utc)
        races = []
        for index, seconds in enumerate((180, 240), start=1):
            start = epoch + timedelta(hours=1, seconds=seconds)
            races.append({
                'id': f'{epoch.year}-{index}', 'name': f'Emulator test race {index}',
                'circuit': 'Synthetic test schedule', 'date': start.date().isoformat(),
                'source': 'http://127.0.0.1:8001', 'starts_at': start.isoformat(),
                'sessions': [{'kind': 'Race', 'starts_at': start.isoformat()}],
            })
        parsed = urlparse(self.path)
        if parsed.path == '/api/v1/next-race':
            payload = {'race': races[0]}
        elif parsed.path == '/api/v1/races':
            season = parse_qs(parsed.query).get('season', [str(epoch.year)])[0]
            payload = {'races': races if season == str(epoch.year) else []}
        else:
            self.send_error(404)
            return
        payload.update(updated_at=epoch.isoformat(), stale=False)
        data = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8001), Handler).serve_forever()
