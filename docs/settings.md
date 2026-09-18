# Settings implementation

This milestone implements the Settings groups against the features currently present in Midoku. It does not mark the full product plan or Phase 8 exit criteria complete: personal-library composition and its database are still separate work.

## Screens and behavior

- Appearance: system/light/dark, forest/slate/ochre accents, compact/comfortable cover grids, and a next-launch tab. Native grouped rows use the approved adaptive palette, semantic typography, and accessible controls.
- Home: pin a source feed or search with its exact filters; show, hide, rename, reorder, and delete sections. A visible pin action complements the context menu. Home loads independent shelves with a disposable 15-minute cache; failures retain previous content. View All reopens the saved parameters.
- Library: persistent category creation, rename, reordering, and deletion with normalized name validation. Sort and launch-refresh defaults are stored and explicitly labelled as applying to the future personal library. Chapter thumbnail visibility applies immediately to source chapter lists; no chapter-page crawling is used for thumbnails.
- Reader: global RTL/LTR/continuous modes, direction-aware tap zones, fitting, background, orientation requests through public UIKit APIs, screen wake behavior, and optional brightness restored on exit/background. Source and offline readers save positions by immutable source identity. Center taps toggle online controls; page zoom has gestures and a visible menu. Continuous pages release off-screen images while retaining their aspect ratio.
- Privacy: LocalAuthentication with device-passcode fallback, enrollment checks, immediate/one-minute/five-minute lock delay, a separate opaque privacy window that also masks presented sheets, History recording toggle and clear. A cancelled authentication stays locked. Lock enrollment is written durably before its UI setting changes.
- Extensions: inspect bundled package versions, contracts, capabilities, and domains; add, enable/disable, rename, remove, and restore source connections; clear a connection's website session separately. Removing a connection archives its UUID instead of deleting dependent state. Bundled executable files stay part of the app.
- Downloads/storage: foreground queue, Wi-Fi-only policy, pause/resume/cancel/retry, per-chapter and bulk deletion, offline access, actual disk totals, memory-cache limit, and isolated cache clearing. Use the visible chapter action menu to download. Only one chapter runs at once; metadata and reader images take priority over waiting download pages. Verification-required jobs fail recoverably and ask the user to open the source.
- Backup: export to Files, bounded import validation, record-count/missing-source preview, merge or replace, and a recovery copy before either operation. Recovery files can be reviewed and restored from Settings.
- About: actual app version/build, credits, project/support link, and a previewable diagnostic export containing versions/counts only. No automatic upload or private reading titles, queries, URLs, cookies, or connection UUIDs.

## Persistence and migration

`Settings/Core/AppSettingsStore.swift` owns an observable main-actor snapshot; disk writes run in a serial actor and reject stale revisions. The v1 snapshot is atomically replaced at Application Support/Midoku/app-settings.json. Migration reads the existing source-connections.json once and preserves its UUIDs; the legacy file remains intact. An invalid or future store never triggers a reset.

A settings write failure keeps the in-memory change visible with an explicit retry message. App-lock changes and restores instead publish their new state only after their atomic write succeeds. Restore blocks competing edits, keeps current device-lock preferences, and changes a generation token so departing reader views cannot write old progress into the replacement snapshot.

The JSON snapshot is a small local foundation, not a replacement for the plan's GRDB personal-library schema. A later database migration must retain connection/category/Home/source chapter identities and move these records transactionally. No library entries, variants, exclusions, clipboard, or custom cover files are invented by this change.

## Backup format

The `.midoku` JSON envelope identifies `dev.midoku.settings-backup`, format version 1, export date, app version, bundled extension inventory, counts, payload byte size, and SHA-256. Its typed payload contains nonsecret preferences, connections, categories, Home descriptors, History (max 100), and physical reading positions. Files are limited to 32 MiB and decoded/validated before any live mutation. UUID duplication, dangling source references, incompatible versions, count/hash mismatches, and source UUID/extension conflicts are rejected.

