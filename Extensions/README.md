# Midoku extension author guide

An extension translates a source website/API into Midoku's manga, chapter, and
page data. Write it in TypeScript, compile it to JavaScript, and register the
reviewed bundle with the app. The app provides networking, sessions, verification,
UI, and storage.

This guide describes **contract version 2 as implemented today** (the host also runs legacy version-1 bundles). The product
plan describes a larger future SDK. If they differ, follow the current
[TypeScript SDK](sdk/index.ts) and [Swift contract](../Midoku/Extensions/Core/ExtensionContract.swift).
A [bundled MangaDex adapter](sources/dev.midoku.mangadex/README.md) is available for
testing. Comix remains planned; confirm its canonical domain before implementing it.

## Contents

- [Responsibilities and supported features](#responsibilities-and-supported-features)
- [Create and build an extension](#create-and-build-an-extension)
- [Manifest requirements](#manifest-requirements)
- [Methods and returned data](#methods-and-returned-data)
- [Filters and contract-2 compatibility](#filters-and-contract-2-compatibility)
- [Identity, ordering, and pagination](#identity-ordering-and-pagination)
- [Complete search example](#complete-search-example)
- [Networking and Cloudflare](#networking-and-cloudflare)
- [Runtime limits and unavailable APIs](#runtime-limits-and-unavailable-apis)
- [Test the example](#test-the-example)
- [Connect an extension to the app](#connect-an-extension-to-the-app)
- [Troubleshooting and release checklist](#troubleshooting-and-release-checklist)

## Responsibilities and supported features

| Extension owns | App owns |
| --- | --- |
| Source API paths and response parsing | HTTPS requests and domain/header permissions |
| Mapping source metadata into the SDK types | Cookies, User-Agent, and connection sessions |
| Stable source IDs and pagination cursors | Visible website verification and bounded retry |
| Chapter order and ordered image descriptors | Native screens and source connection management |
| Source-specific parser fixtures and tests | Library composition, user overrides, and reading progress |

The app renders source-defined feed tabs, debounced search, filters, cover grids,
pagination, entry metadata, chapter-language selection, chapter lists, and direct
chapter reading with page navigation and zoom. Covers and pages use the shared
source session and a bounded image cache. Personal-library composition, persistent
reading progress, downloads, and the full planned reader remain separate milestones.

An extension must not write library entries, merge chapters across sources, choose
which source supplies a library slot, or change progress. Midoku owns those choices.
It must not inject UI or depend on a source-name branch in SwiftUI.

Only reviewed app-bundled adapters are currently accepted. There is no remote
extension installer, catalogue URL, package-signing CLI, or automatic update flow.
Mihon, Aidoku, Paperback, and Suwatte extensions cannot be loaded directly.

## Create and build an extension

Use Node 24 or newer and npm. From the repository root:

```sh
cd Extensions
npm ci
npm run create -- dev.publisher.source "Example Source"
```

The command creates exactly these authoring files:

```text
Extensions/
  sources/
    dev.publisher.source/
      manifest.json
      index.ts
```

It refuses to overwrite an existing source. The starter's `search` deliberately
throws until you implement it. Its empty domain list is suitable for offline
fixtures only; add the actual verified API, website, and image hosts you need.
The scaffold does not create parser tests; add those as described below.

After implementing the source:

```sh
npm run typecheck
npm run build
npm test
```

`npm test` already runs typechecking, bundling, and `tests/*.test.mjs`; the first
two commands are useful for checking each stage separately. A passing build does
not prove your parser works: the bundled method still needs to be exercised.

Build output:

```text
Extensions/dist/dev.publisher.source/
  manifest.json
  bundle.js
```

The bundler scans direct child directories under `sources/`, in addition to the
built-in offline fixtures. It produces an ES2020 IIFE exposing
`MidokuExtension.default`. Keep each directory's name equal to its manifest ID,
and use a unique ID: output paths are based on that ID.

Commit source code, manifests, tests, redacted fixtures, and `package-lock.json`.
Do not commit `node_modules/` or `Extensions/dist/`. The build also regenerates
`Midoku/Extensions/Core/BundledExtensionResources.swift` for the reviewed IDs in
`bundled.json`, plus `Midoku/Development/DevelopmentFixtureBundles.swift` and the
existing A/B resources in `Tests/Extensions/Fixtures/`. These embedded resources
are intentionally checked in so Xcode and Swift tests work without Node. Regenerate them through the build; do not hand-edit them.

## Manifest requirements

For the worked search example below, use this `manifest.json`:

```json
{
  "id": "dev.publisher.source",
  "name": "Example Source",
  "version": "0.1.0",
  "contractVersion": 2,
  "domains": ["api.example.com", "img.example.com", "example.com"],
  "capabilities": ["search"]
}
```

These are documentation hosts, not a working manga API. Replace them with researched
source hosts for a real adapter; the example is tested with a fake host offline.

| Field | Current requirement |
| --- | --- |
| `id` | Stable publisher-qualified ID, e.g. `dev.publisher.source`. Must match `^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$`. Do not change it on updates. |
| `name` | Nonblank display name, at most 100 characters. |
| `version` | Numeric `major.minor.patch`, e.g. `0.1.0`. No `v` prefix, leading zeroes, prerelease suffix, or build metadata. |
| `contractVersion` | Use `2` for new adapters. Legacy `1` remains supported; it cannot declare `filters`. |
| `domains` | Up to 32 distinct lowercase host permissions: exact hostnames or explicitly reviewed `*.domain` subdomain scopes. No scheme, path, port, IP literal, or local/private-style suffix such as `.local` or `.test`. Only one leading `*.` is allowed; the remaining root must be a valid multi-label public hostname. |
| `capabilities` | Nonempty list using only `search`, `feeds`, `details`, `chapters`, `pages`, and `filters`. List each once and implement all its required methods. |

Domain permissions do not include subdomains automatically. `example.com` does
not permit `api.example.com`. Include every host used by metadata, redirects,
cover URLs, page URLs, and Referer values. An empty domain list permits no HTTP.
For a source-owned dynamic CDN, a reviewed `*.mangadex.network` permission allows
its descendants (including nested subdomains), not the bare root or lookalike
suffixes. Exact entries retain exact matching. Broad patterns such as `*`,
`*.com`, or `foo*.example.com` are rejected. Syntax validation does not prove
domain ownership; maintainers must review the scope before adding it.

Fields proposed in the plan such as `icon`, `minimumAppVersion`, settings schemas,
request policy, publisher keys, and authentication metadata have no supported
contract behavior. Adding fields to JSON does not enable those features.

## Methods and returned data

Import from `../../sdk/index` in `sources/<id>/index.ts`, and export one default
`defineExtension({ ... })` object. Each method receives `(input, host)` and returns
a Promise. Implement only the methods your source supports and advertise them in
the manifest. An undeclared capability cannot be called through `SourceAdapter`,
even if its method happens to exist in the bundle.

| Capability | Method | Input | Return |
| --- | --- | --- | --- |
| `search` | `search` | `{ query: string, cursor?: string \| null, filters?: FilterValues }` | `Page<MangaSummary>` |
| `filters` | `getSearchFilters` | `{}` | `SearchFilter[]` |
| `feeds` | `getFeeds` | `{}` | `Feed[]` |
| `feeds` | `getFeedPage` | `{ feedID: string, cursor?: string \| null, filters?: FilterValues }` | `Page<MangaSummary>` |
| `details` | `getMangaDetails` | `{ mangaID: string }` | `MangaDetails` |
| `chapters` | `getChapterPage` | `{ mangaID: string, cursor?: string \| null, language?: string \| null }` | `Page<Chapter>` |
| `pages` | `getChapterPages` | `{ mangaID: string, chapterID: string }` | `PageResource[]` |

`feeds` requires both feed methods. A search-only extension is valid. A source
intended for reading must also resolve chapters and page resources; declaring a
capability is a promise that the corresponding method works, not a feature flag
for an unfinished stub.

These are the complete current return types:

```ts
interface Page<T> { items: T[]; nextCursor: string | null }
interface MangaSummary {
    id: string; title: string; coverURL: string | null;
    preferredChapterLanguage?: string | null;
}
interface MangaDetails extends MangaSummary {
    description: string;
    authors?: string[];
    artists?: string[];
    status?: string | null;
    year?: string | null;
    tags?: string[];
    availableLanguages?: FilterOption[];
    defaultChapterLanguage?: string | null;
    webURL?: string | null;
}
interface Feed { id: string; title: string }
interface Chapter {
    id: string;
    title: string;
    number: string | null;
    ordinal: number;
    language: string | null;
    groups?: string[]; // scanlation credits shown in the list and reader
}
interface PageResource { id: string; url: string; headers: Record<string, string> }
```

Return plain JSON-safe objects and arrays. Use explicit `null` for absent nullable
values, `[]` for a genuinely empty collection, and `{}` for no page headers.
Do not return `undefined`, class instances, Map, Set, BigInt, functions, cyclic
objects, NaN, or Infinity. Contract-2 metadata fields above are optional; unknown
fields are not displayed. Supply human-readable language labels in
`availableLanguages`, and pass its stable option ID back to `getChapterPage`.
`preferredChapterLanguage` carries a browse-language choice into entry opening;
it is never part of a manga identity. `webURL` must satisfy manifest permissions.

Concrete results for the methods other than search:

```json
{
  "getFeeds": [{ "id": "latest", "title": "Latest updates" }],
  "getFeedPage": {
    "items": [{ "id": "manga-42", "title": "Example story", "coverURL": null }],
    "nextCursor": null
  },
  "getMangaDetails": {
    "id": "manga-42", "title": "Example story",
    "description": "A source-provided description.", "coverURL": null
  },
  "getChapterPage": {
    "items": [{
      "id": "chapter-201", "title": "An extra chapter", "number": "20.5",
      "ordinal": 21, "language": "en"
    }],
    "nextCursor": null
  },
  "getChapterPages": [{
    "id": "chapter-201:page-1", "url": "https://img.example.com/chapter-201/1.jpg",
    "headers": { "Referer": "https://example.com/" }
  }]
}
```

The wrapper keys above label separate method results; return only the value for
the method being called. Feed IDs must be accepted by `getFeedPage`. The details
ID must equal the requested manga ID. Page resources must be in reading order.

The app rejects missing/duplicate/blank IDs within a returned collection, IDs
longer than 512 characters, blank manga titles, malformed shapes, and disallowed
resource URLs/headers. `ordinal` must decode as a Swift integer; use safe integers.
Authors must additionally validate meaningful chapter/feed titles, languages,
ordering, and source-specific data. The current host does not enforce every one
of these semantic rules.

## Filters and contract-2 compatibility

Declare `filters` and implement `getSearchFilters` to opt into the native filter
sheet. A filter only describes controls; the adapter must translate selections
into actual source parameters for both search and supported feeds.

```ts
type FilterValues = Record<string, string[]>;
interface FilterOption { id: string; title: string }
interface SearchFilter {
    id: string;
    title: string;
    kind: "single" | "multiple";
    options: FilterOption[];
    defaults: string[];
    scopes: ("search" | "feed")[];
    required: boolean;
}
```

For example, a status control can return:

```json
{
  "id": "status", "title": "Publication status", "kind": "multiple",
  "options": [{ "id": "ongoing", "title": "Ongoing" }, { "id": "completed", "title": "Completed" }],
  "defaults": [], "scopes": ["search", "feed"], "required": false
}
```

The corresponding search input is
`{ "query": "Atlas", "cursor": null, "filters": { "status": ["completed"] } }`.
Filter IDs and option IDs are stable opaque strings. Use at most 32 filters,
nonempty titles/options/scopes, unique IDs, and defaults drawn from the options.
Single selection accepts at most one value; required controls have nonempty
defaults and cannot be applied empty. The host validates returned definitions.
Adapters must also validate input values before building a URL.

Omitted filter keys mean adapter defaults. An explicit empty array means no
selection for an optional control, not its defaults. An empty search query must
have documented behavior: MangaDex returns the filtered catalogue. Preserve the
same filters on every paginated request. Sort filters normally have only the
`search` scope: a feed keeps its own ordering. Tag definitions may be fetched via
`host.request`; the app caches them for the open source screen. They must never
include executable UI or credentials. Apply commits the draft, Cancel discards it,
and Reset restores defaults when applied. Selections persist while navigating
within that source screen; they are not persisted across app launches yet.

Version 2 adds the filter capability/input, rich optional metadata, and an optional
chapter-language input. Existing version-1 bundles continue to work with missing
optional data and no filter UI. Update `contractVersion` to `2` before adopting
these features and bump the adapter release version. No connection, manga, or
chapter IDs change during this update.

## Identity, ordering, and pagination

There are three distinct identities:

| Identity | Owner and purpose |
| --- | --- |
| Extension ID | Author chooses it once; identifies the adapter across releases. |
| Connection UUID | App creates/persists it; identifies one configured source/session. Multiple connections can use the same adapter. |
| External manga/chapter ID | Source supplies it, or the adapter derives a stable key; identifies content within that source. |

Midoku scopes manga identity by connection UUID plus external manga ID, and chapter
identity by that manga identity plus external chapter ID. Never generate a new
random ID per request or use a title, signed URL, display order, or chapter number
as a substitute for an existing stable source ID. Preserve IDs when URLs change.
If a source only has URL paths, document a stable path-derived identity scheme;
do not include expiring query parameters or invent an identity migration API.

Chapter numbers are exact display strings, including `"20.5"` or `null`; do not
convert them to floating-point identities. Different releases can share a number.
Use `ordinal` for source sequence, consistently across pagination. Prefer increasing
reading order and do not reset ordinals to zero on every page. The app's library
composition rules decide how that sequence is used alongside other sources.

For paginated methods, treat an absent or null input cursor as the first page.
Return one bounded page and an opaque `nextCursor`, or `null` when complete. Preserve
any source pagination state in the cursor, not module globals. Validate cursor
contents before using them in a request; do not let a cursor choose arbitrary hosts.

Do not return the same continuation token indefinitely or crawl the entire source
inside one method. Avoid duplicate items across pages when the API permits it.
The bridge validates each returned page. Native browse/chapter pagination drops
duplicate IDs across moving pages and rejects repeated continuation tokens. Empty
filtered pages may still carry a next cursor. A changed query/filter/feed/language
starts a new sequence; late responses from the previous sequence are discarded.

## Complete search example

Replace the scaffold's `index.ts` with the following. It expects an illustrative
API response `{ results: [{ key, name, cover }], next }`. It demonstrates URL
encoding, runtime schema validation, stable IDs, and pagination without relying
on browser globals. It is not an implementation of a real source.

```ts
import { defineExtension, getJSON, type MangaSummary } from "../../sdk/index";

function record(value: unknown): Record<string, unknown> {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
        throw new Error("Expected an object");
    }
    return value as Record<string, unknown>;
}

function requiredText(value: unknown): string {
    if (typeof value !== "string" || !value.trim()) {
        throw new Error("Expected nonempty text");
    }
    return value;
}

export default defineExtension({
    async search({ query, cursor }, host) {
        const continuation = cursor == null ? null : requiredText(cursor);
        const url = "https://api.example.com/search?q=" + encodeURIComponent(query)
            + (continuation === null ? "" : "&cursor=" + encodeURIComponent(continuation));
        const payload = record(await getJSON<unknown>(host, url));
        if (!Array.isArray(payload.results)) throw new Error("Missing results array");
        if (payload.results.length > 2000) throw new Error("Too many results");

        const items: MangaSummary[] = payload.results.map(value => {
            const item = record(value);
            const id = requiredText(item.key);
            if (id.length > 512) throw new Error("Oversized manga ID");
            return {
                id,
                title: requiredText(item.name),
                coverURL: item.cover === null ? null : requiredText(item.cover)
            };
        });
        if (new Set(items.map(item => item.id)).size !== items.length) {
            throw new Error("Duplicate manga ID");
        }
        const nextCursor = payload.next === null ? null : requiredText(payload.next);
        if (nextCursor !== null && nextCursor === continuation) {
            throw new Error("Repeated cursor");
        }
        return { items, nextCursor };
    }
});
```

`getJSON<T>` only parses JSON and applies a TypeScript type assertion; it does not
validate the remote schema. Using `unknown` and validating fields avoids hiding
bad source data. Here a missing `cover` or `next` fails deliberately because the
illustrative API requires explicit nulls. Adapt the parser to the real API's
contract. The app separately validates every normalized cover URL against domains.

Throw on broken schemas, missing required content, and unimplemented paths. Never
catch all errors and return an empty success: that hides outages and parser bugs.
Adapter-thrown messages currently become a generic native `runtimeFailure`; they
are not a custom user-visible error API. Native transport/verification errors
propagate directly out of the bridge, so do not rely on catching them in JavaScript
or branching on non-2xx `response.status` values.

## Networking and Cloudflare

All adapter HTTP goes through the second method argument:

```ts
const response = await host.request({
    url: "https://api.example.com/catalog",
    headers: { Accept: "application/json", "Accept-Language": "en" }
});
// response: { url: string, status: number, headers: Record<string, string>, body: string }
const parsed: unknown = JSON.parse(response.body);
```

This is a GET-only text-response API. There is no method/body option, binary image
API, or direct `fetch`. The host resolves allowed redirects and returns successful
2xx responses; a 204 body can still be invalid JSON, so select parsing appropriately.
Headers from the native transport are lowercased. Set-Cookie, Set-Cookie2,
Authorization, and Proxy-Authorization are removed before JavaScript sees them.

Requests and returned image URLs must be absolute HTTPS URLs with no embedded
username/password, on a declared exact host or within an explicitly declared
subdomain scope, using the default port or 443.
Only `Accept`, `Accept-Language`, and `Referer` may be supplied by adapters, including
page-resource headers. Header names are case-insensitive; case-duplicate keys,
CR/LF values, and values above 2,048 UTF-8 bytes are rejected. A Referer must also
be an allowed HTTPS URL. The host drops an adapter Referer on a redirect to a
different host and selects session headers again for each destination.

Cookies, User-Agent, Authorization, and Host cannot be set by an adapter. Cookie
and User-Agent values come from the connection's WebKit session; the current host
does not provide a source-specific bearer-token authentication API. Do not embed
credentials in source code, manifests, logs, or recorded fixtures.

### Verification flow

No extension-level Cloudflare flag, solver, retry loop, or cookie storage is needed.
Calling `host.request` participates in the app's shared flow:

1. The app validates permissions and sends the request with that connection's
   matching cookies and WebKit-derived User-Agent.
2. It detects `cf-mitigated: challenge` or its narrow legacy challenge signature.
   Cloudflare documents the header in its
   [challenge-response reference](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/).
3. A foreground call can open a visible verification sheet in the same connection's
   persistent WebKit profile. The user completes the website's challenge and taps
   **Retry request**. Waiting for verification does not consume the idle-JS timeout.
4. The app reloads session cookies and retries the challenged request once. An
   accepted native HTTP response establishes success; a cookie or loaded page alone
   does not. A repeated challenge stops with `verificationFailed`.
5. Background calls return `verificationRequired` without opening UI. Cancellation
   ends the operation. The Swift caller chooses foreground/background mode; the
   adapter cannot override it.

An ordinary 403 is an HTTP error, not automatically a challenge. A 429 produces a
rate-limit error and delays later requests for that connection. Current Retry-After
support handles numeric seconds, clamps to 1–3,600 seconds, and otherwise uses
30 seconds; HTTP-date parsing and automatic general retries are not implemented.

Cloudflare reports limited support for embedded browsers, so the host flow does
not guarantee clearance for every source. See its
[browser support documentation](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/).
Do not add automatic CAPTCHA solvers, import Safari cookies, or claim a source
works based only on finding a clearance cookie. A browser-based fallback transport
is an architectural option, not an existing host method.

Return page URLs and allowed headers from `getChapterPages`; do not download or
base64-encode images through the text bridge. The native cover/direct-reader
pipeline retains the connection context and routes images through the same host.
Its memory cache is scoped by connection, URL, headers and decode size (64 MiB
budget); images are downsampled off the main actor. Metadata is limited to 8 MiB
and native image responses to 32 MiB, collected in bounded URLSession chunks.
Queued metadata takes priority over queued cover/page requests; request spacing
and verification rules apply to both. Permanent downloads are not implemented. Before a protected source ships, test both
metadata and images through the same session on a physical device, including
expired sessions, cancellation, repeated challenges, relaunch, network changes,
and isolation between two connections.

## Runtime limits and unavailable APIs

Each method invocation uses a fresh JavaScriptCore context. Module constants and
pure helpers are fine; mutable globals cannot persist authentication, settings,
caches, or cursors between calls. Keep top-level initialization free of HTTP and
other side effects because registration also evaluates the bundle.

Supported imports are explicit relative `.ts`/`.js` files inside `Extensions/`,
with the suffix optional. Bare npm imports, Node modules, remote modules, JSON
imports, and directory-index resolution are not supported by the current bundler.
An installed npm package is not automatically available inside an adapter.

Use standard ES2020 JavaScript, JSON, Promise, and `encodeURIComponent`. There is
no host-provided DOM, `DOMParser`, CSS selector engine, `fetch`, `URL`,
`URLSearchParams`, `setTimeout`, filesystem, storage, logging API, or settings/auth
schema API. HTML can be fetched as text, but HTML/CSS parsing helpers must be added
and reviewed centrally before an adapter relies on them. Build-time Node scripts
and tests have Node APIs; production adapter code does not.

| Limit | Current default |
| --- | --- |
| Bundle | 2 MiB UTF-8 |
| Method input / queued host-job JSON | 64 KiB each |
| `host.request` calls | 32 per method invocation |
| Active request flow | One per connection, with at least 500 ms spacing between native request starts |
| Redirects | Five per request flow |
| HTTP response body | 8 MiB metadata / 32 MiB native images |
| Encoded host response delivered to JS | 12 MiB |
| Normalized JSON | 4 MiB, with the escaped result envelope also limited to 4 MiB |
| Individual JSON string | 256 KiB UTF-8 |
| JSON arrays / object properties | 2,000 elements / 100 properties |
| JSON structure | Depth at most 24; at most 50,000 visited values |
| Native request / resource timeout | 20 / 30 seconds |
| Idle JS Promise timeout | Five seconds; time awaiting host requests/verification is excluded |

Stay comfortably below byte limits because escaping adds overhead. These limits
are not hard CPU/memory isolation: cancellation and Promise timeouts do not stop
an infinite synchronous JS loop or arbitrary JS allocations. Only reviewed bundles
are accepted. Use bounded parsing and loops; do not spin or implement sleep loops.

## Test the example

Save the following as `Extensions/tests/example-source.test.mjs` after creating
the example source. It runs its compiled bundle with a fake HTTP host, so it makes
no requests to the documentation domains. The source ID must match your scaffold.

```js
import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";

async function load() {
    const url = new URL("../dist/dev.publisher.source/bundle.js", import.meta.url);
    const context = vm.createContext({});
    vm.runInContext(await readFile(url, "utf8"), context, { timeout: 1000 });
    return context.MidokuExtension.default;
}

function mockHost(payload, requests) {
    return {
        async request(request) {
            requests.push(request);
            return { url: request.url, status: 200, headers: {}, body: JSON.stringify(payload) };
        }
    };
}

// Normalize cross-VM objects before strict deep comparisons.
const plain = value => JSON.parse(JSON.stringify(value));

test("example search maps stable IDs and carries an encoded cursor", async () => {
    const adapter = await load();
    const requests = [];
    const result = await adapter.search({ query: "A & B", cursor: null }, mockHost({
        results: [{ key: "manga-42", name: "A & B", cover: null }], next: "page 2"
    }, requests));
    assert.deepEqual(plain(result), {
        items: [{ id: "manga-42", title: "A & B", coverURL: null }], nextCursor: "page 2"
    });
    assert.equal(requests[0].url, "https://api.example.com/search?q=A%20%26%20B");
    assert.equal(requests[0].headers.Accept, "application/json");
    const finalPage = await adapter.search({ query: "A & B", cursor: result.nextCursor },
        mockHost({ results: [], next: null }, requests));
    assert.deepEqual(plain(finalPage), { items: [], nextCursor: null });
    assert.ok(requests[1].url.endsWith("&cursor=page%202"));
});

test("example search rejects malformed data and a repeated cursor", async () => {
    const adapter = await load();
    for (const payload of [
        { results: [{ key: "manga-42", cover: null }], next: null },
        { results: "not an array", next: null },
        { results: [], next: "page 2" }
    ]) {
        await assert.rejects(adapter.search({ query: "story", cursor: "page 2" },
            mockHost(payload, [])));
    }
});
```

Run `npm test` from `Extensions/`. These tests check parsing and request construction;
Node VM tests do not enforce the Swift network policy, invoke real Cloudflare
verification, or prove JavaScriptCore compatibility. The VM evaluation timeout
also does not bound subsequent asynchronous adapter calls.

For a real source, store redacted response fixtures and test normal, empty,
malformed, duplicate-ID, invalid-URL, pagination, and changed-locator cases. Check
all advertised methods, fractional/missing chapter numbers, multiple releases,
page order, and required image Referers. Keep fixtures deterministic and free of
cookies, authorization headers, account data, and sensitive signed URLs.

Then run `swift test` from the repository root and build in Xcode. Existing
[Swift tests](../Tests/Extensions/ExtensionTests.swift) execute bundled fixtures
through the actual runtime and test permissions/verification behavior. To exercise
your adapter there, add reviewed manifest/bundle fixtures under that test target's
`Fixtures/`, register them with `ExtensionRegistry`, and use a mocked
`ExtensionHost`/transport. Running the existing suite alone tests existing fixtures,
not every new source. Use [the documented cache overrides](../docs/progress.md#environment-notes)
if the development environment restricts default compiler/npm cache writes.

## Connect an extension to the app

Building a source into `dist/` alone does **not** select it for the app. MangaDex
is currently selected in `Extensions/bundled.json`. An app maintainer adds another
reviewed adapter as follows:

1. Review the source, permission hosts, manifest, and parser tests.
2. Add its stable ID to `Extensions/bundled.json`. Each entry must refer to a built
   `sources/<id>/` directory with a matching manifest ID. Duplicates and unknown IDs
   fail the build. Creating a source does not automatically add it to this list.
3. Run `npm test` in `Extensions/`. The build generates the reviewed manifest JSON
   and JavaScript text in `Midoku/Extensions/Core/BundledExtensionResources.swift`.
   Commit this generated app resource along with source/tests and the selection list.
4. Build/run the app. `AppExtensionCatalogue.load()` in
   [ExtensionEnvironment.swift](../Midoku/Extensions/Apple/ExtensionEnvironment.swift)
   decodes those resources, and `ExtensionEnvironment.load()` registers them with
   `ExtensionRegistry`. Validation checks compatibility, exports, and methods for
   every declared capability. No source-specific Swift registration code is needed.
5. In **Settings → Extensions**, add the source. The app creates a persistent
   connection UUID. Enable the connection, then use **Browse** to search it.
6. Native features obtain an adapter with
   `try await extensions.adapter(for: connection, interaction: .foreground)` and
   call `SourceAdapter` methods. Background callers pass `.background`.
   Always retain that connection when resolving related resources.

The existing **Settings → Extension Lab** exercises the two built-in A/B fixtures
in Debug builds. It does not automatically discover newly created sources.
Adapters do not need custom tabs, views, database schemas, or source-name checks.

## Troubleshooting and release checklist

| Symptom | Check |
| --- | --- |
| Builds but never appears in Extensions | `dist/` alone is not selection; add its ID to `bundled.json`, regenerate resources, and rebuild the app. |
| Invalid manifest / incompatible contract | Check exact field types, numeric version, contract `1`, hostnames, and capability names. |
| Declared capability missing implementation | Export a default object and every required method; `feeds` needs two. |
| Unsupported method | Advertise the implemented capability. Unimplemented features should remain undeclared. |
| Request outside permissions | Check API, redirect, CDN and Referer hosts, HTTPS/port, and allowed headers. |
| Generic extension error | Check parser exceptions, unavailable globals, missing return values, and schema changes with offline fixtures. JS exception text is not displayed. |
| Invalid response | Check JSON types, nullable fields, unique IDs, matching details ID, nonblank manga titles, and image URLs. |
| Response too large / timeout | Paginate, reduce fan-out, avoid huge strings and pending Promises; check the current limits above. |
| Repeated verification | Test the native retry and full image path; do not add a loop or return empty data. The source may be unsupported. |
| Tests pass but iOS fails | Node mocks do not reproduce JavaScriptCore globals, host permissions, or real sessions. Add Swift integration coverage. |

Before accepting a source:

- Verify its actual domains/API and declare only necessary hosts.
- Preserve stable extension/content IDs and test every declared capability.
- Pass offline parser tests, the shared Swift checks, and an Xcode build.
- Exercise app registration and connection creation on iOS.
- For protected sources, complete the physical-device verification and image/session
  checks above; record failures and untested behavior honestly.
- Bump the numeric release version for parser fixes, document source/API changes,
  and ship the reviewed bundle with the app. Keep the previous reviewed release
  available for rollback; remote automatic updates are not implemented.

Remote packages require an explicit distribution decision, authenticated signing,
compatibility checks, staged activation, rollback, and a stronger runtime trust
boundary. See [the architecture decision](../docs/extension-architecture.md) and
[development progress](../docs/progress.md) before designing those additions.
