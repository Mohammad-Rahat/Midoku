# Midoku — iOS Manga Reader Implementation Plan

> Purpose: build **Midoku**, a real, native iOS manga reader with custom extensions and an editable personal library that combines chapters from different sources.
>
> Read this document before implementation. Treat the product invariants and acceptance criteria as requirements. Technical defaults below are implementation recommendations, not claims that a codebase already exists.
>
> App name: **Midoku**, selected by the user. Use this name consistently in the app and project documentation. This document is self-contained; design files are helpful references, not prerequisites for starting.
>
> **2026-09-18 extension decision:** use the versioned TypeScript/JavaScriptCore adapter foundation and shared native WebKit verification flow described in `docs/extension-architecture.md`. MangaDex and Comix are the first planned live extensions, to be implemented later. See `docs/progress.md` for actual completion; the full plan below is not yet implemented. The Xcode-visible copy is `Midoku/plan.md`.

## 1. Instructions to the implementation agent

1. Inspect the repository, existing architecture, build configuration, available Xcode version, and any `AGENTS.md` instructions before changing files.
2. If an app already exists, preserve its working behavior and adapt this plan to its architecture. Do not replace a functioning persistence layer or scaffold a second app without a concrete reason.
3. If starting fresh, use the defaults in this document. Record meaningful deviations and their reasons in a short decision log.
4. Build incrementally, with a runnable app after each phase. Do not deliver a collection of disconnected mock screens.
5. Prove cross-source chapter composition early. Do not spend the first milestone polishing discovery while the core library model remains untested.
6. Use fixtures for predictable development, then integrate real sources. Keep fixture content out of normal production installations.
7. Every visible production action must work, be explicitly disabled with a reason, or be omitted until implemented. Toast-only prototype actions do not count as completed features.
8. Preserve user-entered metadata, covers, chapter selections, removed-chapter decisions, reading order, and progress during source updates.
9. Keep routine implementation decisions autonomous. Ask only when a missing decision materially changes product scope, distribution, data compatibility, or external account access.
10. Do not invent credentials, bundle identifiers owned by the user, signing teams, paid services, extension URLs, source API behavior, or successful test results.
11. Do not add a backend, mandatory account, subscription system, analytics SDK, or cloud synchronization to the first version.
12. Keep extension development documented and reproducible. The user expects the implementation agent to establish how extensions are written, tested, built, and maintained.
13. Verify actual SDK availability and dependency compatibility in the build environment. Avoid private APIs and unsupported claims about background execution or extension isolation.
14. At each milestone report what works, what was verified, and any remaining blocker. Keep changes cohesive and avoid unnecessary commits; follow the user's repository instructions if provided.
15. If running outside macOS/Xcode, complete portable work and explicitly report that iOS builds or device checks were not performed. Never report a successful simulator build based only on static review.

## 2. Product definition

Midoku draws on the familiar reading and discovery patterns of Mihon, Aidoku, Suwatte, and Paperback. Its distinguishing feature is the **personal library entry**: a manga collection owned by the user, with editable metadata and a reading sequence assembled from multiple extensions.

Use **Midoku** as the installed app display name, in About/settings, onboarding, permission explanations where the app is named, backup/export descriptions, extension developer documentation, and release documentation. Use `Midoku` for a new Xcode project and app target where appropriate; use lowercase `midoku` for new tooling identifiers when a lowercase name is needed. Keep functional names such as `Reader`, `ReaderView`, and `Features/Reader/` where they describe the reading feature. The developer-owned bundle identifier and signing team still require the actual project configuration.

The original brief mentioned four tabs but named five. Implement all five:

| Tab | Purpose |
| --- | --- |
| Home | Pinned extension feeds and optional personal reading sections |
| Library | Editable manga entries, categories, and combined chapter collections |
| Browse | Installed extensions, source discovery, and global search |
| History | The most recent 100 distinct opened source chapters |
| Settings | Appearance, app lock, categories, reader, extensions, storage, and backups |

An extension is our app's content adapter for a source. It is not an iOS app extension target and does not require one independently signed app binary per source.

### 2.1 Canonical example

- Extension A provides Naruto chapters 1–20 and 22–40.
- The user adds that listing to their library.
- Extension B provides Naruto chapters 1–40.
- The user copies chapter 21 from B into the app's clipboard.
- The user opens the personal Naruto entry originally added from A and pastes chapter 21.
- The combined sequence becomes A:20 → B:21 → A:22.
- Chapter 21 displays B's source label.
- Next/Previous Chapter follows that combined sequence.
- Refreshing A and B, updating an extension, and restarting the app preserve the composition.
- The user can edit the entry title, description, and cover without losing those changes on refresh.

### 2.2 Scope categories

**Core requested behavior:** five tabs; custom extensions; source-tab pinning; rearrange/delete Home sections; editable library entries and covers; chapter thumbnails; mixed-source chapters; chapter copy/paste; visible source attribution; categories; global/source search; source-defined tabs and filters; History limited to 100; app lock, appearance, cache clearing, reader preferences, and extension management.

**Recommended first-version additions:** duplicate resolution, persistent clipboard, multi-select actions, source update management, selected-source following, basic downloads/offline reading, backup/restore, manual reading order, progressive search, accessible alternatives to long press, Continue Reading, and Library Updates.

**Deferred:** iCloud sync, tracker integrations, local CBZ/PDF/EPUB import, OPDS/media servers, widgets, reading statistics, automatic chapter matching/filling, public third-party extension marketplace, collaborative libraries, Android, web, and macOS apps.

The user has selected MangaDex and Comix as the first production extensions, to be implemented after the source-independent foundation. Verify their current availability, canonical domains, and integration requirements before implementation; Comix's exact domain is still unconfirmed. MangaSee in the older designs remains sample content.

## 3. Non-negotiable invariants

1. A personal library entry has an app-owned identity independent of its source listings.
2. A source chapter retains its immutable source provenance even after display metadata is edited.
3. Editing a local entry never edits the source website.
4. Refresh cannot overwrite explicit user overrides, including intentional blank values.
5. Copy/paste copies references and local display information, not chapter page files.
6. Copy does not use or overwrite the system clipboard.
7. Pasting one chapter does not subscribe the user to every chapter from that source.
8. The same physical source chapter cannot appear twice in the same personal entry accidentally.
9. Equal chapter numbers do not prove equal chapters or translations.
10. A deliberately removed chapter stays removed until the user restores or explicitly re-adds it.
11. Reader sequence is separate from list display sorting and temporary list filters.
12. A failed source does not block other sources or erase local data.
13. Trimming or clearing History does not delete reading progress.
14. Clearing cache does not delete downloads, custom covers, personal metadata, or the database.
15. Fully downloaded chapters remain readable without the originating extension being installed.
16. Removing one library entry does not destroy shared chapter files or progress needed elsewhere.
17. No source is silently substituted when the selected chapter cannot load.
18. No title-based automatic merge across sources.
19. App updates and source updates must preserve persistent identifiers and migrate data explicitly.
20. The app does not require a central backend for ordinary local library use.

## 4. Recommended technical foundation

These defaults make the plan actionable. Reuse equivalent existing solutions if the repository already has them.

| Area | Default |
| --- | --- |
| Platform | Native iPhone app; portrait-first interface, rotation-aware reader |
| Minimum OS | iOS 17 as a planning default; confirm installed toolchain/dependency support |
| Language | Swift with structured concurrency; enable appropriate concurrency checks |
| UI | SwiftUI, using UIKit bridges for reader behaviors that require them |
| Navigation | `TabView` plus a separate `NavigationStack` path per tab |
| State | Observable feature state on the main actor; injected service dependencies |
| Database | SQLite through GRDB, with explicit migrations and transactional repositories |
| Network | URLSession behind one source-aware request coordinator |
| Image handling | Shared image pipeline, bounded decoding, memory/disk cache, ImageIO where useful |
| Secrets | Keychain; never ordinary settings or source bundles |
| App lock | LocalAuthentication with device-authentication fallback |
| Extension authoring | TypeScript compiled to a JavaScript bundle |
| Extension runtime | JavaScriptCore feasibility spike behind a replaceable runtime interface |
| Extension distribution | Our maintained, signed HTTPS catalogue and bundles |
| Backup | Versioned archive containing structured JSON and custom assets |
| Package management | Swift Package Manager for Swift; one locked package manager for extension tooling |
| Testing | XCTest or the supported Swift testing framework for domain tests; XCUITest for key flows |

