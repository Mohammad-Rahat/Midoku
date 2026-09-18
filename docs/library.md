# Personal library and chapter curation

Library entries have their own UUIDs. Source listings and physical chapters keep
connection UUID + external ID identities. A logical slot holds one or more explicitly
chosen releases, with one preferred release. Matching chapter numbers only prompt a
review; they never silently group releases.

## Available flows

- Add a source listing after loading every chapter page, or create an empty entry.
- Search, sort, grid/list display, categories, status/source/publication/unread and
  downloaded filters. Bulk categories, status, read/unread, refresh, download and remove.
- Edit inherited metadata, per-entry reader preferences and normalized custom covers.
- Copy chapters into the persistent internal clipboard; review the destination,
  duplicates, replacement/alternative/separate decisions and insertion position.
- Edit chapter title/number/volume/cover, reorder chapters, switch preferred release,
  remove chapters and restore exclusions. Removed releases stay excluded on refresh.
- Read offline first, then use the preferred source. Previous/Next follow canonical
  entry order across sources; display sorting and filters do not change the sequence.
- Physical positions and completion remain attached to each release. Replacement
  offers an explicit logical-completion carry option, never page-position transfer.
  Completion requires the final image to load and remain displayed (or the continuous
  end marker to be visible) for one second while active.
- Refresh lists fully before marking missing releases unavailable. Keep edits,
  exclusions, alternatives and manual order; append new chapters in manual mode.
  Pasted source links do not follow the entire series. Enabling following establishes
  an explicit current-list baseline and only auto-adds later discoveries.
- Home has Continue reading and library updates; History restores entry context.

## Storage, migration and backups

The v2 snapshot is stored in `library.sqlite`, with a relational identity index and
foreign-key/uniqueness constraints in the same FULL synchronous transaction. Native
SQLite3 supplies the planned transaction guarantees without a new GRDB dependency.
The snapshot remains the canonical model; relational indexes are rebuilt only when
library/source data changes. This deliberately favors a bounded local library over
incremental SQL queries; very large libraries may need more granular writes later.

The existing v1 `app-settings.json` migrates once and is retained unchanged. A corrupt
or unsupported store is never silently reset. Curation is published after durable
commit. Reading/settings writes retain their existing revision-ordered save behavior.

Version 2 `.midoku` backups include entries, links, slots, variants, overrides,
exclusions, custom-cover bytes, clipboard, completion and progress alongside existing
settings. Version 1 imports remain supported. References and image hashes validate
before restore. Merge maps shared source identities and same-name categories while
keeping existing local entries. Replace and Merge first create a mandatory recovery
archive. Offline page files and connection-scoped sessions stay independent.

Current limits: 5,000 entries, 100,000 remembered chapters, 5,000 clipboard items,
1 MiB per normalized cover and 32 MiB total backup. Covers import through Photos or
Files with a fit preview; a crop editor is not included. Source references are kept
when following is stopped. Fine-grained source unlinking/variant deletion, background
OS refresh scheduling, global cross-source search, reader prefetch and tracker/cloud
features remain separate work. No new live source adapter was added in this change.

## Verification

Domain tests cover A1–20/A22–50 + B21 composition and SQLite restart, selected-only
refresh, explicit alternatives/replacements, separate physical progress, exclusions,
local overrides, manual order, stale-preview rejection, baseline following, decimal
ordering, identity-remapping merges, SQLite rollback, legacy migration and v1 backups.
The Actions workflow runs native Swift tests, archives an unsigned device IPA and
captures Debug simulator Library/Entry/Settings screens using an isolated preview
store. The Release app excludes preview fixtures. Device installation and real-source
network behavior require subsequent device verification.
