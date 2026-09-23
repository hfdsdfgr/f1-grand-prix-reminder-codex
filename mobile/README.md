# GrandPrixReminder mobile

Flutter app. Setup and verification commands are in the repository README.
The app calls only the configured API_BASE_URL, never third-party F1 APIs directly.

## API environments

- `development` is the default and uses the local Backend at `http://127.0.0.1:8000`.
- `test` uses the ECS Nginx endpoint at `http://8.134.70.237`.
- `production` currently defaults to the ECS Nginx endpoint at `http://8.134.70.237`.
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

The v1.0 release permits cleartext HTTP only to `8.134.70.237` through a
release-specific Android network security configuration. Other release HTTP
destinations remain blocked. The backend currently uses HTTP over a public IP;
HTTPS/domain deployment is deferred to the post-v1.0 deployment backlog.
Evolution technical claims still require human review before publication.

## Android release

From the repository root, run `scripts/init-release-signing.ps1` once. Back up
`mobile/android/app/grandprix-upload.jks` and `mobile/android/key.properties`
securely; both are ignored by Git and are needed to sign future updates.
For the current ECS endpoint, run:

```powershell
.\scripts\build-release.ps1
```

The script builds a signed release APK and AAB with `API_ENV=production`.
When HTTPS is available, pass `-ProductionApiUrl https://your-domain.example`
and remove the release-only HTTP exception after verification.
