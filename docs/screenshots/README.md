# Screenshot provenance

## Release 1.1

`v1.1/` contains fresh captures from the current Flutter pages, generated on 2026-09-27 by `mobile/test/ui_qa_test.dart`. English and Simplified Chinese images are 390 by 844 logical pixels. They use recorded production payloads in `mobile/test/fixtures/ui_qa/` and `mobile/test/fixtures/evolution/`, rather than current network responses.

The Home next-race envelope selects the captured Singapore race unchanged. Race-specific Evolution responses filter the captured season feed by race ID. No new race facts are authored for screenshots. Capture-time countdowns differ from the payload's historical update timestamp.

| Prefix | Page |
| --- | --- |
| `home` | Home upper section |
| `home-actions` | Detail/reminder rows and updated footer |
| `calendar-upcoming` | Upcoming-first Calendar |
| `briefing` | Source-backed Briefing |
| `evolution` | Evolution with test illustration rendering |
| `detail` | GP Detail and Team Identity |
| `settings` | Settings |

Each has `-en.png` and `-zh-CN.png` variants. The test harness renders page content, without native status/navigation bars or the full app navigation shell. Home has no native reminder service in this harness and shows the platform-unavailable message. Evolution uses `enableGltf: false`; it does not demonstrate the production GPU renderer. These are rendered widgets, not generated artwork or reconstructed mockups.

Reproduce from `mobile/` with `flutter test test/ui_qa_test.dart`. Fonts include project assets and Windows Microsoft YaHei for Chinese. Output goes to `.tools/ui-qa/`; copy selected captures here after inspection.

The signed APK was separately installed and launched on an Android emulator. Online acceptance was blocked by production endpoint timeouts; see [release validation](../release-notes-v1.1.0.md).

## Archived 1.0 images

Root-level `home.jpg`, `races.jpg`, `briefing.jpg` and `explorer.jpg` are supplied 1.0 Android screenshots at 576 by 1280. They remain historical assets and are not used as 1.1 gallery images. `../social-preview-v1.0.0.jpg` is an archived 1.0 composition.

## Signed Android build capture

[Settings on API 35](v1.1/android-settings-en.png) is an unmodified 1080 by 2400 screenshot of the installed, signed 1.1.0 APK, including Android system bars and the app navigation shell. This offline settings capture is separate from the page regression gallery.
