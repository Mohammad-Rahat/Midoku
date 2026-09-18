# Writing a Midoku extension

## Toolchain and quick start

Use Node 24 or newer and npm. Dependencies are pinned in `package-lock.json`.

```sh
cd Extensions
npm ci
npm run create -- dev.publisher.source "Source name"
npm test
```

The scaffold creates `sources/dev.publisher.source/manifest.json` and `index.ts`.
It refuses to overwrite an existing directory. Replace the throwing search stub,
declare the verified exact source/CDN hosts, and implement only the capabilities you
advertise. A successful scaffold is not a working production adapter.

`npm run build` bundles every directory under `sources/`, plus the fixtures.
Output is `dist/<extension-id>/manifest.json` and `bundle.js`.
The build also regenerates Debug-only Swift fixture strings and Swift test resources.
Do not edit these generated artifacts manually.

## Contract 1

Import `defineExtension`, data types, and `getJSON` from `../../sdk/index`.
Export one default object. Its methods receive a typed input and the host:

```ts
import { defineExtension, getJSON } from "../../sdk/index";

export default defineExtension({
    async search({ query, cursor }, host) {
        // Build a URL using your verified API's encoding/pagination rules.
        // const result = await getJSON<SourceResponse>(host, url);
        // Validate and map to { items: [{ id, title, coverURL }], nextCursor }.
        throw new Error("Implement the verified source API");
    }
});
```

Methods currently supported:

| Capability | Methods |
| --- | --- |
| search | search |
| feeds | getFeeds, getFeedPage |
| details | getMangaDetails |
| chapters | getChapterPage |
| pages | getChapterPages |

Return explicit `null` for missing optional values, stable source IDs, exact chapter
number strings, and opaque next cursors. Empty successful lists and failures are
different: throw when fetching/parsing fails. Do not merge titles or manufacture
chapter equivalence. The app decides how source chapters enter a personal library.

The first contract intentionally covers the executable foundation. Declarative
filters/settings, login-specific secrets, HTML/CSS parser helpers, non-GET requests,
download streaming, and identity migration are follow-up contract additions. Do not
claim these host APIs exist yet. Introduce and validate them centrally before an
adapter depends on them. MangaDex and Comix must be researched when implementation
starts; Comix's precise canonical domain has not been selected.

## Runtime and HTTP

Bundles use an IIFE with `MidokuExtension.default`, targeting ES2020. The build
supports explicit relative TypeScript/JavaScript imports within `Extensions/`.
Ambient Node packages and unsupported imports fail the build. Add reviewed parser
dependencies through deliberate build/host changes rather than assuming Node APIs.

Each invocation gets a fresh JavaScript context. Keep adapters stateless. There is
no DOM, browser `fetch`, Node filesystem, or timer API. Use `host.request({url, headers})`
for GET requests. The response contains `url`, `status`, `headers`, and a text `body`.
The host validates permissions and redirects, supplies the source connection's
cookies/User-Agent, detects challenges, and handles verification before returning
content. Set-Cookie and authentication headers are withheld from adapter results.

Only Accept, Accept-Language, and an allowed Referer can be supplied by the adapter.
Cookies, User-Agent, Authorization, and Host are host-owned. Page resources carry
permitted headers but retain the same source connection when later loaded.
Do not log secrets or signed image URLs.

Current limits: one active request flow per connection, 500 ms minimum request
spacing, five redirects, 8 MiB HTTP responses, 2 MiB bundles, 4 MiB normalized JSON,
32 host calls per invocation, and bounded JSON depth/item counts. HTTP request and
resource timeouts are 20 and 30 seconds. Idle JavaScript promises time out after
five seconds; time awaiting host requests/interactive verification is excluded.
These limits do not interrupt infinite synchronous JavaScript or bound arbitrary
JavaScript allocations. Only reviewed bundled adapters are accepted.

## Plugging a reviewed adapter into the app

1. Build and run adapter fixtures with `npm test`.
2. Include the reviewed manifest and JavaScript as app resources (or generated Swift
   constants); decode the manifest and load the bundle text.
3. Add a `BundledSourceExtension` to `AppExtensionCatalogue.bundled`.
4. Build the app. The registry validates compatibility and capability exports.
5. Add a source connection from Settings → Extensions. Its UUID persists and owns
   its isolated session. The same extension may have multiple connections.
6. Obtain `SourceAdapter` from `ExtensionEnvironment.adapter(for:interaction:)`.
   Feature code consumes normalized types and never branches on extension names.

Remote catalogues, signing/publishing, staged updates, and rollback are intentionally
not enabled. A checksum alone is not publisher authentication. See the architecture
document for the release gate.

## Tests and maintenance

Record redacted source responses as fixtures. Test normal/empty/malformed responses,
pagination, stable IDs, changed locators, and unsupported capabilities without live
internet. Run `npm test`, `swift test` from the root, and an Xcode build.

For Cloudflare, adapters need no solver code. Use the host's visible verification
flow. Validate successful retries, expired sessions, cancellation, repeated
challenges, image headers, and account separation on a physical device for each
source. A cookie's presence is not proof of success. Do not assume Safari can
transfer its cookies back into Midoku.

Use a new numeric SemVer release for parser changes, preserve the extension ID and
source content IDs, and keep previous reviewed app-bundled versions available for
development rollback. Remote automatic updates will require their own authenticated
activation and rollback workflow.
