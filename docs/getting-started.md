# Developer guide

The repository contains a FastAPI Backend (`backend/`) and a Flutter Android client (`mobile/`). Commands below use Windows PowerShell from the repository root. Python, Flutter and an Android SDK are required for local development.

## Run the Backend

```powershell
py -3 -m venv backend/.venv
.\backend\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
cd backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Use a second terminal for the client. The default `development` environment points to `http://127.0.0.1:8000`. For the Android emulator, pass `--dart-define=API_BASE_URL=http://10.0.2.2:8000`.

## Run the Flutter client

```powershell
cd mobile
../.tools/flutter/bin/flutter.bat pub get
../.tools/flutter/bin/flutter.bat run
```

The ignored `.tools/flutter` path is the local SDK used by this project; a Flutter installation on `PATH` works too. For the current ECS test API, use `--dart-define=API_ENV=test`. Release builds use `API_ENV=production`; see [mobile/README.md](../mobile/README.md) for signing, environment and Android HTTP configuration.

## Verify

```powershell
cd backend
.\.venv\Scripts\python.exe -m unittest discover -s tests -q
cd ../mobile
../.tools/flutter/bin/flutter.bat analyze
../.tools/flutter/bin/flutter.bat test
```

From the repository root, `.\scripts\build-release.ps1` builds signed APK and AAB artifacts when the local signing configuration is present. The signing files and passwords stay outside Git.

## API routes

The current read API is implemented in [`backend/app/main.py`](../backend/app/main.py). Representative routes:

| Data | Route |
| --- | --- |
| Next race | `GET /api/v1/next-race` |
| Calendar | `GET /api/v1/races?season=2026` |
| Race detail | `GET /api/v1/races/{race_id}` |
| Results | `GET /api/v1/races/{race_id}/results` |
| Briefing | `GET /api/v1/races/{race_id}/briefing?lang=en` |
| Evolution detail | `GET /api/v1/evolution/{race_id}?lang=en` |
| Season Evolution | `GET /api/v1/evolution?season=2026&lang=en` |
| Health | `GET /health` |

The race ID format is `season-round`, for example `2026-14`. Briefing and Evolution also accept `lang=zh-CN`. Presentation falls back to English or canonical text when a translation is unavailable; source evidence and entity IDs remain unchanged.

## Deployment boundary

The current production client uses the ECS Nginx endpoint on port 80. Nginx forwards `/api/*` to FastAPI bound to `127.0.0.1:8000`. The DeepSeek API key is provided to the server through a systemd EnvironmentFile; it is not part of the client or repository. The current public-IP HTTP transport is unencrypted, with HTTPS and a domain deferred beyond v1.0.
