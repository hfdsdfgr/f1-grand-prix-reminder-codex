# UI v2 implementation

The approved reference and original audit remain in [UI_V2_SPEC.md](../UI_V2_SPEC.md).
Status: UI and data-path implementation; photographic and race-specific geometry fidelity remains dependent on reviewed assets. This is not a declaration of pixel-identical completion.

## Delivered

- Shared editorial headers, numbered rows, hairline dividers, underlined tabs, evidence fields, source actions and system sharing. Bundled Newsreader / Barlow / Barlow Condensed fonts include their SIL OFL licenses.
- Home / Calendar / Explore / Settings navigation; Briefing opens from Home Latest. Briefing remains accessible with no upcoming race. Page scroll positions have separate storage keys; system Back closes the Home Briefing view.
- Home uses actual schedule metadata, local session dates/times and a three-column countdown. Latest checks real Briefing and Evolution responses, exposes stale/error states, and can fall back to the previous season when the current season has no completed race.
- Briefing has Key stories / Race result / Quotes / Analysis tabs. Result and Analysis reuse the existing race-detail implementations. Existing Follow ordering, source drawer and session spoiler gate remain in place.
- Quotes requires a `key_quotes` field and validated evidence anchors. The tab displays original evidence excerpts, not an AI summary styled as a quotation. Unavailable authorship is omitted. The detail page opens original sources.
- Evolution supports a race overview across teams, explicit team filtering, numbered upgrade rows, real model-derived component thumbnails and the existing timeline. It defaults to the most recent documented race on first load.
- Explorer is a separate component-detail route with the original change/title, goal, expected effect, lifecycle status, confidence and sources. Missing Purpose/confidence displays Unknown; unsupported component mappings retain their textual evidence.
- The existing GLTF / Canvas viewer remains. Standard / Technical, five view presets, Focus, Exploded/Assemble, labels, wireframe, keyboard controls, rotation, zoom, Heritage and textual comparisons remain reachable. Fullscreen reuses camera state and returns without resetting it.
- Isolated part previews render the existing generic geometry, using dark materials and a thin selection outline. They are explicitly labelled generic illustrations.

## Additive API changes

Existing route names, source publication rules, language selection and cache keys are retained.

| Addition | Contract |
|---|---|
| `Race.total_rounds` | Optional schedule metadata, calculated from the highest published round number. Existing clients ignore it; older servers may omit it. |
| `BriefingInsight.field` | Optional stable field name; existing `topic`, `detail` and `sources` remain. |
| `BriefingInsight.evidence` | List of original `quote` plus its source. An anchor is included only when it matches saved original text after whitespace/case normalization. Existing unsupported summaries are not upgraded into verified quotations. |
| `GET /api/v1/races/{race_id}/media` | Reviewed media associations for the requested race. Returns an empty list when no media catalog is configured. Invalid configured catalogs return 503. |

The UI is compatible with servers without the new fields/routes: photography is omitted and the Quotes tab explains the lack of verified quotations. Deploying the backend additions is required to expose these new records to an installed app. No backend was deployed in this task.

## Media ingestion

Set `EDITORIAL_MEDIA_PATH` to a UTF-8 JSON array on the backend. Each entry follows `backend/app/editorial_media.py:EditorialMedia`:

- `id`, exact `race_id`, and `role` (`home`, `briefing`, `story`). Story media also supplies the existing insight `topic`.
- HTTPS `url` and HTTPS `source_url`.
- Nonempty `credit`, `license`, `caption`, and `reviewed_by`.
- `reviewed: true` only after checking license, identity, event association and the caption.
- `spoiler` defaults to true. Mark false only after reviewing both the image and caption for result disclosure.

No example records are shipped as production data. Media never creates or validates a technical claim. The client uses the reviewed image as a header background or story thumbnail and retains its credit/source. Spoiler-hidden media does not create an image widget or expose its caption.

## Explicit outstanding asset dependencies

1. No licensed race photographs or portraits were supplied. The catalog currently has no configured entries. Pages use their genuine text layout; they do not substitute unrelated photos or screenshot crops.
2. The model remains the existing universal technical illustration. Photorealistic livery, carbon detail, accurate team-specific floor/wing shapes and dated race variants have not been invented.
3. Ghost Compare retains its entry and requirement explanation. The old race branch could offset the same generic mesh and describe it as a previous specification. That branch is now gated until distinct verified geometries are available, matching the approved specification. Textual Specification / Generation comparisons remain available. A reviewed versioned geometry catalog and renderer integration are still required to enable a genuine geometric Ghost Compare.
4. No iOS build or physical-device rendering/performance validation was possible in this Windows task. Font/viewport screenshots and Canvas tests do not establish mobile GPU rendering equivalence.

## Validation

Verified on 2026-09-24:

| Check | Result |
|---|---|
| Flutter analyze | No issues found |
| Full Flutter test suite | 49 passed |
| Final layout/Evolution/fullscreen regression subset | 18 passed |
| Final Home/navigation/localization subset after cross-season handling | 10 passed |
| Backend suite | 77 passed |
| Android debug build (`API_ENV=test`) | Successful; `mobile/build/app/outputs/flutter-apk/app-debug.apk` |
| Diff whitespace check | Passed |

 Existing backend and Flutter tests were run; navigation assertions were updated for the approved menu names/routes, while source, lifecycle, reminder, Follow, localization and spoiler assertions were preserved. New tests cover media review/association, original-evidence validation, quote filtering, hidden media, Unknown fields and camera state across fullscreen.

Layout screenshots under `.tools/f1-preview/` are generated with explicitly test-only fixtures. They are not production evidence or claims about actual races. The Android debug build targets the existing test API configuration, not a production deployment.

Sharing uses the standard [share_plus API](https://pub.dev/packages/share_plus) with real titles and source links; no invented application deep links are emitted.