This is a data-only envelope with no arbitrary filesystem paths, executable payloads, credentials, or archive extraction. Hashes detect corruption; they are not publisher signatures or encryption. There are no custom assets in the current app to include. A later full-library backup needs a new format and asset manifests rather than silently dropping library fields from this format.

Merge keeps existing preferences, category names/order, Home edits/order, and reading positions for conflicting identities; imported missing records are appended. Equal normalized category names and exact duplicate Home queries are deduplicated. History keeps the latest visit per physical source chapter and retains the newest 100 with a stable tie-break. Replace stages a complete validated snapshot and first writes a recovery export; failed recovery creation or snapshot write preserves the old snapshot. Offline files remain independent, and any local source identities they require remain archived. New imported source connections never inherit leftover WebKit sessions. Lock settings remain those of the current device.

## Download and storage boundaries

- App data and recovery exports: Application Support/Midoku, excluding the Downloads subdirectory for usage totals.
- Permanent offline pages, manifests, queue inventory, and per-job staging: Application Support/Midoku/Downloads.
- Disposable Home-feed cache: Caches/Midoku/Feeds. The existing image cache remains bounded to 64 MiB in memory.
- Website sessions: separate connection-specific WebKit profiles. Cache clearing does not sign out.

Downloads have a versioned atomic inventory and UUID-derived local directories/ordinal filenames. Native response limits remain 8 MiB for metadata and 32 MiB for image/download responses, with at most 5,000 pages/1 GiB per chapter. Each page is image-validated before saving and recorded with byte count/SHA-256. A chapter becomes completed only after all expected pages pass validation and its staging directory is promoted. Startup reconciles interrupted work and verifies saved files; offline reads validate again. This is foreground execution, not a claim of continuous background downloads. Explicit retry restarts an incomplete chapter; failed jobs do not retry indefinitely. Offline files are excluded from settings exports and cache clearing.

## Explicit remaining dependencies

- Personal-library sort/refresh application, category assignment, per-entry reader overrides, complete mixed-source progress/completion semantics, and full-library/custom-asset backup await the personal-library milestone. Their absence is described in the relevant screen.
- Remote extension installation/update/authentication schemas are still outside the reviewed bundled-only runtime. Settings explains bundled updates and only exposes capabilities that currently exist.
- Downloads currently target individual source chapters. Library multi-select download scheduling, automatic retry/backoff, rendition changes/redownload replacement, and more advanced background scheduling remain download-product work.
- The current continuous reader resumes a page/relative anchor; long-image behavior, rotation changes, system gesture interaction, and zoom need the device checks below. This change does not claim a complete reader acceptance pass.

## Verification and handoff

`Extensions`: `npm ci` and `npm test` passed TypeScript typechecking, bundling, and all 16 Node tests. Generated bundle path-comment changes were reverted because the adapter sources are unchanged.

All 46 app/test Swift files passed Swift 6.2 parser checks. All 10 new settings/storage tests passed in an isolated Linux harness using the same source files and test file; the harness substituted Apple's Swift Crypto module for CryptoKit, provided the two Apple-only Foundation URL conveniences, and omitted Observation observation hooks for Linux linking. These checks cover state/persistence behavior, not SwiftUI or LocalAuthentication. The app source continues to use native CryptoKit and Observation, with no new runtime package dependency.

Run the complete `swift test` suite on the supported Mac toolchain and build Midoku.xcodeproj in Xcode 27 before merging. This environment cannot compile SwiftUI/WebKit/JavaScriptCore or run an iOS simulator. Required device checks: light/dark and accessibility sizes; all settings routes; source pin filters/back navigation; source/continuous/offline reader mode and zoom; restore preview/recovery and relaunch; lock cancellation/passcode fallback/delay while a sheet is open; Wi-Fi changes, pause/cancel/relaunch, disk failure, corrupt page recovery, cache clear followed by airplane-mode reading. Preserve the existing signing and deployment settings.
