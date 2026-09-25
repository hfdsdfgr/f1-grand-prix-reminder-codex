# Public API snapshots for UI QA

Captured on 2026-09-25 from the app's configured API, `http://8.134.70.237`.
These are unmodified HTTP response bodies, used only by tests. Production UI
continues to request the API through `RaceRepository`.

## Evolution

Each endpoint was requested with both `lang=en` and `lang=zh-CN`.

| File prefix | Endpoint | Response |
| --- | --- | --- |
| `evolution/2026-` | `/api/v1/evolution?season=2026` | 200; 42 upgrades |
| `evolution/2025-` | `/api/v1/evolution?season=2025` | 200; empty upgrades and timeline |
| `evolution/2026-1-` | `/api/v1/evolution/2026-1` | 200; one historical Australian GP upgrade |
| `evolution/2026-22-` | `/api/v1/evolution/2026-22` | 200; no documented upgrades |

The backend contract tests validate these same files against `EvolutionFeed`
and `EvolutionRaceDetail`. Flutter tests replay the raw UTF-8 responses, including
source links, translated evidence, numeric-string confidence and null fields.

## Other pages

`ui_qa/races-en.json` captures `/api/v1/races?season=2026&summaries=true`;
`seasons-en.json` captures `/api/v1/seasons`. Both returned 200.

The other files capture `/api/v1/races/2026-14/{filename-prefix}`:

- `results`, `story`, `championship-impact`: 200.
- `briefing`: 200 for both locales.
- `strategy`: 503, with the original temporary-unavailability response.
- `media`: 404, with the original not-found response.

The test client preserves the failure status codes. Schedule and results fields
are localized by the app; translated editorial content uses its matching locale
snapshot. Fixtures deliberately retain upstream race names and dates as returned.
