# GrandPrixReminder 1.1

Prepared 2026-09-27. Android version name `1.1.0`, version code `2`.

## Changes

- Editorial typography and dividers; compact Calendar with upcoming-first and completed-first ordering.
- Evolution expansion-state restoration fix and consistent English/Chinese presentation.
- Containerless Home detail action, actual reminder configuration and permission status, and a single updated/refresh footer row.
- Shared Team Identity: a 3 × 18 pixel color marker with neutral abbreviation/name text. All 11 teams use one mapping with stable API IDs and an unknown fallback.
- Existing reminders, Spoiler-Free, Follow, evidence tracing, Evolution lifecycle and 3D controls remain available.

## Artifacts

Local signed build outputs:

- `mobile/build/release-candidate/GrandPrixReminder-v1.1.0.apk` — 66,925,600 bytes.
- `mobile/build/release-candidate/GrandPrixReminder-v1.1.0.aab` — 64,577,513 bytes.

APK SHA-256:
`667a5a42a68fb35a6d18c4b73400caa98d59d719d9f8a3e69cefcca48024d37d`

AAB SHA-256:
`a67853492d199d848224981635d30f623bab09ed8e928735f2b907aeeb36fdd5`

The existing release key is retained. `apksigner verify --print-certs` succeeded; certificate SHA-256:
`53f3f5f576497c987623064ba0c24a5b0baa6d7dd6b3eb1225d9bd3904fa266a`.

These artifacts are built locally; this record does not claim a GitHub Release has been published. APK/AAB files and signing secrets are excluded from Git.

## Verification and limits

- `flutter analyze --no-pub`: no issues found.
- `flutter test --no-pub --reporter expanded`: all 74 tests passed, including current Home captures and both locales.
- Signed APK installed and launched on the API 35 Android emulator. Package manager reports `versionName=1.1.0`, `versionCode=2`.
- Production `http://8.134.70.237/api/v1/next-race` timed out from the build machine, including a direct no-proxy retry. The emulator showed a network failure state. This is not a successful online content or physical-device acceptance run.
- Build used `./scripts/build-release.ps1 -SkipApiCheck` to explicitly skip the unavailable endpoint health check. The compiled production environment and API address are unchanged. The script checks availability by default.
- README images are fresh Flutter page captures using previously recorded API payloads, identified as regression captures. GPU 3D and native notification behavior are not represented by those images.
- No backend changes were made in this round; backend tests were not rerun for packaging.

## Installation

Open the APK on Android. A release with the same package name and signing key supports an in-place update. Debug builds use a different key; uninstalling removes local preferences and reminders.

Before broad distribution, recheck production connectivity and real-device reminder/3D behavior. Existing HTTP transport, evidence uncertainty and illustration-only 3D limitations remain documented in README.

See [Team Identity](team-identity.md), [UI QA](ui-qa-polish.md) and [screenshot provenance](screenshots/README.md).
