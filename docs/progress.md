# Home design, library paging and cover fixes — 2026-09-19

- Replaced the system floating tab bar with a solid full-width five-tab bar. Each tab retains navigation state; reader routes hide the bar.
- All five main screens use large leading titles with the native clear space above them. Detail screens keep compact navigation titles.
- Home uses the design's Continue Reading card with entry cover, chapter name, physical page progress, and a resume action.
- Library categories support taps and horizontal paging. Settings > Library offers Standard, Compact, and Custom layouts, including portrait/landscape item counts. Existing density preferences migrate without resetting other settings; custom values survive backup/restore.
- Bootstrap awaits the local extension registry before publishing screens. Concurrent adapter callers await the same initialization task; Home also observes readiness and supports retry after load failure.
- Entry covers and individual chapter covers have explicit, separate write targets. Chapter lists use a custom chapter cover or a cached first-page thumbnail, never the entry cover. Visible rows resolve thumbnails through the shared source coordinator in background mode; they cannot trigger verification sheets. Offline first pages are supported. The disposable cache retains up to 300 bounded thumbnails and is excluded from backups; custom covers remain backed up.
- Added a clear Rename chapter action for the bold chapter label, also exposed in Edit chapter. Source refresh does not overwrite that override.
- Added regression tests for independent cover ownership across persistence/refresh, stale cover targets, old preference migration, and custom row-count backup validation. Extension typechecking, bundling, and 21 Node tests pass locally. The first Xcode 27 run passed all 55 Swift tests and archived the unsigned Release IPA. Simulator review caught a cover sizing issue; grid cells now have explicit widths and a 2:3 image frame, and the native tab container handles tab lifecycle behind the custom bar. The final workflow verifies those corrections and the larger main titles, with screenshots of all five tabs and the layout/rename screens.
- No signing/deployment settings changed. Physical-device and LiveContainer behavior must be checked with the delivered IPA.

---

# Development progress

## 2026-09-18 (UTC) — Personal library, chapter curation and compact headers

Implemented source-backed and empty library entries, persistent chapter clipboard,
explicit paste conflict review, local entry/chapter edits and custom covers,
alternatives, manual order, exclusions, categories, bulk actions and refresh. The
reader follows an entry's canonical order across sources and keeps release-specific
positions/completion; Home and History use that context. All tab roots use compact
inline titles with toolbar actions beside them; the extra Settings intro row is removed.