GRDB is a SQLite toolkit; consult its [official repository](https://github.com/groue/GRDB.swift) for actual APIs and supported versions. This plan specifies our architecture, not a particular GRDB version or undocumented behavior.

Pin dependency versions after verifying compatibility. Do not use floating package versions in a release build. Add third-party dependencies only where they solve a concrete need, such as robust HTML parsing or archive processing.

### 4.1 Repository organization

Use a simple feature-oriented structure. Names can adapt to the existing repository.

| Directory/module | Responsibility |
| --- | --- |
| `App/` | App entry, dependency container, scene lifecycle, navigation, lock coordinator |
| `DesignSystem/` | Semantic colors, type styles, spacing, reusable views, icons |
| `Domain/` | Stable identities, models, ordering, duplicate decisions, reader sequence |
| `Persistence/` | Database setup, migrations, records, queries, repositories |
| `Services/Networking/` | Requests, source isolation, rate limits, retry policy |
| `Services/Extensions/` | Catalogue, signatures, packages, bridge, runtime, source adapters |
| `Services/Images/` | Thumbnails, decoding, caching, image request context |
| `Services/Downloads/` | Queue, page manifest, file validation, recovery |
| `Services/Backup/` | Export, validation, merge/replace import, recovery |
| `Services/Refresh/` | Source refresh jobs, snapshots, reconciliation, update events |
| `Features/Home/` | Pins, section loading, personal sections |
| `Features/Library/` | Collection, details, edits, categories, source linking |
| `Features/Browse/` | Source catalogue, discovery, global search |
| `Features/Chapters/` | Selection, clipboard, paste preview, alternatives |
| `Features/Reader/` | Paged/continuous rendering, controls, progress |
| `Features/History/` | Recent opens and resume |
| `Features/Settings/` | Preferences, lock, storage, extension management |
| `Extensions/sdk/` | Typed contract, host helpers, validation |
| `Extensions/template/` | New-source starter |
| `Extensions/sources/` | Individually maintained source adapters |
| `Extensions/fixtures/` | Deterministic request/response samples |
| `Tests/` | Domain, integration, migration, and UI tests |
| `docs/` | Setup, extension author guide, decisions, release instructions |

Avoid creating a separate package for every screen. Clear boundaries matter more than a large number of modules.

### 4.2 Architectural boundaries

- Views render state and dispatch user actions; they do not execute SQL or parse website responses.
- Feature models coordinate services and expose loading/content/error states.
- Repositories own persistent writes and transactions.
- Domain services own ordering, identity, duplicate resolution, and composition rules.
- Extensions return normalized content data. They never directly mutate the library.
- The network coordinator enforces source request policy for metadata and page images alike.
- The reader consumes a resolved reading context, not a hardcoded extension chapter array.
- File access goes through a storage service so cache, permanent assets, and downloads stay separate.
- Keep clocks, UUID generation where needed, networking, and extension execution injectable for deterministic tests.
- Serialize database writes through the chosen database facility. Do not move non-Sendable runtime/database objects between arbitrary Swift tasks.

## 5. Design direction and screen inventory

Build a minimal, calm iOS interface. Use warm backgrounds, charcoal text, muted forest-green actions, clear manga covers, thin separators, and restrained cards. Avoid a card around every row, oversized shadows, decorative gradients, and dense dashboards.

### 5.1 Available design references

The user supplied the UI design kit and approved Midoku asset pack on 2026-09-18. Repository copies live in `docs/design/manga-reader-design-kit/` and `docs/design/Midoku/`. Read `docs/design/README.md` for precedence and integration. Use the UI kit for layouts and the newer brand guide for final identity, adaptive colors, and illustrations. Native resources are in `Midoku/Resources/MidokuAssets.xcassets`; shared SwiftUI components are in `Midoku/DesignSystem/`.

The preceding design work produced:

- `manga-reader-design-board.svg`: a board containing 20 main screens/states.
- `manga-reader-preview.html`: a self-contained clickable preview.
- `manga-reader-design-kit.zip`: individual screen SVGs, tokens, and source assets.
- `manga-reader-overview.png`: the five-tab overview.

These are reference artifacts, not a native Figma document or production app. The Figma editing connection was unavailable during design. The preview has sample content and some feedback-only utility actions. Do not reproduce those limitations in the actual app. The cover and reader art in the kit is original abstract placeholder artwork, not official manga covers. Earlier references use “Reader” or “The Reader” as placeholder branding; replace those product-name labels with **Midoku** during implementation while keeping the minimal visual direction. The reference filenames above remain unchanged.

If supplied with the repository, place references under a documentation/design directory. Do not ship the HTML prototype as the native application.

### 5.2 Tokens

| Semantic role | Light reference |
| --- | --- |
| App background | `#FAFAF7` |
| Elevated/grouped surface | `#FFFFFF` |
| Primary text | `#202D26` |
| Secondary text | `#606D63` |
| Main accent | `#376A50` |
| Accent surface | `#E9F0E9` |
| Neutral control surface | `#F0F2ED` |
| Separator | `#E7EAE4` |
| Attention/accent brown | `#B66B3E`, only where contrast is sufficient |

Use semantic color assets with explicit dark-mode variants. Dark mode is a first-version requirement under appearance settings, even though most supplied designs use light mode. Test contrast against actual surfaces; do not mechanically invert colors.

- Use native system typography/SF Pro in the app. The SVG references use Arial for portability.
- Prefer Dynamic Type text styles. Reference sizes: large title 32–34 pt, screen title 27–29 pt, section title 19–20 pt, body 15–17 pt, supporting text 12–14 pt.
- Reference screen: 393 × 852 points. Implement adaptive constraints, not fixed screen coordinates.
- Default horizontal margin: 24 pt, reduced where appropriate for smaller screens.
- Spacing scale: 4, 8, 12, 16, 24, 32 pt.
- Card radius: about 16 pt; controls 12–14 pt; pills fully rounded.
- Minimum interactive target: 44 × 44 pt, including small-looking icons and text actions.
- Use SF Symbols for interface icons and label all five tabs.
- Respect safe areas, the home indicator, keyboard, and native sheet presentation.
- At large text sizes, increase row heights and reduce cover grid columns instead of clipping text.
- Use light haptics for copy, pin, and successful additions. Respect system settings.
- Loading placeholders should resemble content geometry and avoid disruptive whole-screen flashes.

### 5.3 Required screens

| Screen | Required content/actions |
| --- | --- |
| Home | Personal sections, pinned feeds, view-all routes, section errors |
| Library | Categories, collection search, sort/filter, bulk actions |
| Browse | Enabled sources, favorites, source list search, global search entry |
| History | Recent chapters, resume, date groups, removal |
| Settings | Grouped preferences and management routes |
| Personal manga detail | Editable metadata, source links, combined chapters, continue, paste |
| Source discovery | Source-defined feeds, filters, pagination, pin menu |
| Source manga detail | Source metadata, original chapters, add/link/copy |
| Edit manga | Metadata form, cover picker, per-field reset |
| Edit chapter | Local display fields, thumbnail, reading position/order |
| Chapter action sheet | Read/resume, copy, add elsewhere, edit, remove/download actions |
| Paste preview | Clipboard selection, destination, conflicts, proposed order |
| Chapter alternatives | Source/language/group comparisons, preferred version |
| Reader | Pages, progress, next/previous, source context, controls |
| Reader preferences | Modes, navigation, fitting, background, per-entry overrides |
| Home management | Reorder, rename, hide, delete |
| Categories | Create, rename, reorder, assign, delete |
| Extension management | Install/update/disable/remove, versions, source settings |
| Global search | Progressive groups, source filters, retry, view all |
| Downloads/storage | Queue, saved chapters, retry/cancel, usage, clear cache |
| Backup/restore | Export, import validation, preview, merge/replace summary |
| App lock | Authentication, lock delay, error/recovery states |

Some functional screens have no supplied visual reference. Design them using the same tokens and native patterns; do not leave them unimplemented because a mockup is missing.

## 6. Navigation and app lifecycle

- Each tab retains its own navigation stack, selected category, search query, and scroll position where sensible.
- Switching tabs must not reset another tab's state or start duplicate refreshes.
- The reader opens full screen. Hide the bottom tab bar while reading.
- Editing and paste review can use sheets or dedicated screens depending on size. Never stack ambiguous sheets repeatedly.
- Source routes identify source connection, manga, feed, filters, and sort using stable IDs.
- Personal routes use the library entry UUID, not its title.
- Reader routes carry a reading context: personal entry/slot/release, or source listing/chapter for direct Browse reading.
- Back returns to the originating screen with its scroll position intact.
- Preserve necessary draft edits during temporary backgrounding. Ask before discarding unsaved form changes.
- On launch, load the local collection first, then schedule nonblocking stale-data refreshes.
- Protect app content in the app switcher while locked. Avoid exposing covers behind the authentication sheet.
- Save reader progress frequently and on scene changes; never rely solely on application termination callbacks.
- Cancelling authentication keeps content locked and presents a retry route.
- On an unavailable destination, show saved metadata and repair options rather than a blank screen.

## 7. Domain model and identity

The following conceptual entities must remain distinct. Physical SQL naming can differ.

### 7.1 Identity rules

- Generate persistent UUIDs for app-owned entities.
- A source listing identity is `(sourceConnectionID, externalMangaID)`.
- A source chapter identity is `(sourceListingID, externalChapterID)`.
- A connection refers to an extension ID plus a particular source configuration/account context. Its UUID survives restarts and backups.
- Extension version is not part of source content identity.
- A content URL is a locator, not necessarily an identity. Prefer source-provided stable IDs.
- A manga title, cover URL, chapter number, array index, or image URL must never be the primary key.
- Preserve IDs if a URL changes. Migrate identity through an explicit alias/relink process if a source changes its identifier scheme.
- Normalize only according to that source's semantics. Do not indiscriminately lowercase IDs or strip URL query parameters.

### 7.2 Suggested entities and fields

| Entity | Important fields and purpose |
| --- | --- |
| `LibraryEntry` | UUID, created/updated dates, personal reading status, metadata source link, title/description/etc. overrides, cover asset, reader overrides, sequence revision, soft-delete state |
| `ExtensionInstallation` | Stable extension ID, publisher identity, installed/previous version, contract version, status, package location, last error/check dates |
| `SourceConnection` | UUID, extension ID, label, enabled/favorite state, settings, selected language, opaque credential reference |
| `SourceListing` | UUID, connection UUID, external manga ID, canonical URL, latest source metadata snapshot, fetch timestamps, availability |
| `EntrySourceLink` | UUID, entry UUID, listing UUID, follow mode, metadata-primary flag, auto-add policy, last refresh outcome |
| `SourceChapter` | UUID, listing UUID, external chapter ID, original title/number/volume/date/language/group, optional cover, canonical URL, availability and revision |
| `EntryChapterSlot` | UUID, entry UUID, sequence key, normalized display identity, preferred variant UUID, optional completion override, created/updated dates |
| `EntryChapterVariant` | UUID, slot UUID, source chapter UUID, local title/number/volume/cover overrides, origin=followed/manual, added date |
| `ChapterExclusion` | Entry UUID + source chapter UUID, removed date; prevents refresh re-addition |
| `ChapterProgress` | Source chapter UUID, page identity/index, page-relative scroll fraction, page count snapshot, completed flag, updated date, content revision |
| `HistoryRecord` | Source chapter UUID, last opened time, last reading-context hint, title/cover snapshots; unique per source chapter |
| `Category` | UUID, name, normalized name, order, optional update/download preferences |
| `EntryCategory` | Unique entry UUID + category UUID pair |
| `HomeSection` | UUID, kind, order, enabled, custom label, source/feed descriptor or built-in section type |
| `Clipboard` | Singleton versioned collection of copied references, order, copied metadata/override snapshots, copied date |
| `DownloadJob` | UUID, source chapter UUID, requested rendition/settings fingerprint, state, retry info, progress, cancellation flag |
| `DownloadedChapter` | UUID, source chapter UUID, rendition/version key, page manifest, permanent directory, completeness and validation state |
| `LocalAsset` | UUID, purpose, content hash, relative path, MIME type, dimensions, byte size, created date |
| `LibraryUpdateEvent` | Entry/slot/source chapter references, first discovery time, notification/read state |
| `IdentityAlias` | Source-scoped old identity to canonical identity mapping, with migration provenance |
| `AppPreferences` | Versioned nonsecret settings; small values can use UserDefaults behind a typed wrapper |

### 7.3 Why slots and variants exist

An entry's logical Chapter 21 is a slot. Extension A's English Chapter 21 and Extension B's English Chapter 21 may be variants of that slot after the user confirms equivalence. The slot determines where the chapter belongs; the preferred variant determines which release the reader opens.

Do not automatically place unverified same-number chapters into an equivalence group. They remain separate items or unresolved candidates until confirmed. Different languages/groups must be visible during comparison.

- Slots belong to one personal entry.
- Variants belong to a slot, and reference shared source chapter records.
- A source chapter can be referenced by different personal entries without duplication of its physical record.
- The same source chapter can appear at most once across slots in one entry.
- Each nonempty slot has exactly one preferred variant.
- Deleting a preferred variant either promotes a user-selected remaining variant or removes the now-empty slot.
- Display metadata overrides are entry-specific; shared original source data remains unchanged.

### 7.4 Metadata override semantics

Represent each editable field as inherited, explicitly set, or explicitly cleared. A plain nullable value that cannot distinguish cleared from inherited is insufficient.

Effective display value = local explicit value/clear state if present, otherwise the current value from the entry's selected metadata source, otherwise a local fallback.

- Resetting a field removes its override and immediately reveals the latest inherited value.
- Changing metadata source changes only inherited fields.
- A manual entry has no required source link and can have zero chapters.
- Source labels/provenance are not editable disguises; users may rename a connection, but its actual extension remains inspectable.
- Validate titles as nonempty after whitespace trimming; preserve meaningful line breaks in descriptions.

### 7.5 Persistent integrity

- Enforce uniqueness in the database as well as UI logic.
- Make paste, reorder, preferred-variant changes, history upsert/prune, and restore commits transactional.
- Use foreign keys and intentional delete policies. Avoid broad cascading deletes into shared source content/progress/downloads.
- Store dates in a consistent UTC representation; localize only when displaying them.
- Store chapter decimals as exact text/decimal representations, not lossy binary floating-point keys.
- Keep a stable ordinal tie-breaker where chapter metadata is incomplete.
- Index entry/category joins, source identities, entry sequence order, last-read dates, history dates, download state, and source refresh status.
- Add explicit schema migrations. Never resolve a migration error by silently deleting the user's database.
- Maintain a recovery path before destructive migrations/import replacement.
- Use relative storage paths. Never back up simulator/device-specific absolute paths.

## 8. Library behavior

### 8.1 Adding entries

From source details, Add to Library creates the personal entry, source link, initial source chapter references, selected categories, and inherited metadata.

- If the exact listing is already linked, offer Open Library Entry first.
- If several personal entries reference it, show a destination chooser rather than guessing.
- If a similar title exists, offer Link to Existing or Create Separate. Similarity is a suggestion only.
- Creating an empty entry opens the same editor with local fields and a later Add Source/Chapters route.
- Adding a listing with existing Browse progress should reuse its source chapter identities and progress.
- Initial import is not a batch of new-chapter update notifications. Establish the initial snapshot before generating future update events.
- Keep adding cancellable where network work is involved. Do not leave a half-created entry after an atomic operation fails.

### 8.2 Collection display

- Grid by default; optional compact list.
- Search effective title and alternative titles without needing network access.
- Sort by title, recently read, recently added, and recently updated.
- Filters: unread, downloaded, personal reading status, publication status, source, and category.
- Unread counts reflect logical slots with preferred variants, not the total number of duplicate releases.
- Category membership is many-to-many. All and Uncategorized are virtual views, not mandatory ordinary database categories.
- Long press starts multi-select; a visible Select action offers the same functionality.
- Bulk actions include set categories, mark read/unread, download where supported, refresh, and remove entries.
- Removing an entry explains whether downloaded files will be retained or deleted. Default to preserving shared downloads and unrelated progress.

### 8.3 Personal status versus publication status

Personal status: Planned, Reading, Completed, On Hold, Dropped. Publication status: Ongoing, Completed, Hiatus, Cancelled, Unknown where supported.

Do not mark publication Completed because the user read every currently available chapter. Do not reset personal Completed merely because a metadata fetch changed a publication field. If new chapters appear, show unread counts and let the user adjust personal status.

### 8.4 Categories

- Create, rename, reorder, and delete.
- Prevent empty names. Warn about or prevent normalized duplicate names within the local library.
- Preserve user-selected order across restarts.
- An entry can belong to several categories.
- Deleting a category leaves its entries intact.
- Bulk assignment must distinguish replacing all categories from adding/removing selected memberships.
- Optional category update preferences are scoped to refresh/download scheduling, not chapter identity.
- If an entry belongs to several categories, deduplicate scheduled work by source listing.

## 9. Manga detail and chapter list

### 9.1 Header

Show cover, title, author/artist, publication status, personal status, summary, genres, categories, source links, and Start/Continue. Collapse long descriptions with an explicit expansion control.

Cover controls support Photos and Files, with crop/fit preview. Copy selected assets into permanent app storage; do not depend on a temporary photo/file-picker URL. Apply file size and image dimension limits without silently discarding the previous cover on import failure.

Provide Edit Details, Manage Sources, Refresh, and Remove from Library. Show last refresh failure without hiding existing content.

### 9.2 Chapter rows

Each row includes a thumbnail, chapter display number/title, available volume/date, progress/read state, download state, and source label below the main details. Language and group appear where useful.

Thumbnail precedence:

1. Explicit local chapter cover.
2. Source-provided chapter thumbnail.
3. Already cached/available first-page thumbnail when enabled.
4. Effective manga cover.
5. Neutral placeholder.

Do not request every chapter's pages to build a list of thumbnails. Lazy-load visible thumbnails; cancel off-screen requests. First-page preview fetching should be opt-in or conservatively bounded, with a spoiler-safe fallback.

Filters: all/unread/read/downloaded, source, language, and group where present. Sort display ascending/descending or by date. Preserve these view preferences independently from the canonical reading sequence.

### 9.3 Context actions and local edits

| Context | Actions |
| --- | --- |
| Any available source chapter | Read/resume, Copy, Add to Another Entry, Open Original Source, download if supported |
| Personal entry chapter | Above plus edit local display fields, mark read/unread, remove from this entry, choose alternative |
| Downloaded chapter | Read offline, delete download, inspect origin |
| Removed chapter | Restore/re-add from a removed-items view |
| Unavailable chapter | Retry, inspect reason, reinstall source, choose/link alternative, remove locally |

Source detail chapter menus should remain familiar. If Edit is selected before a personal entry exists, ask the user to create or select the personal destination. Remove applies to a personal collection; it must never suggest deletion from a third-party website. Copy remains usable without adding the entire title to Library.

Editable chapter fields: display title, number, volume, local cover, and reading order. Original IDs and provenance remain stable.

### 9.4 Source management

For every linked listing show extension, title, language, follow mode, metadata-source choice, refresh state, and Open Original action.

- Primary initial source: Follow New Chapters enabled by default.
- Source introduced by one pasted chapter: Selected Chapters Only by default.
- Enabling follow on a secondary listing requires an explicit import policy and duplicate preview.
- Disabling follow stops automatic new-chapter insertion, not access to existing references.
- Unlinking asks whether to keep or remove chapters from that link. Preserve references needed by retained variants.
- A chapter may remain accessible through its source connection even when that listing is no longer followed.

## 10. Copy, clipboard, paste, and alternatives

### 10.1 Copy

- Single or multi-select copy.
- Copy replaces the existing clipboard selection in v1; do not silently append unless an explicit Add to Clipboard action is later introduced.
- Store source chapter references, source labels, title/number/volume/language/group snapshots, selection order, and relevant local display overrides when copying from a personal entry.
- Do not copy credentials, transient image URLs as identity, page files, or read status as if it were part of the chapter's display metadata.
- Persist clipboard contents across navigation, reader presentation, and restarts.
- Provide a count, preview, remove-item action, and Clear Clipboard.
- Keep clipboard contents after paste so repeated pasting into different entries works.
- A broken/missing source does not automatically clear the clipboard. Show the limitation at paste/read time.

### 10.2 Paste review

1. Select or confirm destination personal entry.
2. Resolve clipboard references locally; fetch metadata only if needed and possible.
3. Compare against current destination memberships.
4. Show chapter source, proposed position, title/language mismatch hints, and conflicts.
5. Allow deselection of copied items and manual position adjustment.
6. Resolve every conflict before commit.
7. Commit all approved insertions atomically, with the entry sequence revision checked again.
8. Show counts for added, skipped, replaced, and retained-as-alternatives.
9. Keep the clipboard available.

If the entry changes while the review is open, regenerate the preview or revalidate the conflicting subset. Never apply choices against a stale sequence without checking.

### 10.3 Conflict decisions

| Situation | Behavior |
| --- | --- |
| Exact source chapter already in destination | Skip by default; no duplicate membership or progress reset |
| Same displayed number, different source release | Show possible duplicate; user chooses skip, replace, keep alternative, or separate slot |
| Different language/group | Surface it prominently; never assume interchangeability |
| Matching title, different edition/volume | Require explicit equivalence before grouping |
| Missing/ambiguous number | Suggest position using neighboring metadata; allow manual placement |
| Removed/excluded exact chapter explicitly pasted | Ask to restore/re-add and remove its exclusion if confirmed |
| Clipboard from a different manga | Show destination/source titles and allow deliberate insertion; do not silently reject a valid custom collection |
| Source not installed | Allow saving a reference with a clear unavailable state; reading requires installation or a verified download |

### 10.4 Replace versus keep

- Keep Alternative retains the old and new release under a confirmed logical slot. Let the user choose which is preferred.
- Keep Separate creates another independent slot; use this for specials or uncertain equivalence.
- Replace Existing selects the new release in that slot and removes the old variant from the entry after explicit confirmation. Retain shared source records/history/downloads according to retention policy.
- Record an exclusion for the removed old release so a later refresh does not immediately undo replacement.
- Keep the slot's position and local slot identity during replacement.
- Do not transfer page index/scroll offsets to a different release automatically.
- If the user confirms equivalence, offer to preserve completed status at the logical slot. Otherwise use the new release's actual progress.
- Do not mark an alternative's physical pages read just because another release was read.

### 10.5 Reading order

- Normal mode sorts by a source-aware exact chapter/volume/part key, with stable fallbacks.
- Support decimal chapters, special labels, volume-local numbering, and multiple parts.
- Do not use string sorting that places 10 before 2.
- Define deterministic tie-breaking for equal/unknown values: existing sequence order, source-provided ordinal, then stable UUID.
- Unknown numbers retain source order where possible.
- Manual mode uses persisted order keys; renumber these transactionally when needed.
- In manual mode, new followed chapters enter a visible review group or append without moving existing items. Choose and document the default; v1 default is append with an Added Chapters notice.
- Changing list display sort does not rewrite the stored reading order.
- Next Chapter uses the current entry's slot sequence and preferred variants, skipping nonpreferred alternatives.
- Temporary list filters do not alter Next Chapter in v1. If a future Skip Filtered Chapters preference is added, make it explicit.

## 11. Reading progress and History semantics

### 11.1 Physical versus logical progress

Use canonical progress per physical `SourceChapter`. Reading the same release from Browse, History, or an entry resumes the same actual page.

- Different source releases have separate physical progress, even if grouped as alternatives.
- A logical slot may have a completion override only for a user-confirmed equivalent replacement or explicit slot-level decision.
- Effective slot completion is its explicit completion override if present, otherwise its preferred release's completed state.
- Actual reading of the new preferred release can update/clear that override according to an explicit user action. Do not silently map old page positions.
- Mark Read/Unread in a source release context updates that release's canonical progress. Other entries preferring that same release see the same status; document this consistent v1 behavior.
- Mark Read/Unread in a slot context updates the preferred release and clears conflicting completion overrides for that slot.
- Bulk marking all slots affects preferred releases, not every alternative.
- Keep historical maximum reached separately if useful; a reread position is not automatically a loss of completed status.
- Explicit Mark Unread resets completed state and the resume position; do not remove History unless separately requested.

### 11.2 Saving progress

- Use zero-based indices internally and one-based page labels in the UI.
- For continuous mode, store a stable page ID/index plus normalized position within that page, not only total scroll pixels.
- Record the page manifest revision and page count used to interpret progress.
- Save on page transitions, throttled meaningful scrolling, backgrounding, and reader dismissal.
- Suggested debounce is 500 ms for scrolling; transitions and background flushes should not wait for it.
- Out-of-order async writes must not overwrite newer progress. Use session sequence numbers/timestamps under serialization.
- Do not mark completion just because page count loaded or the last page was prefetched.
- Completion requires the final page to be displayed; for a very tall final webtoon page, require reaching its end region. Use a small visibility/dwell threshold and test it.
- If page order/count changed, attempt stable-page matching; otherwise clamp safely and disclose a resumed-nearby position rather than pretending exact recovery.

### 11.3 History

- Upsert when the reader opens for a valid chapter reference, including a chapter whose network load subsequently fails. A details-screen visit is not a History event.
- Unique by canonical source chapter UUID, not by title, logical number, entry, or session.
- Reopening updates the timestamp and reading-context hint.
- Keep at most 100 records, newest first. Upsert and prune in one transaction, with stable tie-breaking.
- Group visually by Today, Yesterday, then localized date.
- Store sufficient display snapshots to show a useful row if a source is later uninstalled.
- Open History using the remembered personal context when valid; otherwise open the source chapter directly.
- Deleting a row, clearing all rows, or automatic truncation leaves progress, entries, and downloads unchanged.
- Reading chapter 101 removes only the oldest History row, not that chapter's progress.
- If two different releases of logical chapter 21 are opened, they are two distinct History records.

## 12. Home feeds and pinning

### 12.1 Pin descriptor

Persist a descriptor containing section UUID, kind, connection UUID, stable feed ID, query where relevant, canonicalized filters, sort, language, optional user title, order, enabled flag, and last successful result/cache reference.

- Do not pin only a URL or source display name.
- Do not pin the currently returned array of covers as permanent content.
- Exclude pagination cursor from pin identity; pins start at the beginning of the saved query.
- Canonicalize filter serialization so the same filter object in a different property order does not create a duplicate pin.
- The same feed with materially different filters may be pinned separately.

### 12.2 Interaction

- Long press a source tab → Pin to Home.
- Provide a menu/button alternative for accessibility and discoverability.
- Suggested initial preview count: 10 items, horizontally scrolling.
- View All opens the exact feed/query/filter context and supports pagination.
- Tapping the extension label opens that source's main discovery page.
- Tapping a cover opens the appropriate source detail with a visible route to its personal entry.
- Show a success confirmation without resetting navigation.
- Exact duplicate pin creation should offer Open Existing or Update Existing, not create another identical section.

### 12.3 Management and loading

- Reorder, rename, hide, unhide, and delete pins in Settings → Home Sections.
- Home has a shortcut to the same management view.
- Deleting a pin does not delete source data, entries, or downloads.
- Continue Reading and Library Updates are optional built-in section types with the same ordering/hide controls.
- Load cached content first. Suggested feed cache freshness target: 15 minutes, configurable centrally.
- Pull to refresh starts independent section requests through shared rate limiting.
- One section failure remains local to that section. Keep stale successful results with a small status label and Retry.
- Source disabled/uninstalled: retain the pin and show an enable/reinstall action.
- Feed removed in a new extension version: mark the pin unsupported and offer a replacement feed; never silently point it elsewhere.
- Feed renamed with stable ID: preserve the pin. Keep a custom user label unchanged.
- Empty Home: explain pinning and link to Browse. Do not install sources or seed live pins without user intent.

## 13. Browse and search

### 13.1 Extension directory

- Show installed source connections with icon, name, language, enabled state, favorite state, and unavailable/error status.
- Source-list search filters the local directory.
- Favorites appear first without obscuring the full list.
- Manage opens extension installation/settings.
- No-source state includes a clear install/add source route.

### 13.2 Source discovery

- Render only source-declared feed tabs and supported filters.
- Feeds may include Latest, Popular, Trending, Completed, or source-specific names. Do not hardcode these as universal capabilities.
- Support paginated listings with opaque cursors.
- Remember source-local search/filter/sort preferences, but preserve explicit saved pin parameters when opening a pin.
- Show source-specific login/setup requirements before repeatedly failing requests.
- Unsupported optional features disappear gracefully; a search-only source still works.
- Source manga details show source metadata and original chapters, plus add/link/copy routes.

### 13.3 Global search

- Search all enabled installed connections that declare search capability.
- Suggested input debounce: 350 ms.
- Start a generation/token for every committed query. Cancel old tasks and reject late responses from older generations.
- Limit concurrency; initial default is three simultaneous source searches, still subject to per-source limits.
- Render groups progressively as each source responds.
- Show a group's loading, empty, success, login-required, throttled, or failed state independently.
- Allow source and language selection, cancellation, and per-source retry.
- Results from separate sources stay separate unless the user explicitly links them.
- A similar title across sources is not automatically one result/card with merged identity.
- Do not exhaust every source's pagination on the first query. Fetch a preview page, then View All within a source.
- Mark an exact linked listing In Library using stable identity.
- Store recent searches locally only if implementing a visible clear-history control; this is optional, not required for v1.

## 14. Refresh and reconciliation

### 14.1 Job structure

Refresh can target a listing, entry, category, or entire library. Deduplicate requests when several entries reference one listing. Snapshot source data first; reconcile against each entry's follow/exclusion rules separately.

1. Capture current listing and extension configuration/version.
2. Fetch metadata and every required chapter page using bounded pagination.
3. Validate the response and accumulate a temporary snapshot.
4. If fetching is incomplete, update only safe partial data and mark the snapshot incomplete.
5. Only a validated complete snapshot may be used to infer source removals.
6. Reconcile using stable source chapter identities.
7. Apply new records, availability changes, and eligible entry additions transactionally.
8. Emit deduplicated Library Update events for genuinely new followed chapters.
9. Save last success/failure separately.

### 14.2 Reconciliation rules

- Update shared source snapshots, not personal overrides.
- Existing source chapter ID: refresh metadata and retain references/progress.
- New chapter in a Follow New Chapters link: add if not excluded; handle uncertain duplicates as candidates.
- New chapter in a Selected Chapters Only link: do not insert.
- Excluded exact source chapter: skip until explicit restoration.
- Missing chapter after complete snapshot: mark unavailable, retain local data and downloads.
- Empty response after timeout, authentication failure, parse error, or partial pagination: never treat the whole source as deleted.
- 403/challenge, 404, rate limit, and network loss have different error states.
- A URL change under the same stable ID updates locators and invalidates appropriate caches, not progress.
- An identifier-scheme change requires declared migration/alias handling or a user repair workflow; do not fuzzy-match destructively.
- Source metadata changes cannot reorder a manually ordered entry.
- Changed source numbering may affect automatically ordered entries, but must not override explicitly edited local numbers. Show material order changes where useful.
- New releases with the same number do not automatically replace preferred variants.
- Do not repeatedly notify the same discovery on every refresh or app restart.
- In-app update history can be shown in Home without adding a sixth tab.

### 14.3 Scheduling

Manual refresh is required and reliable. Launch/foreground refresh is recommended when stale. Background refresh is best-effort; do not promise an exact interval or guaranteed work while the app is terminated. Apple provides background scheduling APIs, but scheduling and permitted execution must be verified against the deployment target. See [Background Tasks](https://developer.apple.com/documentation/backgroundtasks).

Use one shared request coordinator for search, refresh, reading, and downloads so separate features cannot each exceed the source's budget. Give active reader requests priority over nonurgent discovery work.

## 15. Reader implementation

### 15.1 Modes

Required modes:

- Right-to-left horizontal paging for manga.
- Left-to-right horizontal paging for comics.
- Continuous vertical scrolling for webtoons.

Use SwiftUI where practical; use a UIKit-backed paging/scrolling/zoom view when needed for robust gesture coordination and memory handling. Decide based on a reader spike, not on an obligation to implement every interaction in pure SwiftUI.

### 15.2 Reader context

Resolve these separately:

- Current physical source chapter and its page manifest.
- Current personal entry/slot when present.
- Canonical Next/Previous chapter resolver for that context.
- Effective preferences: per-entry override → global setting → default.
- Available verified local download rendition.
- Saved physical progress and any logical completion override.

Direct Browse reading follows that listing's source sequence. Personal-entry reading follows the combined entry sequence. History restores its valid remembered context. Never accidentally switch to the source sequence after finishing an imported chapter.

### 15.3 Controls and gestures

- Tap center to show/hide controls.
- Optional tap-to-navigate with configurable zones respecting reading direction.
- Swipe paging, pinch zoom, double-tap zoom, and an explicit page jump control.
- Fit width/fit screen preferences where suitable to the current mode.
- Source label in chapter information, especially after a cross-source transition.
- Page counter, slider or jump sheet, chapter list, mode controls, and close/back.
- Orientation preference without fighting system rotation or invoking private APIs.
- In-reader brightness controls should restore the previous screen brightness on exit if they changed device brightness.
- Zoomed-page panning should take precedence over page navigation until a clear edge gesture/action occurs.
- Do not reverse vertical scrolling when right-to-left mode is selected elsewhere.
- Disable unnecessary animations with Reduce Motion.

### 15.4 Loading and memory

- Resolve ordered pages through the actual chapter's source.
- Prefer a complete verified local download when available.
- Decode/downsample to the display's needs; retain higher resolution only when zoom requires it.
- Keep a bounded neighborhood of decoded images in memory.
- Initially prefetch approximately two pages; measure and adjust by image size and memory pressure.
- Very tall images need tiling/downsampling so one webtoon page does not exhaust memory.
- Cancel requests when leaving a chapter or changing to another source.
- A page failure gets a page-level retry, preserving already loaded pages and position.
- Treat unsupported formats and corrupt files as recoverable errors with useful messages.
- Do not evaluate all pages or images synchronously on the main thread.
- If a source returns expiring resources, re-resolve them on expiry/auth failure while preserving the chapter's stable identity.

### 15.5 Chapter boundaries

- Offer Next/Previous from controls and a chapter-end transition.
- Show a short transition naming the next chapter and source when the source changes.
- Failure to load the next preferred chapter presents Retry, Choose Alternative if available, and explicit Skip.
- Do not silently skip unavailable/unread chapters.
- Reaching the end of the collection shows a calm caught-up state with Refresh and Return to Entry.
- Page ordering inside a chapter is extension-defined and separate from chapter ordering within the collection.

## 16. Downloads and file storage

### 16.1 Queue

Support individual and multi-select chapter downloads. Queue states: queued, resolving, downloading, paused, completed, failed, and cancelled.

- Persist jobs so interrupted work can recover on app relaunch.
- Initial concurrency: at most two active chapters, with page request counts bounded by source policy.
- Reader traffic has priority.
- Pause/cancel stops future work and cancels safely cancellable requests.
- Respect Wi-Fi-only settings; explain when a queue is waiting for Wi-Fi.
- Retry transient failures with bounded backoff. Do not retry permanent failures indefinitely.
- Surface storage-full failures with the option to free space and resume.
- Progress reports known pages/bytes honestly; do not fabricate a precise percentage before a page count is known.
- Prevent duplicate jobs for the same chapter/rendition unless an explicit redownload is requested.

### 16.2 Manifests and completeness

A downloaded chapter contains an ordered page manifest with stable local filenames, page identity/index, MIME type, byte count, optional checksum, and page dimensions where known.

- Write into a staging directory.
- Validate files and expected page count before marking complete.
- Promote the manifest/directory atomically where possible.
- A metadata entry or partially downloaded folder is not a completed download.
- On restart reconcile incomplete jobs and files instead of deleting everything.
- Redownload stages a replacement and retains the last complete copy until success.
- Quality/source-settings changes create a rendition mismatch; never silently overwrite one rendition with another under the same key.
- Retain enough local metadata to read after extension uninstall or website removal.

### 16.3 Storage classes

| Storage | Contents | Clear cache effect |
| --- | --- | --- |
| Database / Application Support | Library, progress, identities, pins, clipboard | Preserve |
| Permanent custom assets | User-selected manga/chapter covers | Preserve |
| Downloads | Complete user-requested chapter pages and manifests | Preserve |
| Temporary cache | Re-fetchable covers, feed responses, transient page cache | Delete eligible files |
| Staging | Incomplete downloads/imports/updates | Manage per job, not blind cache deletion |
| Secure storage | Credentials and sessions where applicable | Separate explicit sign-out behavior |

Store user-requested offline files outside a purgeable cache location. Mark re-downloadable content for appropriate backup exclusion where supported. Do not imply that this substitutes for the app's user-facing backup feature.

Shared downloads are reference-aware. Removing one entry or variant does not delete a file still used elsewhere. Deleting a download removes files without deleting the source chapter, membership, or progress.

### 16.4 iOS background limits

Do not promise continuous arbitrary JavaScript or network coordination after suspension. Background URLSession transfers, if used, must be compatible with the already-resolved authenticated request and restoration model. Validate on device. Otherwise persist work and resume when execution is available. Manual downloads must work correctly in the foreground first.

## 17. Extension SDK and contract

### 17.1 Goals

- Independent source maintenance without rewriting app screens.
- One normalized, versioned contract for discovery, search, manga, chapters, and pages.
- Stable IDs for user data retention.
- Explicit capabilities and settings.
- Source-specific code owns fetching/parsing logic; the app owns state, navigation, storage, and permissions.
- Compatibility with Mihon/Aidoku/Suwatte/Paperback extension binaries is not a first-version requirement. Use our own SDK.

Suwatte's [source architecture](https://suwatte.mantton.com/developers/introduction/) provides a useful reference for TypeScript adapters running on-device. Our proposed contract below is independently defined; do not assume Suwatte APIs are present in this app.

### 17.2 Package contents

- Manifest JSON.
- Compiled JavaScript bundle in the module format actually supported by the runtime.
- Optional icon and small static parser assets.
- Signed package metadata binding identity, version, compatibility, permissions, and content digest.
- Development-only source maps and fixtures kept out of normal release packages unless intentionally supported.

Proposed manifest fields:

| Field | Meaning |
| --- | --- |
| `id` | Stable publisher-qualified extension identity |
| `name`, `description`, `icon` | User-facing information |
| `version` | Semantic-version string; compare as SemVer, never a floating number |
| `contractVersion` | Required host API contract version/range |
| `minimumAppVersion` | Minimum compatible app build/version |
| `publisherID`, `keyID` | Authenticated maintainer identity |
| `website` | Canonical source website |
| `languages` | Supported language tags |
| `contentRating` | Metadata for user-visible content preferences |
| `domains` | Exact permitted hosts and deliberately scoped subdomain patterns |
| `capabilities` | Search/discovery/filters/settings/auth/chapters/pages/download support |
| `settingsSchemaVersion` | Migration identity for source preferences |
| `entrypoint` | Bundle entry resource |
| `requestPolicy` | Conservative source rate/concurrency hints bounded by host rules |

Actual live source domain lists must be researched per source. Do not fill them with made-up hosts from this plan.

### 17.3 Proposed adapter methods

These are our intended interface names, not pre-existing framework APIs.

| Method | Input | Output |
| --- | --- | --- |
| `getFeeds` | source settings/context | Feed descriptors with stable IDs |
| `getFeedPage` | feed ID, filters, sort, cursor | Paginated manga summaries |
| `getSearchFilters` | settings/context | Declarative filter and sort definitions |
| `search` | query, filters, sort, cursor | Paginated manga summaries |
| `getMangaDetails` | stable external manga ID | Normalized metadata and canonical URL |
| `getChapterPage` | manga ID, cursor | Paginated normalized chapter records |
| `getChapterPages` | manga ID, chapter ID, rendition settings | Ordered page resource descriptors |
| `getSettingsSchema` | schema/context | Declarative nonsecret and secret-input definitions |
| `getAuthenticationStatus` | host-provided session context | Ready/login-required/expired state |
| `migrateSettings` | old version + safe stored settings | Validated new settings, when needed |
| `migrateIdentity` | old known identity scheme | Explicit mapping candidates, when supported |

Only methods required by the declared capabilities must exist. Installing an adapter with missing declared required methods fails validation. A search-only adapter may omit feed methods. Reader-capable adapters must supply chapter/page resolution.

### 17.4 Standard data contracts

`MangaSummary`: external manga ID, title, optional alternative titles, cover descriptor, optional publication status, and canonical URL.

`MangaDetails`: summary fields plus description, author/artist arrays, genres/tags, supported languages, optional metadata revision, and clearly typed optional fields.

`ChapterRecord`: external chapter ID, original title, number as exact string or null, volume/part fields where supplied, source ordinal, release date with parsing status, language, group names, optional thumbnail, canonical URL, and content revision if available.

`PageResource`: ordered page key/index, resource URL or supported host resource descriptor, required allowed request headers, optional expiry, dimensions, MIME hint, and rendition identity. Do not accept arbitrary file paths as resources.

`PaginatedResult<T>`: items, opaque next cursor or null, optional total count, and explicit snapshot-completeness semantics. An empty list is different from an error. Detect repeated cursors and enforce page/item caps.

`FilterDefinition`: stable ID, label, type (single choice, multiple choice, boolean, text, range if supported), valid values, default, and optional dependencies. The app builds native controls; sources do not inject arbitrary UI views.

`FeedDescriptor`: stable ID, label, supported filters/sorts, pin support, default parameters, and optional explanatory text.

Use bounded JSON-safe values over the bridge. Define maximum string lengths, list sizes, response bytes, and nesting depth in host configuration; reject malformed or oversized results with a typed error.

### 17.5 Host API

Provide narrowly scoped helpers:

- HTTP requests through the app's network coordinator.
- HTML parsing/CSS selection and JSON parsing using documented helper semantics.
- URL resolution/encoding utilities.
- Source-specific nonsecret settings and small key/value storage.
- Access to that connection's own session through opaque handles, without exporting unrelated secrets.
- Redacted diagnostics/logging with source attribution.
- Cancellation checks and a request context identifier.

Do not assume JavaScriptCore has a browser DOM, fetch, Node modules, filesystem APIs, or timers. Explicitly implement only the required helpers. Bundle dependencies needed by source code, and reject unsupported runtime imports during build validation.

### 17.6 Runtime bridge and feasibility gate

Start with JavaScriptCore behind an `ExtensionRuntime` protocol. Before building many adapters, prove:

1. Bundle loading and contract validation.
2. Async host HTTP requests and Promise/result delivery.
3. Per-call correlation IDs so responses cannot resolve the wrong request.
4. Proper conversion and validation of arguments/results.
5. Font/UI work never occurs in the runtime; extension execution cannot block the main actor.
6. Per-runtime execution isolation and correct confinement of JavaScript runtime objects.
7. Exception capture, cancellation propagation, and stale-result rejection.
8. Recovery after a source throws, times out, or returns oversized data.
9. Correct image request headers/session handling through the host.
10. Source settings/account isolation.

Important implementation distinction: timing out a Swift task waiting for a JavaScript result does not necessarily interrupt synchronous JavaScript execution. A JavaScriptCore context is not by itself a security boundary for arbitrary hostile code. Do not claim hard CPU/memory isolation based on an actor, Promise timeout, or catch block.

For v1, accept only our reviewed maintained extensions. Validate the actual public-runtime cancellation/resource-control options. If a required safety/recovery property cannot be delivered with the chosen runtime, document the limitation and evaluate a supported alternative behind the same interface before enabling arbitrary third-party bundles. Do not use private interruption APIs to force an apparent solution.

### 17.7 Network policy and authentication

- HTTPS by default; document any narrowly required exception.
- Validate the destination host before a request and on every redirect.
- Domain suffix matching must be boundary-aware; `example.com.evil.test` is not `example.com`.
- No unrestricted access to localhost, local files, or private network ranges through public source adapters. Future local-server integrations need a separate explicit design.
- Do not allow source code to override host-controlled credentials/security headers arbitrarily.
- Partition cookies, authentication, cache keys, and storage by connection.
- A page image's allowed headers/session must follow it through reader, thumbnail, and download pipelines.
- Use request deadlines and bounded response sizes.
- Honor rate-limit responses, including Retry-After when valid.
- Retry idempotent transient requests with jittered, bounded backoff. Avoid repeating login/submission requests blindly.
- If interactive login is supported, use a controlled WebKit-based flow and synchronize only that source's permitted session data.
- Challenge-protected sources may fail; present login/challenge/not-supported states honestly. Do not promise universal bypass.
- Never log raw cookies, passwords, tokens, or sensitive signed resource URLs.

### 17.8 Package installation and updates

1. Fetch the maintained catalogue using HTTPS.
2. Validate catalogue schema and authenticated publisher metadata.
3. Check semantic version and app/contract compatibility.
4. Download to staging with size limits.
5. Verify package digest and a trusted signature that binds identity/version/permissions/content.
6. Safely extract: reject traversal paths, absolute paths, symlinks that escape staging, excessive expansion, and unexpected executable native artifacts.
7. Validate manifest and required contract exports.
8. Run bounded initialization/health checks.
9. Activate atomically, retaining the last working version.
10. If activation fails, keep the previous version usable and show a recoverable error.

A digest/checksum is not proof of publisher identity. Signing private keys must stay outside the app/repository; verification keys may be bundled. Define a key rotation strategy and prevent untrusted catalogue entries from replacing an installed extension with the same ID.

Permission/domain expansion on update is visible to the user. Do not silently broaden a connection's access. Settings migrations preserve secret references and content identities; failure must not corrupt the old configuration.

Uninstall removes executable package data while retaining library references, progress, custom data, pins, and complete downloads. Warn which entries depend on it, then offer reinstall/relink. Reinstalling the same authenticated identity reconnects retained data.

### 17.9 Extension developer experience

Deliver a starter template and author guide with:

- Required toolchain/setup and supported contract version.
- Manifest and stable ID conventions.
- How to declare feeds, pagination, filters, chapters, images, and authentication.
- Shared helper usage and unsupported APIs.
- How to preserve identifiers when fixing source URL changes.
- How to build and validate a bundle.
- Fixture recording with secret redaction.
- Deterministic parser tests.
- A local development runner and an iOS test harness using the same contract.
- Error examples and diagnostics.
- Version bump, signing, catalogue update, rollback, and maintenance workflow.

The scaffold command should accept a source ID/name and generate compilable code, a manifest, sample tests, and a fixture adapter. Exact command names are an implementation choice; document and verify them rather than inventing unavailable CLI commands in the user handoff.

### 17.10 App distribution decision

Public App Store distribution versus personal/internal installation is unresolved. Continue building the local architecture and bundled fixture adapter while this is settled; do not block all development.

Before committing to the production remote-bundle runtime and release process, assess it against the intended distribution route. Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) address downloaded code in 2.5.2 and qualifying plug-ins in 4.7. JavaScript use alone does not guarantee acceptance. Record the actual decision and any required design constraints; do not claim approval based on another reader app's existence.

## 18. Settings, privacy, and app lock

### 18.1 Required settings groups

- Appearance: system/light/dark, restrained accent choices, cover density, launch tab.
- Home: manage sections.
- Library: categories, sort defaults, refresh preferences, thumbnail preferences.
- Reader: mode, tap navigation/zones, fitting, background, brightness behavior, orientation.
- Extensions: packages, updates, enabled connections, settings/authentication, diagnostics.
- Downloads/storage: queue, Wi-Fi-only, storage totals, delete downloads, clear cache.
- Privacy: app lock, lock delay, app-switcher protection, History controls.
- Backup/restore: export, import, merge/replace.
- About: app version/build, credits/licenses, support/diagnostic export.

### 18.2 Lock behavior

- Use biometric authentication where available, with device authentication fallback.
- Verify that a usable authentication method exists before enabling a lock that could strand the user.
- Default delay can be immediate on backgrounding; offer short delay choices if supported by the product design.
- Lock screens and privacy overlays must not expose manga art or recent activity underneath.
- Handle biometric unavailable, lockout, user cancellation, and interruption as ordinary states.
- Do not maintain a custom insecure plaintext PIN as a shortcut.
- App lock is a UI-access feature, not a promise of a separately encrypted database.
- Protect files according to appropriate iOS data-protection settings and validate how that interacts with intended background transfers.

### 18.3 Privacy defaults

- No mandatory analytics or advertising SDK.
- No upload of library titles, reading history, or custom covers to an application backend.
- Source requests necessarily reveal source activity to that source; keep unrelated library data out of adapter requests.
- Diagnostics exported by the user are redacted and previewable.
- Backup archives may contain private reading metadata; describe their contents in the export screen.

## 19. Backup and restore

### 19.1 Backup contents

Include schema/app format version, export date, stable UUIDs, personal entries, metadata overrides including clear states, custom assets, categories, source references, links/follow policies, slots/variants/preferences, exclusions, manual sequence, physical progress, logical completion overrides, History, Home pins, clipboard, and nonsecret preferences.

Exclude passwords, session cookies, tokens, signing keys, executable extension bundles, temporary cache, and downloaded page files by default. Keep an extension identity/version inventory so restoration can offer compatible reinstallations. Avoid copying unverified executable content from backup into the runtime.

### 19.2 Export

- Capture a consistent database snapshot; do not naïvely copy a live SQLite main file while ignoring its WAL.
- Export portable structured data and referenced permanent custom assets.
- Produce a manifest with counts, byte sizes, hashes, and schema version.
- Validate completeness before presenting the share/save sheet.
- Cancel cleanly and remove incomplete export staging files.
- Export to Files or a share destination chosen by the user.

### 19.3 Import validation

- Check archive size, expansion limits, safe relative paths, schema compatibility, required files, and asset hashes.
- Parse into temporary storage before touching live data.
- Unknown future schema: fail clearly rather than guessing or partially destroying the library.
- Invalid foreign keys/duplicate IDs: report a readable validation failure.
- Present counts of entries, chapters, categories, progress records, and missing sources before applying.
- Show precisely what merge and replace will do.

### 19.4 Merge

- Match app-owned UUIDs first, then exact source identities for shared source records.
- Never merge different personal entries simply because titles match.
- Detect conflicting edits to the same UUID. Prefer existing local data by default or show a conflict policy; do not blindly choose the largest timestamp from another device.
- Reconcile ID aliases before recreating references.
- Deduplicate category/source membership and exact variants without losing manual order.
- Merge History by canonical source chapter, keep the newest open time, then cap at 100.
- Reading progress conflict policy must be explicit; a user may be rereading, so maximum page number is not always correct. Prefer local on conflict in v1 unless the user chooses imported data.
- Validate all invariants before transaction commit.

### 19.5 Replace

- Create a local recovery export first.
- Stage validated data/assets and perform a controlled atomic database replacement/transaction.
- Keep the old library usable if import fails before commit.
- Reconcile asset references before deleting obsolete assets.
- Preserve downloaded files that can still be associated safely; otherwise mark them for user-reviewed cleanup rather than silently deleting all downloads.
- Do not automatically authenticate sources using imported references. Ask for source login as needed.
- After restoration show missing extensions and any unrecoverable optional assets.

## 20. Errors, empty states, and accessibility

### 20.1 Typed errors

Define domain errors rather than showing arbitrary exceptions: offline, timeout, rate limited, authentication required, challenge required, source unavailable, source content removed, parser changed, unsupported capability, incompatible extension, invalid signature, invalid package, storage full, invalid image, corrupt download, backup invalid, stale paste preview, and database migration failure.

Every user-facing error should identify the affected scope, preserve useful content, and offer a sensible next action. Avoid exposing stack traces, internal file paths, raw HTTP payloads, or secrets in normal UI.

### 20.2 Required states per feature

| Feature | States to implement |
| --- | --- |
| Home section | Initial skeleton, populated, empty, stale offline, failed, source missing, feed removed |
| Library | Empty, populated, search-empty, category-empty, selection, recoverable load issue |
| Browse/search | No extensions, loading per source, partial results, empty, cancelled, login required, failed group |
| Manga detail | Cached metadata, loading chapters, empty manual entry, partial source failure, unavailable source |
| Paste | Empty clipboard, valid preview, exact duplicates, ambiguous alternatives, mismatch, stale destination, success/failure |
| Reader | Resolving, page loading, ready, partial page failure, offline complete download, no pages, end of collection |
| Download queue | Waiting, running, paused, Wi-Fi waiting, failed, storage full, complete |
| Backup | Exporting, validating, conflict preview, importing, successful, failed with recovery |
| App lock | Locked, authenticating, unlocked, cancelled, unavailable/lockout |

### 20.3 Accessibility

- VoiceOver labels for covers, chapters, source attribution, unread counts, and download states.
- Never require long press, swipe-only actions, color recognition, or haptics as the only interaction cue.
- Provide visible menus and accessible custom actions for reorder/copy/pin/remove.
- Dynamic Type and long title/language testing.
- Minimum 44-point touch targets even when icon glyphs are smaller.
- Meaningful focus order in sheets and after navigation.
- Adequate contrast in both themes; status differences need text/icon cues.
- Reduce Motion and sensible loading announcements.
- Reader controls remain available to assistive technology; do not trap focus inside zoom/paging gestures.
- Artwork reading remains image-based; do not imply that image pages have accessible text unless real text metadata exists.

## 21. Performance and operational defaults

Treat these as initial engineering budgets to measure, not invented benchmark results.

- Local library browsing should not wait on network calls.
- Keep scrolling and gestures responsive at the device's normal refresh rate.
- Avoid blocking the main thread for database queries, image decoding, parsing, archive work, or extension execution.
- Fixture scale for development: 500 entries, 50,000 source chapter records, large single-title lists, and several linked sources.
- Virtualize chapter lists and image grids. Do not eagerly decode every cover/page.
- Paginate source discovery and cap each global-search preview.
- Suggested initial source budget: two in-flight requests per connection and conservative minimum spacing, overridable downward by source policy. Respect stricter real-source limits.
- Suggested metadata request deadline: 20 seconds; page-image transfer can use a separately bounded policy. Tune against actual sources.
- Bound retries, redirect counts, pagination loops, response bytes, archive expansion, and image dimensions.
- In-memory image budget responds to memory pressure. Cache limits are configurable and enforceable.
- De-duplicate identical concurrent image/metadata requests without crossing authenticated connection boundaries.
- Cancel work when no longer needed, but preserve intentionally queued downloads.
- Cache keys include source connection, content identity, and relevant language/quality/settings scope; never mix authenticated users' resources.
- Use redacted logs with request IDs, duration, source ID, status category, and extension version.
- Provide a developer-only diagnostics view or export to inspect parser/runtime problems.

## 22. Implementation phases and exit criteria

Do these in order unless existing repository work changes dependencies. A phase is complete only when its behavior works, not when its UI files exist.

### Phase 0 — Inspect and record decisions

- Inspect repository, Xcode/SDK, signing configuration, assets, and existing tests.
- Choose/reuse app target, persistence, package management, and minimum OS.
- Apply the confirmed name **Midoku** and record unresolved distribution/source choices.
- Establish semantic colors, typography, and navigation conventions.
- Add this plan and a short progress/decision log to the repository if authorized by the coding task.

**Exit:** app builds/launches in the available iOS environment, or a precise environment blocker is recorded; no fabricated build result.

### Phase 1 — Local foundation and fixture adapters

- Database migrations and core identities.
- Library entries, source listings/chapters, links, slots/variants, progress, exclusions, clipboard, and History.
- Deterministic fixture A with chapters 1–20 and 22–40.
- Deterministic fixture B with chapters 1–40 and distinct page art/source labels.
- Thin native navigation and minimal detail/reader screens.
- Persistence and transaction tests.

**Exit:** data survives restart; exact identities are unique; fixture requests require no internet.

### Phase 2 — Prove the differentiating flow

- Add fixture A's manga.
- Copy B:21, preview, and paste into the personal entry.
- Resolve Next/Previous through A:20 → B:21 → A:22.
- Edit title/cover and a chapter display field.
- Refresh, restart, and confirm retained edits/composition.
- Remove a chapter and verify refresh does not restore it.
- Repeat paste and verify exact duplicate skipping.

**Exit:** automated domain/integration checks and a manual in-app walkthrough prove the core invariants. Do not proceed with a source-owned library architecture if this fails.

### Phase 3 — Extension runtime and SDK spike

- Implement the versioned runtime interface and TypeScript template.
- Async networking bridge, request scoping, parsing helpers, schema validation, capabilities.
- Prove cancellation behavior and explicitly record synchronous-execution limits.
- Package/install/update staging and compatibility checks.
- Fixture adapters running through the real extension interface rather than a UI-only mock bypass.
- Decide the production distribution/runtime constraints.

**Exit:** one fixture bundle executes through the real bridge; malformed/throwing adapters do not corrupt local data; unsupported runtime claims are resolved or documented before expanding scope.

### Phase 4 — Library and chapter curation

- Full library grid/list, local search, category management, sorting/filtering.
- Manga and chapter editing, cover imports, source links.
- Multi-select actions, persistent clipboard, conflicts, alternatives, manual ordering.
- Direct source details with Open Library Entry routing.
- Completion/progress semantics wired consistently.

**Exit:** user-owned data survives all refresh/edit/remove/restart cases; category deletion is non-destructive.

### Phase 5 — Reader and progress

- RTL, LTR, continuous modes.
- Zoom, tap zones, controls, page jump, per-entry overrides.
- Bounded images/prefetch, corrupt/failed page retries.
- Frequent progress saving, content revision handling, chapter boundary behavior.
- History recording and 100-item cap.

**Exit:** all three modes work on device/simulator; combined sequence remains correct; page failure and background/resume do not lose progress.

### Phase 6 — Browse, search, and Home

- Source directory, declared feeds/filters, pagination.
- Global search with cancellation, progressive groups, partial failures.
- Pin descriptors, deduplication, section management, cached feeds.
- Continue Reading and Library Updates.
- At least one real chosen source integrated and verified; use fixtures to maintain two-source deterministic coverage if a second live source is not yet selected.

**Exit:** pinning reopens the same filtered view; slow/failed sources do not block others; old search responses cannot overwrite a newer query.

### Phase 7 — Refresh, source lifecycle, and downloads

- Complete-snapshot reconciliation and follow policies.
- New-chapter events, exclusions, unavailable source states.
- Download queue, permanent manifests, offline reader, recovery, storage UI.
- Update/uninstall/reinstall behavior retaining personal data.
- Bounded rate limiting shared across app features.

**Exit:** airplane-mode reading works for complete downloads; interrupted work recovers; uninstalling a source leaves local collection and downloads intact.

### Phase 8 — Settings, lock, backup, and restore

- Appearance/light/dark, settings persistence, app lock/privacy overlay.
- Cache/download separation.
- Versioned export, import preview, merge/replace, recovery backup.
- Restore missing-source and identity-conflict handling.

**Exit:** a populated mixed-source collection round-trips through export/restore without losing required state; invalid backup leaves existing data usable.

### Phase 9 — Visual polish and release preparation

- Implement supplied visual direction across all functional states.
- Small/large devices, rotation, dark mode, Dynamic Type, VoiceOver.
- Real-source smoke checks, parser fixtures, performance profiling, offline/error cases.
- Dependency licenses, source attribution where required, permission descriptions.
- Complete setup, extension-authoring, backup, and release documentation.
- Validate chosen distribution/signing route and unresolved source decisions.

**Exit:** production checklist passes; no placeholder action is represented as a functioning feature; limitations and unrun tests are disclosed.

## 23. Test strategy

Concentrate tests on state transitions, data retention, contracts, and failure handling. Do not write low-value tests that merely mirror static view structure.

### 23.1 Domain and persistence tests

- Stable identity uniqueness and alias migration.
- Metadata override inheritance/set/clear/reset.
- Exact chapter ordering for 1, 2, 10, 10.5, parts, volumes, and specials.
- Manual order persistence and append policy on refresh.
- Slot/variant invariant enforcement.
- Copy/paste atomicity, conflict resolution, stale preview revalidation.
- Exclusions surviving refresh and explicit restoration.
- Selected-only links never importing unselected chapters.
- Source snapshot updates never overwriting personal metadata.
- History upsert/prune and progress independence.
- Shared source chapter progress without duplicate History when later saved.
- Migration from each supported schema fixture.
- Backup/import referential integrity and rollback on failure.

### 23.2 Extension tests

- Manifest compatibility, valid signature, invalid signature, identity collision.
- Semantic version ordering such as 1.9.0 versus 1.10.0.
- Required method/capability validation.
- Valid and malformed JSON results, missing optional fields, oversized data.
- Stable source IDs through URL changes.
- Pagination end, repeated cursor, partial failure, empty valid response.
- Feed/filter descriptors and saved pin parameters.
- Source isolation, redirect host validation, redacted logs.
- Promise success/rejection and stale request cancellation.
- Source-specific image headers/authentication.
- Adapter exceptions and documented timeout behavior.
- Parser fixtures for the chosen real sources, with no live internet required for ordinary CI tests.

### 23.3 Download and reader tests

- A:20 → B:21 → A:22 in all reader modes.
- Direct Browse sequence versus personal-entry sequence.
- Wrong/missing preferred source never silently substituted.
- Last page visibility marks completion; prefetch alone does not.
- Continuous position restores across a display-size change.
- A later progress write cannot be overwritten by an older in-flight write.
- Network loss mid-chapter preserves loaded pages and position.
- Partial/corrupt download is not marked completed.
- Redownload failure preserves the old complete copy.
- Offline chapter survives source uninstall and cache clear.
- Queue recovers after relaunch and observes Wi-Fi-only state.

### 23.4 UI flows

- Pin filtered source tab → reorder Home → View All retains filters.
- Add manga → edit details/cover → refresh → edits retained.
- Source chapter long press → copy → switch tabs → paste → correct source badge/order.
- Duplicate paste → skip/replace/alternative outcomes.
- Category creation/assignment/deletion leaves entries safe.
- Continue Reading returns to saved physical page.
- History clear leaves progress.
- Dark mode and large text do not clip important controls.
- App lock masks background content and handles cancelled authentication.
- Backup export/import preview/restore presents accurate counts and errors.

### 23.5 Fault injection fixtures

Include fixtures for one slow source, one throwing source, 429 with retry delay, authentication expiry, changed image URL, malformed chapter number, duplicate language release, removed feed, incomplete pagination, chapter disappearance, full disk/write failure simulation, invalid archive, and app restart during a staged operation.

## 24. Product acceptance checklist

- [ ] All five named tabs exist and preserve their relevant navigation state.
- [ ] Home supports live source-feed pins, saved filters, view-all, source navigation, reorder, rename, hide, and delete.
- [ ] Home handles independent loading and source failures.
- [ ] Library supports editable local entries, covers, categories, search, sorting, and filtering.
- [ ] Source metadata refresh does not overwrite local edits or intentional blank overrides.
- [ ] The same personal entry combines source A and source B chapters.
- [ ] Every chapter shows its actual extension/source attribution.
- [ ] Chapter thumbnails have sensible fallbacks without bulk page fetching.
- [ ] Single and multi-select copy work without using the iOS clipboard.
- [ ] Clipboard survives restarts and repeated pasting.
- [ ] Paste preview identifies duplicates, origin, destination, and placement.
- [ ] Exact repeated paste does not duplicate chapters.
- [ ] Confirmed alternatives have one preferred release for sequential reading.
- [ ] Manual removal is preserved by exclusions across refreshes.
- [ ] Chapter display sorting cannot accidentally reverse reading sequence.
- [ ] Personal and source reading contexts resolve different sequences correctly.
- [ ] All three reading modes work and preserve progress.
- [ ] Reader does not silently skip missing/unavailable chapters.
- [ ] Global search shows progressive independent source results and ignores stale responses.
- [ ] Source tabs/filters are driven by capabilities, not fixed assumptions.
- [ ] History records opened chapters from anywhere and retains at most 100 distinct source chapters.
- [ ] Clearing/trimming History preserves progress.
- [ ] Downloads are complete/validated before being advertised as offline-ready.
- [ ] Offline reading survives source uninstall and temporary cache clearing.
- [ ] Extension updates preserve identity and recover from failed activation.
- [ ] Custom extension starter, contract, tests, build, signing, and maintenance documentation exist.
- [ ] Light/dark/system appearance works using semantic colors.
- [ ] App lock and app-switcher privacy work on a real supported device.
- [ ] Backup/restore preserves composition, edits, custom covers, exclusions, order, progress, categories, and pins.
- [ ] Invalid backup/import and migration failures do not silently destroy existing data.
- [ ] Production has no fake working buttons or accidental fixture catalogue.
- [ ] Build/test/release instructions match the actual repository and toolchain.

## 25. Required developer handoff

Deliver the native app source and project, locked dependency configuration, migration history, extension SDK/template, maintained source adapters selected for v1, fixtures/tests, and documentation.

Documentation must explain:

1. How to open, configure, build, and run the app.
2. Supported iOS/Xcode versions actually verified.
3. Where to configure signing and bundle identity without embedding secrets.
4. How local entities, slots, variants, and source identities relate.
5. How to add, test, build, sign, publish, update, and roll back an extension.
6. Which source capabilities/login flows are supported.
7. How data migrations and backup versions work.
8. How to run deterministic tests and optional real-source smoke checks.
9. How to inspect redacted diagnostics and repair a broken source.
10. Remaining limitations, distribution decisions, and any unrun device checks.

## 26. Decisions still open

| Decision | Default while unresolved | When it becomes blocking |
| --- | --- | --- |
| App icon and wordmark | Approved Midoku book icon imported; native system-font wordmark supplied | Validate final release icon presentation |
| Minimum iOS version | iOS 17 planning target | Dependency/toolchain selection |
| Distribution route | Build locally; do not claim App Store eligibility | Production remote extension runtime and release |
| First real sources | MangaDex and Comix selected; implement later after domain/API verification | Real-source acceptance/release |
| iPad-specific layout | Keep layouts adaptive, optimize iPhone first | Declaring polished iPad support |
| Additional repositories | Our maintained repository only | Third-party extension ecosystem |
| Backup encryption | Clearly described local export without a separate custom encryption scheme | If user explicitly requests encrypted portable backups |
| Cloud sync | Deferred | Multi-device synchronization request |

Routine UI details, directory names, conservative queue limits, and implementation mechanics can be chosen without repeatedly asking the user. Record decisions that alter persistent data semantics.

## 27. Reference sources

These references informed the plan. The app's detailed behaviors, entities, and API names above are our proposed specification, not claims that each reference app implements them identically.

- [Mihon categories](https://mihon.app/docs/guides/categories): user-named categories, multiple-category membership, ordering, and update preferences.
- [Mihon library FAQ](https://mihon.app/docs/faq/library): real-world duplicate chapter, update, and identity-change concerns.
- [Paperback pinning discussion](https://github.com/Paperback-iOS/app/issues/889): existing discovery/search sections pinned to Home, as described in its project tracker.
- [Aidoku](https://aidoku.app/) and [Aidoku source SDK](https://github.com/Aidoku/aidoku-rs): configurable source-based reading and source development tooling.
- [Suwatte source architecture](https://suwatte.mantton.com/developers/introduction/), [capabilities](https://suwatte.mantton.com/developers/capabilities/), and [source catalogues](https://suwatte.mantton.com/developers/source-lists/): on-device adapters, optional capabilities, and independently maintained source bundles.
- [GRDB](https://github.com/groue/GRDB.swift): proposed SQLite integration; verify actual APIs and compatibility during implementation.
- [Apple JavaScriptCore](https://developer.apple.com/documentation/javascriptcore): verify runtime and bridge APIs against the installed SDK.
- [Apple Background Tasks](https://developer.apple.com/documentation/backgroundtasks): verify supported background strategies and scheduling behavior.
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): distribution constraints requiring evaluation before release.

## 28. First task for the coding agent

Inspect the repository and report a concise implementation approach. Then build the local domain/persistence foundation and two fixture extensions. Demonstrate the exact missing-Chapter-21 workflow, including refresh and restart persistence, before expanding to the full set of polished screens. Use the phase exit criteria and acceptance checklist to track real completion.
