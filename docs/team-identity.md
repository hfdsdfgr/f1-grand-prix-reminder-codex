# Team Identity and Home polish

Implemented 2026-09-26. This change keeps the existing Home upper layout, backend contracts, evidence rules and 3D renderer.

## Shared identity

`mobile/lib/shared/team_identity.dart` renders a 3 × 18 logical-pixel vertical color marker, an 8-pixel gap and neutral body-small text. The default standard form shows abbreviation and name; compact shows abbreviation; label shows name. The component adds no interaction, container, logo or image dependency. Readable text and a combined accessibility label supplement the color. Both locales use the same structure and existing name localization.

`mobile/lib/design/team_colors.dart` owns all colors, abbreviations and aliases. Resolution first checks stable IDs, then exact normalized names for older data. Canonical keys match the client catalog: `alpine`, `aston_martin`, `audi`, `cadillac`, `ferrari`, `haas`, `mclaren`, `mercedes`, `racing_bulls`, `redbull`, `williams`. Entries also include the existing API `tea_<uuid>` IDs verified against the captured 2026 roster. A known ID wins over a conflicting display name. Future teams require one mapping entry.

Unknown teams use `UNK` and neutral `#92999F` (146, 153, 159), preserving a supplied display name or using the existing localized Unknown label.

## Color provenance

The user-provided [Formula 1 color directory](https://teamcolorcodes.com/formula-1/) supplies the linked palette values below. Its directory includes historical teams and has no entries for Audi, Cadillac or Racing Bulls at review time. Those three colors are original client accents, not claimed official RGB values.

| Team | UI hex | UI RGB | Source or adjustment |
| --- | --- | --- | --- |
| Alpine | `#2173B8` | 33, 115, 184 | [Blue](https://teamcolorcodes.com/alpine-f1-team-color-codes/) |
| Aston Martin | `#357C73` | 53, 124, 115 | [Source dark green](https://teamcolorcodes.com/aston-martin-f1-team-color-codes/) is `#002420`; lightened for visibility on the app background |
| Audi | `#CE494E` | 206, 73, 78 | Original muted red accent |
| Cadillac | `#BFC3C7` | 191, 195, 199 | Original silver accent |
| Ferrari | `#EF1A2D` | 239, 26, 45 | [Red](https://teamcolorcodes.com/scuderia-ferrari-color-codes/) |
| Haas | `#E6002B` | 230, 0, 43 | [Red](https://teamcolorcodes.com/haas-f1-color-codes/) |
| McLaren | `#FF8000` | 255, 128, 0 | [Orange](https://teamcolorcodes.com/mclaren-color-codes/) |
| Mercedes | `#00A19B` | 0, 161, 155 | [Tiffany green](https://teamcolorcodes.com/mercedes-amg-petronas-f1-team-color-codes/) |
| Racing Bulls | `#798FD0` | 121, 143, 208 | Original muted blue accent |
| Red Bull | `#FDD900` | 253, 217, 0 | [Yellow from the published palette](https://teamcolorcodes.com/red-bull-racing-color-codes/), chosen for a distinct small marker |
| Williams | `#00A0DE` | 0, 160, 222 | [Blue](https://teamcolorcodes.com/williams-racing-color-codes/) |

Ferrari and Haas retain similar source reds; text remains the primary identifier.

## Page integration

- Results: compact identity beside existing driver information, preserving rank hierarchy.
- GP Detail: standard identity in result rows.
- Evolution: label identity in team selectors; standard identity in component detail metadata. The 3D renderer and its controls are unchanged.
- Briefing: the shared Results tab receives the identity. Key Stories, Quotes and Analysis facts have no structured team ID in their current insight model, so these retain their evidence-backed text without inferred team associations.
- Follow: standard identity in followed-team settings and label identity in followed-driver context.
- Calendar: unchanged to preserve its compact information density.

## Home lower section

View details is a full-width, containerless action row. Race reminders is a setting-style row opening the existing reminder sheet. It shows saved session/lead-time configuration and permission state; an automatic preference alone does not count as enabled. Permission checks run when returning to the app or closing the sheet and do not request permission or schedule notifications. Unexpected permission-query failures display an unknown status.

The scheduled-race counter and raw API URL are removed from Home. Source information remains in detail views. Updated time and refresh share one row. Other pages retain their existing feed footer through an opt-in Home footer layout.

## Verification

- `flutter analyze --no-pub`: no issues found.
- `flutter test --no-pub --reporter expanded`: all 74 tests passed.
- `team_identity_test.dart`: all 11 captured API IDs, ID precedence, exact-name compatibility, unknown fallback, all three variants, both locales, narrow width and enlarged text, semantics and absence of new interactions.
- `home_polish_test.dart`: saved reminder configuration, notification and exact-alarm permission changes, unscheduled automatic preference, Home entry navigation and removal of old controls/source text.
- Existing real-payload UI QA tests pass in English and Chinese, including enlarged text. This is Flutter widget/render validation, not a new physical-device or GPU validation run.
- `git diff --check`: passed.

No backend schema, network image, asset package or business feature was added.
