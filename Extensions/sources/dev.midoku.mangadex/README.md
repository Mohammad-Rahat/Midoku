# MangaDex for Midoku

Bundled testing adapter: `dev.midoku.mangadex`, release `0.1.0`, contract 1.
Implemented in TypeScript against Midoku's SDK; it does not load Aidoku binaries.

## Try it

Open/build Midoku in Xcode, then go to **Settings → Extensions → MangaDex → Add**.
Open **Browse → MangaDex** and enter a title, such as `Yotsuba`.
The app saves the connection and keeps its session isolated from other connections.
The current Browse screen displays the first page of search titles. Reader,
metadata-detail, feed, and load-more UI are separate app milestones; all six adapter
methods are available through `SourceAdapter` and covered by tests.

MangaDex is included in `Extensions/bundled.json`. Run `npm run build` inside
`Extensions/` after modifying the source/manifest; this regenerates
`Midoku/Extensions/Core/BundledExtensionResources.swift`. That small generated Swift
resource is checked in so an Xcode checkout builds without Node. `node_modules/`
and `dist/` remain ignored.

## Current behavior

| Operation | Implementation |
| --- | --- |
| Search | Public `/manga` endpoint; encoded title, English chapter availability, cover relationships, 20 results per API page |
| Feeds | Latest updates, popular, recently added using supported manga ordering parameters |
| Details | `/manga/{id}`; title, description, cover; stable MangaDex UUID |
| Chapters | `/manga/{id}/feed`; 100 records per page; volume/chapter ascending, creation time tie-breaker |
| Page descriptors | Verify chapter parent via `/chapter/{id}`, then `/at-home/server/{id}?forcePort443=true`; original-quality images in API order |

Defaults are English chapter translations, English-preferred titles/descriptions
with deterministic language fallbacks, and `safe`/`suggestive` content ratings.
There is no settings UI, MangaDex login/library sync, alternate-cover picker, or
data-saver preference yet. Do not advertise these as implemented capabilities.

Chapter numbers remain strings, including fractional numbers; separate releases
keep distinct chapter UUIDs even if their numbers match. External-link, unavailable,
empty, and non-English chapters are excluded. Filtering does not reset pagination
or ordinals. Ordinals reflect positions in the source feed, not persistent IDs;
new source uploads can change them. Collection pagination stops at MangaDex's
10,000-result window, so very large feeds may require future date-window support.
Returned page URLs may expire: resolve them again when opening a chapter rather
than using the URL as its identity.

## Networking and permissions

All production requests use `host.request`, including JSON requests that resolve
images. Page methods return descriptors; the unfinished reader/download pipelines
must use the same native connection when loading them.

The manifest grants exact access to `api.mangadex.org`, `mangadex.org`, and
`uploads.mangadex.org`, plus reviewed subdomains of `mangadex.network` for the
API-assigned image server. `*.mangadex.network` does not permit the bare domain,
lookalike suffixes, unrelated hosts, HTTP, credentials in URLs, or non-443 ports.
The adapter validates image bases and path segments; the native host independently
validates every returned URL and header.

MangaDex's API assigns CDN hosts dynamically, sometimes with a path token. Forcing
port 443 keeps descriptors compatible with Midoku's HTTPS policy. Do not pin a
single observed image-server name, rewrite the returned CDN to a guessed host, or
expand permissions to arbitrary hosts.

The app controls User-Agent, cookie storage, rate limiting, and interactive
Cloudflare verification. The adapter supplies only Accept and Referer. A live API
response or successful image fetch does not prove Cloudflare clearance on iOS.
No automated solver, login bypass, or per-extension cookie cache is included.

## Verification

From `Extensions/`:

```sh
npm ci
npm test
# Optional: makes a small number of actual API/image requests; excluded from offline tests.
npm run test:live:mangadex
# Optional alternate search title:
npm run test:live:mangadex -- "Yotsuba"
```

The live check stops on errors/challenges, bounds the request count, observes
request spacing, checks all six methods, and downloads one page image only into
memory. It logs counts/title, not cookies, CDN tokens, or page URLs. It uses a Node
test host; simulator/device verification is still required for native sessions.
Do not repeatedly rerun it against a rate-limited or blocked source.

From the repository root, run `swift test`, then build in Xcode. The Swift suite
runs the same embedded production bundle through JavaScriptCore, validates DTO
mapping, and checks CDN permission boundaries. See `Tests/Extensions/MangaDexTests.swift`
and the synthetic shared fixtures in `Tests/Extensions/Fixtures/mangadex/`.
The Node parser tests are in `Extensions/tests/mangadex.test.mjs`.

## References and provenance

Checked on 2026-09-18:

- [Official API documentation](https://api.mangadex.org/docs/),
  [OpenAPI schema](https://api.mangadex.org/docs/static/api.yaml), and
  [limitations](https://api.mangadex.org/docs/2-limitations/).
- [Aidoku Community MangaDex source](https://github.com/Aidoku-Community/sources/tree/dd88f0a95157abd9041c5092fa41b5bdff146b52/sources/multi.mangadex)
  at revision `dd88f0a95157abd9041c5092fa41b5bdff146b52`: reference for endpoint
  selection, covers, external chapter handling, and at-home image resolution.

Midoku's TypeScript implementation was written for its own contract. No Aidoku
Rust code, icon, account-auth implementation, or binaries are embedded. Synthetic
fixtures contain invented IDs/titles and API-shaped metadata, not chapter content.