SQLite transactions migrate the previous settings JSON without deleting it. Full
library backup v2 includes covers and composition while retaining v1 import support.
See [library behavior and limits](library.md) for the implementation and remaining work.
[Native build 35394737018](https://github.com/Mohammad-Rahat/Midoku/actions/runs/35394737018)
passed 45 Swift tests in ten suites and archived the Release IPA with Xcode 27.0
(27A266a). Typechecking, bundling and all 16 Node tests also passed. Debug simulator
screenshots of Library, mixed-source Entry and Settings were inspected: compact
headers, adjacent actions, category/search controls and chapter rows render correctly.
No automated touch-flow or physical-device/LiveContainer installation test was run.

Delivered unsigned IPA from commit `4c9c36dc3cc36a5fedd4853079eeb496f664a158`,
4,161,072 bytes, SHA-256
`e8df51409a1fe423cc95f340333f94c43d131ad84fb2fb97145e1ad935543606`.
Deployment remains iOS 27; existing signing settings are unchanged. Native warnings
remain in the pre-existing extension-registry default initializer and UIScreen.main
usage; there are no archive errors.


## 2026-09-18 (UTC) — Direct main delivery and IPA build

At the user's request, the settings implementation was fast-forwarded directly
onto `main`; GitHub closed the draft pull request automatically. Added an Xcode 27
Actions workflow that runs the complete Swift suite, archives a Release device
build, and uploads an unsigned IPA with its source commit and SHA-256 checksum.
The workflow preserves signing/deployment settings and needs no signing secrets.

The first native archive found a missing UniformTypeIdentifiers import in the
diagnostics exporter. Fixed it and made the settings identifier witness explicitly
nonisolated. [The next run](https://github.com/Mohammad-Rahat/Midoku/actions/runs/35388694209)
passed all 34 Swift tests in nine suites and archived/package-validated successfully.
The archive also exposed an existing launch configuration warning: Info.plist now
references the bundled `LaunchScreen` storyboard. Physical-device behavior and
visual acceptance remain unverified; this IPA requires signing before installation.
See [IPA builds](ipa-build.md) and [settings verification](settings.md).

## 2026-09-18 (UTC) — Settings and connected management features

Implemented all nine Settings routes with native grouped styling, adaptive accents,
Dynamic Type, and persistent typed preferences. Appearance/launch tab/grid density,
reader controls, Home section management, categories, app lock/History controls,
bundled extension management, storage/foreground downloads, backup/recovery, and
About/diagnostic export are connected to local services. See [settings.md](settings.md)
for behavior, migration, backup format, and limits.

Source UUIDs migrate from the existing connection inventory into one atomic settings
snapshot. Backups validate before mutation, preserve device-lock enrollment, reject
identity collisions, create recovery copies, and retain independent offline files.
History clearing does not clear progress. Cache clearing only removes disposable
cache, not downloads, sessions, recovery files, or user data. Source removal retains
archived identities and references. Queued image downloads use the existing request
coordinator with lower priority than reader images and metadata.

Verification: extension typechecking/bundling and 16 Node tests pass; all Swift files
pass syntax parsing. All 10 portable Swift state tests pass, covering round-trip/tamper rejection,
local-wins merge, reference/duplicate validation, UUID migration, stale writes,
History retention, lock state transitions, download validation/promotion recovery,
and recovery-before-replace. Native app builds, the full JavaScriptCore Swift suite,
simulator visuals, LocalAuthentication, privacy snapshots, and real-device downloads
have not been verified here. No signing or deployment settings were changed.

This is not completion of the product plan's Phase 8 acceptance criterion. The
personal-library database/composition, category assignment, library refresh,
per-entry reader overrides, custom assets/full-library archives, and signed remote
extension updates still depend on their earlier planned features. The settings UI
states these limits instead of presenting unsupported actions as working features.


## 2026-09-19 — Source browsing, filters, entries, and direct reading

### Implemented

- MangaDex 0.2.0 uses contract 2. The host retains contract-1 compatibility and
  persistent connection/content IDs. The SDK, scaffold, manifest validation,
  generated bundle and extension author guide describe the new contract.
- Source-defined Latest updates, Popular, Recently added, and Search tabs; visible
  search input; cancellable 300 ms debounce and immediate submission; real cover
  grids; empty/error/retry states; pull refresh and cursor pagination.
- Source-defined filter sheets with Apply, Cancel and Reset. MangaDex supports
  sorting, chapter language, publication status, demographic, original language,
  content rating and included/excluded tags with all/any matching. Feed ordering
  remains owned by its feed. Filter options come from the adapter, never source
  names in SwiftUI; live tag IDs come from the MangaDex API.
- Entry navigation with normalized title/description/cover, authors/artists,
  status/year, tags, source link, labelled chapter-language choices, scanlation
  credits and paginated chapters. The selected browse language carries into the
  entry. Existing query/results/chapter language/scroll survive detail back navigation.
- Direct source chapter reading: real page images, Previous/Next, page picker,
  pinch zoom and visible zoom alternatives, loading/error/retry states and credits.
- Shared connection-scoped image loading, ImageIO downsampling off the main actor,
  and a 64 MiB memory cache. Image requests use the existing permission/session/
  verification coordinator and retain page Referer headers.
- Bounded URLSession delegate chunks replace byte-by-byte body collection; 8 MiB
  metadata / 32 MiB native image limits and cancellation cleanup. Pending metadata
  takes priority over queued images. Existing request spacing and verification
  limits remain in force.
- A shared observable page store prevents old searches or old pagination from
  replacing a new selection, deduplicates moving feeds, detects cursor loops,
  retains failed-refresh content and releases loading state on cancellation.

### Verified

- `npm ci` followed by `npm test` passes: TypeScript typechecking, bundling and
  16 Node tests, including filter defaults/IDs, parameter encoding, feed ordering,
  pagination, metadata/credits, selected-language chapters and page resolution.
- 24 Swift Testing checks in seven suites pass. New checks cover stale search and
  pagination races, cursor loops, deduplication, retry/cancellation state, bounded
  chunk transport and cancellation before any server response. Native integration
  exercises all seven adapter methods through the checked-in JavaScriptCore bundle.
- Xcode BuildProject succeeds without build errors. The existing registry warning
  about the JavaScript runtime initializer's default actor isolation remains;
  the bootstrap constant is explicitly nonisolated. No deployment/signing changes.
- iPhone 16 Pro Max simulator: all three feeds render distinct live results;
  rapid Yotsuba search opens the exact Yotsuba&! entry, with real metadata/covers.
  Filter Cancel preserves prior values, Apply changes results, and Reset restores
  defaults. English Chapter 1 opens actual page 1 and Next loads distinct page 2
  with the counter advancing to 2/48. Initial images took roughly 6–9 seconds on
  this simulator/network; this is not a physical-device performance benchmark.
- Source and entry back navigation retain query, results, language and scroll.
  Refresh completes in both Latest updates and Search. Device testing caught and
  fixed a hidden search field, oversized cover layout, cancellation leaving a
  stale refresh notice, low-contrast reader loaders, and deep-scroll grid handling.
- Final simulator pass confirms deep-scroll feed switching returns to the first
  row without a blank grid, and Load more keeps existing card positions while
  appending results. No remaining observed layout defects or crashes. The device
  session was closed with the original Xcode destination retained.
- The Node live smoke script now includes filter definitions; it was not rerun in
  this milestone because the native simulator exercised live API and image paths.

### Remaining scope

This completes the requested source browse/search/filter/entry path, with basic
direct chapter reading. Personal-library creation/composition, persistent reading
progress/history, downloads/offline reading, additional reader modes, account sync,
and saving filter choices across launches remain product work. Comix is not
implemented. Physical-device protected-source verification and real Cloudflare
challenge/session continuity remain unverified; successful MangaDex reading is
not a claim of universal clearance.

## 2026-09-18 — Bundled MangaDex testing adapter

### Implemented

- `Extensions/sources/dev.midoku.mangadex/`: contract-1 TypeScript adapter for search,
  latest/popular/recent feeds, details, paginated chapters, and ordered original-quality
  image descriptors. English, safe/suggestive defaults; no login or settings API.
- Stable MangaDex UUIDs, exact chapter number strings, source-page ordinals, validated
  cursors and payloads, and filtering of external/unavailable/empty chapters.
- Reviewed `*.domain` permissions for API-assigned MangaDex CDN hosts. Exact domains
  still match exactly; wildcard matching requires a label boundary and does not
  permit the root, lookalike hosts, arbitrary ports, or local addresses.
- `Extensions/bundled.json` selects adapters for app inclusion. The build generates
  `BundledExtensionResources.swift`; native registration decodes and validates the
  embedded manifest/bundle without source-specific UI code. Unselected sources are
  not activated. Node dependencies and `dist/` remain ignored.
- Synthetic shared parser fixtures, Node checks, native JavaScriptCore integration
  checks, a manual opt-in live API/image smoke script, and updated authoring/source
  documentation. Aidoku's MangaDex source was consulted at a pinned revision;
  this adapter is a separate Midoku TypeScript implementation.

### Verified

- `npm ci` and `npm test`: typechecking, bundling, and all 12 Node checks pass.
- 17 Swift Testing checks pass, including all six MangaDex methods through the same
  generated bundle used by the app, resource consistency, and permission boundaries.
- Xcode BuildProject succeeds. Existing extension runtime/registry actor-isolation
  warnings remain; no source-specific build errors were reported.
- Manual Node live smoke: three feed descriptors, 20 popular items, 20 search results,
  details, a readable English chapter, 52 ordered page descriptors, and one actual
  1,778,558-byte image response in seven requests. No responses/images were saved.
  This verifies adapter/API behavior, not the native reader/session pipeline.
- iPhone 16 Pro Max / iOS 27.0 simulator: MangaDex 0.1.0 is available, adding a
  connection enables Browse search, and “Yotsuba” returns live titles. Loading ends
  normally, and the connection persists after reinstall/relaunch. No crash, layout
  issue, or challenge was observed. Original destination restored; session closed.

### Scope and remaining checks

MangaDex is available for testing through Settings → Extensions → Add, then Browse.
At this milestone the UI displayed the first search page only. The 2026-09-19
entry above supersedes that UI limitation.
No real Cloudflare challenge was solved, and physical-device protected-source
metadata/image session continuity remains unverified. Comix is not implemented.
The source notes record language/content defaults, the 10,000-result API window,
rate-limit behavior, and live test commands.


## 2026-09-18 — Extension author guide

Expanded `Extensions/README.md` into the contract-1 authoring reference and linked
it from the root README. It covers scaffolding, manifest validation, every method
and returned data shape, stable identities, pagination, host networking and
Cloudflare verification, runtime limits, manual bundled registration, tests, and
release troubleshooting. Planned APIs are distinguished from implemented ones.

The documented search adapter, manifest, and two Node tests were extracted and
run in an isolated temporary project using the real scaffold and build tools.
Typechecking, bundling, and all six Node checks (four existing plus the two example
checks) passed. Documentation file links and `git diff --check` also passed.
No live adapter was added. Swift tests and an Xcode build were not rerun for this
documentation-only change; the examples do not establish live source or Cloudflare
compatibility.

## 2026-09-18 — Brand assets and UI references

Imported the supplied Midoku asset pack and retained the supplied manga reader
UI kit as the layout reference for subsequent features. See
[`design/README.md`](design/README.md) for paths, precedence, and provenance.

### Implemented

- Approved app icon, 13 adaptive colors, brand artwork, six empty-state sets,
  and three placeholder sets. Artwork is unchanged from the supplied package.
- Shared SwiftUI theme, symbols, brand components, primary button style, and
  scrolling empty states that support Dynamic Type.
- Branded Home, Library, and History empty states; Home and Library actions
  navigate to Browse. Browse and Extensions use the supplied source placeholder.
- Warm light/dark screen surfaces, green controls, and grouped Settings rows.
- Supplied adaptive launch background, configured as `LaunchScreen.storyboard`.
- Developer guidance and both plan copies point to the local design references.
  The reference kit's populated screens and sample sources remain references;
  this milestone does not implement the remaining reader/library features.

### Verified

- Xcode BuildProject succeeds with the imported catalog, storyboard, and SwiftUI
  components. The compiled app selects `AppIcon` and `LaunchScreen`. Existing
  extension-core actor-isolation warnings remain outside this presentation change.
- All 100 imported catalog files match the source bytes after mapping the icon
  directory name from `MidokuAppIcon` to `AppIcon`; all image references resolve.
- The original approved master matches the source manifest's SHA-256.
- iPhone 16 Pro Max / iOS 27.0 simulator: supplied app icon displays; all five
  tabs and Settings → Extensions work; Home/Library Browse actions navigate
  correctly. Light illustrations/surfaces and dark Home/Browse render correctly.
- Enlarged accessibility text on Home, Library, and Browse remains readable
  without clipping, and Library's action remains usable. Decorative source
  images no longer expose their asset names in the accessibility hierarchy.
- Simulator appearance/text settings and the original Xcode destination were
  restored, and the interaction session was closed. Launch transitions and a
  complete accessibility audit were not tested.
- Extension Swift/Node checks were not rerun for these asset and presentation
  changes; the extension implementation is unchanged.

## 2026-09-18 — Extension foundation

The user's current request prioritizes extension architecture and developer setup,
with Cloudflare verification central to the host. MangaDex and Comix will be built
later. This milestone does not claim completion of the full application plan.

### Implemented

- Root `AGENTS.md`, setup documentation, extension author guide, architecture
  decision, pinned npm lockfile, and deterministic Swift/Node checks.
- Five-tab native app shell with separate navigation stacks, a generic source
  directory/search path, and extension management.
- Typed, versioned extension manifests, capability validation, stable source
  identities, a bundled registry, and an interchangeable runtime interface.
- Actual TypeScript → JavaScriptCore execution, async HTTP Promise bridge,
  cancellation of suspended calls, error propagation, and bounded result validation.
- Shared GET request coordinator: exact host/header permissions, manually validated
  redirects, request spacing, rate-limit handling, and bounded response collection.
- Cloudflare challenge detection, visible WebKit verification sheet, per-connection
  persistent browser profiles, matching cookies/User-Agent, one native retry, and
  explicit foreground/background behavior.
- Atomic, versioned persistence of source connection UUIDs and enabled state.
- Offline A/B chapter fixtures built with the same TypeScript SDK and runtime as
  future adapters. The Debug-only Extension Lab validates A missing chapter 21 and
  B providing it. Fixtures do not populate the normal catalogue.

### Verified

- Xcode BuildProject succeeds using Xcode 27.2 (27B5019j), Swift 6.4, iOS 27.2 SDK.
- 14 Swift Testing checks pass on macOS against the app's shared extension core:
  compiled fixture execution, Promise HTTP delivery, secret-header filtering,
  invalid adapters/results, cancellation, exact URL/header permissions, cookie
  scope/expiry, challenge detection, one-retry behavior, background behavior,
  redirect rejection, persistent UUIDs, preservation of unsupported store versions,
  queued verification-sheet dismissal, and cancellation cleanup.
- A clean `npm ci`, TypeScript typechecking, fixture bundling, and all four Node
  checks pass, including scaffold creation, traversal rejection, and refusal to
  overwrite an existing source.
- iPhone 17e / iOS 27.2 simulator: all five tabs respond and render correctly,
  Extensions shows the expected empty state, Settings retains its navigation stack
  across tab switches, and the Extension Lab produces the expected 39/40 chapter
  result without a lingering spinner. No observed layout issues or crashes.
  The interaction session was closed and the original Any iOS Device destination restored.
- The final verification-queue adjustment was built and covered by the presentation
  lifecycle regression check. Live challenge presentation remains unverified.

### Environment notes

The IDE uses `/Applications/Xcode-beta.app` (27.2). The shell's default Xcode is
27.0; select the IDE toolchain explicitly when reproducing these checks.
The existing iOS 27.2 deployment target, bundle identifier, and signing team were
preserved. The core package declares iOS 17/macOS 14 API availability, which is not
evidence of a full app build/run on iOS 17.

Compiler/npm default cache writes were restricted in the coding environment.
These local overrides allowed verification without changing system permissions:

```sh
# From Extensions/
NPM_CONFIG_CACHE=/tmp/midoku-npm-cache NPM_CONFIG_UPDATE_NOTIFIER=false npm ci
NPM_CONFIG_CACHE=/tmp/midoku-npm-cache NPM_CONFIG_UPDATE_NOTIFIER=false npm test

# From the repository root
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/midoku-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/midoku-swift-cache \
swift test --disable-sandbox --cache-path /tmp/midoku-spm-cache --scratch-path /tmp/midoku-spm-build
```

The bundler resolves only explicit local modules and ignores ambient ancestor
configuration. Its standard filesystem resolver stalled in this restricted
environment; the explicit resolver also enforces the intended no-Node-runtime
contract. esbuild still performs the TypeScript compilation and bundling.

### Remaining milestones

- GRDB library schema/migrations, local entry editing, persistent chapter clipboard,
  slots/variants/exclusions, and the complete A:20 → B:21 → A:22 reader workflow.
  Fixture chapter checks do not prove mixed-source composition or restart persistence.
- Reader modes, images/downloads, progress/history, Home feeds, full search/filter
  UI, categories, app lock, appearance, backups, and release polish.
- Comix adapter (MangaDex is now implemented). Confirm Comix's canonical domain before development.
- Real Cloudflare verification and metadata/image session continuity on physical
  devices. No live-source clearance was attempted or established here.
- HTML parser helpers, settings/auth schemas, non-GET and streaming host
  operations as required by researched sources.
- Distribution route, signed remote catalogues/packages, safe staging/activation,
  updates/rollback/key rotation, and a stronger runtime boundary before considering
  unreviewed third-party code.

### Decisions

- TypeScript SDK + JavaScriptCore behind replaceable Swift protocols.
- Host-owned interactive verification and isolated browser sessions.
- Reviewed bundled adapters first; no remote executable imports yet.
- Keep the existing deployment target while establishing the foundation.
- Store only the connection inventory in atomic JSON now; retain its UUIDs when
  moving that inventory into the planned library database.
- Root and Xcode-visible plan copies record the new source/extension decisions.

## Comix and reader controls (implementation)

- Added reviewed Comix contract-2 adapter using the verified primary domain `comix.to` (mirror `comix.ws`), browser API extraction through an isolated connection profile, catalogue/details/chapter/page normalization, and safe/suggestive catalogue scope.
- Added manifest-gated browser rendering, foreground Cloudflare verification with one retry, and shared byte/grid image decoding for online images and downloads. Source signing remains within its browser context. The shared WebKit resource policy and HTML extraction both passed the live macOS probe; interactive device clearance is not yet verified.
- Chapter title overrides now take precedence in library rows and the reader, preserving source IDs and numeric ordering. Reader long-press can set chapter or entry covers transactionally using bounded local images.
- Fullscreen hides the bottom library chapter bar as well as reader controls. Online and offline readers offer previous/next boundary cards and a reserved left-edge close gesture. Source browsing offers adjacency among loaded chapters; library navigation uses the complete canonical sequence.
- Verification: 21 Node tests pass locally. Swift parse, 51 native tests and device archives passed. Final build `35423269372` succeeded at app commit `acaf04819daf984a573f29d4463221a3acd681d8`, including simulator build and screenshots. Downloads and source browsing recover their library sequence when available. Live macOS WebKit smoke passed catalogue, details, chapters and page descriptors; observed cover host `static.comix.to` and image shard `j24n.wowpic2.store`. Reviewed `*.wowpic2.store` for source-owned shard rotation.

- Delivered `Midoku-comix-unsigned.ipa` (4,241,270 bytes), SHA-256 `a0f91f561c935220c3021de004cfffbe185129ec9ede5d82c7f98b51df825564`. Verified ZIP integrity, arm64 Mach-O, bundled Comix, bundle ID `com.raahat.Midoku`, and existing minimum OS 27. Signing/deployment settings are unchanged.
- Final checks: `npm ci && npm test` passed all 21 adapter/tooling tests; `swift test` passed 51 tests in 12 suites; Release archive and Debug simulator build succeeded. Shared browser-policy live smoke `35423133516` returned `ok: true` for safe catalogue, details, chapters and page descriptors. Touch gestures and interactive Cloudflare challenge completion still need device testing; descriptor validation does not establish that every remote page image is available.

## 2026-09-19 device feedback follow-up

- Main screens now draw large titles in compact, solid headers immediately below the status area. The custom bottom navigation occupies its own layout row so lists can reach their last item. Navigation actions use ordinary buttons and opaque surfaces.
- Source entry Add to library is top-right and durably saves the already-visible metadata/chapters immediately. The remaining chapter list is fetched afterward; incomplete fetches never erase remembered releases. Select and clipboard sit beside the chapter language control.
- Online/offline readers share overlay controls and an invariant full-screen page viewport, with previous/next chapter and page buttons. Offline continuous reading now supports page jumps too.
- Covers have separate memory and bounded persistent disk caches with coalesced requests. Downloads & storage exposes Clear cache; downloaded files and custom covers remain separate. History resolves the entry cover, including old records without a saved cover URL.
- Browse includes global search, with independent per-source results/errors. Source, global and library text search run on keyboard submission, preserving results while typing.
- Reset details restores source metadata, covers, chapter edits, reader defaults and automatic ordering, while preserving chapter identities, imported sources, exclusions, categories and progress.
- Added cache persistence/eviction/clearing, partial-add persistence/full refresh, history migration and mixed-source reset regression tests. Local extension checks pass (21 tests); native verification and simulator layout review run in the IPA workflow.

- Native verification passed all 60 Swift tests and 21 extension tests. Simulator review confirmed the compact title headers and stable reader page frame, and caught a status-area overlap in reader chrome; controls now read safe-area insets from a separate outer container. The Settings boundary preview explicitly scrolls to the last row.

## 2026-09-19 navigation and chapter layout follow-up

- Restored native navigation back buttons and system glass toolbar actions, retaining compact root headers and the solid, space-reserving bottom navigation. Root action icons now share 20-point glyphs and 44-point glass controls; pushed Browse directories keep the native navigation bar.
- Chapter thumbnails use portrait 2:3 frames. Settings → Library offers independent chapter list/grid mode and portrait/landscape items per row. Both personal and source entry grids keep selection, reading, downloads and chapter actions, and use virtualized native List rows. Accessibility text falls back to lists.
- Library, source browsing and global search now use the same manga layout preference and viewport orientation. Removed the conflicting legacy Browse density control; existing preferences continue to decode.
- Hide empty chapter clipboard/paste actions. Personal-entry paste opens the paste review directly. Removed successful refresh status and chapter ordering explanations while preserving failures and source metadata.
- Original-listing actions resolve exact source identities into native entries when the extension is enabled. Website fallback and source website links present an internal Safari sheet, without changing source sessions or launching external Safari.
- Added settings migration, restart persistence and invalid-backup count checks, plus simulator captures for portrait chapter lists, chapter grids, source grids and empty clipboard state. Native build and screenshot verification are pending.
