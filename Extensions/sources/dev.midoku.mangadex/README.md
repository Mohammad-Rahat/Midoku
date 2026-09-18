# MangaDex for Midoku

Bundled testing adapter: `dev.midoku.mangadex`, release `0.2.0`, contract 2.
Implemented in TypeScript against Midoku's SDK; it does not load Aidoku binaries.

## Try it

Open/build Midoku in Xcode, then go to **Settings → Extensions → MangaDex → Add**.
Open **Browse → MangaDex** and enter a title, such as `Yotsuba`.
The app saves the connection and keeps its session isolated from other connections.
Browse opens Latest updates, with Popular, Recently added, and Search alongside it.
The visible search field searches after a short typing pause; Return submits
immediately. Tap Filters to change a draft, then Apply; Cancel discards changes
and Reset restores the defaults when applied. Search and feed results have Load
more, tappable covers, and entry navigation. Feed tabs retain their own ordering.

An entry shows its description, author/artist, status, year, tags, source link,
chapter-language selector, scanlation credits, and paginated chapter list. A
chapter opens real pages with Previous/Next, a page picker, pinch zoom and visible
zoom controls. Returning preserves the query, results, chapter language and scroll.
Direct source reading currently does not save reading progress or create personal
library entries. Downloads, library composition and the full planned reader modes
remain separate app milestones.

MangaDex is included in `Extensions/bundled.json`. Run `npm run build` inside
`Extensions/` after modifying the source/manifest; this regenerates
`Midoku/Extensions/Core/BundledExtensionResources.swift`. That small generated Swift
resource is checked in so an Xcode checkout builds without Node. `node_modules/`
and `dist/` remain ignored.

## Current behavior

| Operation | Implementation |
| --- | --- |
| Search | Public `/manga` endpoint; encoded title, selected chapter language/filters, covers, 20 results per page; blank title browses the filtered catalogue |
| Feeds | Latest updates, popular, recently added using supported manga ordering parameters |
| Filters | Sort, chapter language, publication status, demographic, original language, content rating, included/excluded tags with all/any matching; tags from `/manga/tag` |
| Details | `/manga/{id}`; title, description, cover, author/artist, status/year, tags, labelled available languages and source URL; stable MangaDex UUID |
| Chapters | `/manga/{id}/feed`; selected language, scanlation group names, 100 records per page; volume/chapter ascending, creation time tie-breaker |
| Page descriptors | Verify chapter parent via `/chapter/{id}`, then `/at-home/server/{id}?forcePort443=true`; original-quality images in API order |

Latest updates follows MangaDex's manga-level upload ordering; the language filter
requires available chapters in that language.

Defaults are English chapter translations, English-preferred titles/descriptions
with deterministic language fallbacks, and `safe`/`suggestive` content ratings.
Filters can change language and ratings; the selected browse language carries
into entry opening. Changes survive navigation inside the source, but are not
saved across app launches. There is no MangaDex login/library sync, alternate-cover
picker, or data-saver preference yet.

Chapter numbers remain strings, including fractional numbers; separate releases
keep distinct chapter UUIDs even if their numbers match. External-link, unavailable,
empty, and chapters outside the selected language are excluded. Filtering does not reset pagination
or ordinals. Ordinals reflect positions in the source feed, not persistent IDs;
new source uploads can change them. Collection pagination stops at MangaDex's
10,000-result window, so very large feeds may require future date-window support.
Returned page URLs may expire: resolve them again when opening a chapter rather
than using the URL as its identity.

## Networking and permissions

Adapter JSON requests use `host.request`. Cover and reader image bytes use the
same native coordinator and connection session. The transport receives bounded
chunks, prioritizes queued metadata over queued images, and uses a 64 MiB memory
image cache keyed by connection/URL/headers/decode size. Metadata and image body
limits are 8 MiB and 32 MiB respectively. There is no disk cache/download store yet.

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
request spacing, checks all seven methods, and downloads one page image only into
memory. It logs counts/title, not cookies, CDN tokens, or page URLs. It uses a Node
test host; simulator/device verification is still required for native sessions.
Do not repeatedly rerun it against a rate-limited or blocked source.

From the repository root, run `swift test`, then build in Xcode. The Swift suite
runs the same embedded production bundle through JavaScriptCore, validates DTO
mapping, and checks CDN permission boundaries. See `Tests/Extensions/MangaDexTests.swift`
and the synthetic shared fixtures in `Tests/Extensions/Fixtures/mangadex/`.
The Node parser tests are in `Extensions/tests/mangadex.test.mjs`.

## References and provenance

API schema rechecked on 2026-09-19 (5.13.1); original Aidoku reference checked 2026-09-18:

- [Official API documentation](https://api.mangadex.org/docs/),
  [OpenAPI schema](https://api.mangadex.org/docs/static/api.yaml), and
  [limitations](https://api.mangadex.org/docs/2-limitations/).
- [Aidoku Community MangaDex source](https://github.com/Aidoku-Community/sources/tree/dd88f0a95157abd9041c5092fa41b5bdff146b52/sources/multi.mangadex)
  at revision `dd88f0a95157abd9041c5092fa41b5bdff146b52`: reference for endpoint
  selection, covers, external chapter handling, and at-home image resolution.

Midoku's TypeScript implementation was written for its own contract. No Aidoku
Rust code, icon, account-auth implementation, or binaries are embedded. Synthetic
fixtures contain invented IDs/titles and API-shaped metadata, not chapter content.
