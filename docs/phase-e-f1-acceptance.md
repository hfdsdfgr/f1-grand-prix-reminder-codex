# Phase E / F1 acceptance

## PHASE E COMPLETE

Accepted on 2026-09-22. The user completed physical Android acceptance and
confirmed the reported viewer issues were fixed. Baseline: `3e23732`.
Final local regression: Flutter 34/34; Backend 54/54. ECS test Debug APK
was successfully built at that baseline.

## Phase F1 audit and direction

Existing pages already use mostly flat lists, not cards. Retain that structure.
Differences to resolve: system-dependent light appearance, incomplete type scale,
default pill buttons/chips, outlined Calendar selector versus underline selectors,
repeated page padding, inconsistent section headings and asynchronous states,
source URLs competing with briefing content, and follow context above Home timing.

Use near-black background, charcoal surfaces, white text, muted metadata and warm
red accent. Align titles, paragraphs and section dividers to the same gutter.
Keep native system typography (including existing Chinese fallback), with tabular
race timing. Keep all data contracts, translations, viewer code and behavior frozen.

## PHASE F1 COMPLETE

Completed on 2026-09-22.

- Theme: background #0C0D0F, charcoal #17191D, white #F3F4F5,
  secondary #A6ABB4, accent #FF6578, divider #30343B. Dark is the app default.
- Type: 38px page title, 30px timing, 23px sections, 20px item headings,
  16px body, 13px metadata; native font fallback and tabular timing preserved.
- Layout: shared 24px page gutters, 760px maximum reading width, 8/16/24/32px
  spacing tokens, 6px control radius, 48px button targets, thin dividers.
- Components: SectionHeading, ContentState, SourceReference. Existing section,
  loading/error/empty/cached and source presentations now share these treatments.
- Pages: Home, Calendar, GP detail/results, Briefing, Evolution surroundings,
  Settings and reminder sheet. Follow/Spoiler-Free keep their behavior and use
  the shared theme. Native navigation architecture and page transitions retained.
- Removed repeated title/retry/loading/source layouts and Calendar's separate
  outlined selector. Home follow context follows primary timing/reminder content.
- Layout checks: 390px, 320px at 1.6x font, 812px landscape at 1.6x font;
  existing navigation tests also cover 320/375/812/1024px at 2x font.
- Fixed reminder preset selector overflow with isExpanded; scheduling unchanged.
- flutter analyze: no issues. flutter test: 38/38. Backend baseline: 54/54.
- Debug APK built successfully with --dart-define=API_ENV=test; Gradle 12.1s.
  Artifact: mobile/build/app/outputs/flutter-apk/app-debug.apk (207653175 bytes).
- No changes to Backend, repositories/models, localization, or 3D Viewer files.

Limits: F1 visual checks used local Flutter-rendered test fixtures, not a new
physical-device session. Current Briefing contract is topic/detail with sources;
independent driver/team identity blocks await a future authorized contract change.
No facts or identities were inferred for presentation. Team logo work remains
deferred. Rollback baseline: 3e23732. Stop after F1.
