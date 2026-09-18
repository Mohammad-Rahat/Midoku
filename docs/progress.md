# Development progress

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
The current UI displays the first search page; details, feed, reader, and search
pagination screens remain app milestones even though their adapter methods work.
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
- Live MangaDex/Comix adapters. Confirm Comix's canonical domain before development.
- Real Cloudflare verification and metadata/image session continuity on physical
  devices. No live-source clearance was attempted or established here.
- HTML parser helpers, filters/settings/auth schemas, non-GET and streaming host
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
