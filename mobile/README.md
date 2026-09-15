# GrandPrixReminder mobile

Flutter app. Setup and verification commands are in the repository README.
The app calls only the configured API_BASE_URL, never third-party F1 APIs directly.

## API environments

- `development` is the default and uses the local Backend at `http://127.0.0.1:8000`.
- `test` uses the ECS Nginx endpoint at `http://8.134.70.237`.
- `API_BASE_URL` can override either environment for a one-off local test.

Examples:

```powershell
# Local Backend (default)
..\.tools\flutter\bin\flutter.bat run

# Android device / ECS test Backend
..\.tools\flutter\bin\flutter.bat run --dart-define=API_ENV=test

# Debug APK for the ECS test Backend
..\scripts\build-android.ps1
```

The HTTP exception is debug-only while the test Backend has no domain or TLS.
Use an HTTPS domain before any release/profile distribution.
