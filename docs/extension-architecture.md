# Extension architecture decision

Status: accepted for the development foundation, 2026-09-18.

The user delegated the extension architecture decision and identified Cloudflare
handling as crucial. MangaDex is now bundled for development testing; Comix remains
planned. See the source notes and progress log for live-verification limits. This decision refines plan sections 4 and 17; it does not
mark later plan phases as complete.

## Choice

Authors write small TypeScript adapters against Midoku's versioned SDK. esbuild
produces one JavaScript IIFE per source. Native Swift protocols separate the adapter
contract, registry, JavaScript runtime, request transport, session store, and
interactive verification. Normalized content includes source-scoped stable IDs.
Library ownership and reading sequence remain separate from adapter results.

JavaScriptCore executes reviewed bundled adapters off the main actor. WebKit handles
website interaction on the main actor. One execution context per call avoids
cross-account JavaScript state. Source connection UUIDs select independent persistent
WebKit data stores. Extensions and versions are not connection IDs.

This supports any adapter implementing our contract. Existing Mihon, Aidoku,
Paperback, or Suwatte binaries are not directly compatible.

## Cloudflare handling

The native host, not individual adapters, owns this sequence:

1. Send an allowed HTTPS request with the connection's WebKit-derived User-Agent and
   matching cookies. Cookie selection checks host boundaries, path, Secure, and expiry.
2. Detect `cf-mitigated: challenge` regardless of HTTP status; also recognize a
   narrow legacy HTML challenge signature on 403/503. An ordinary 403 remains an
   HTTP error, and rate limiting is a separate error.
3. A foreground request may present a visible verification sheet using that
   connection's persistent WebKit profile. Background requests return
   `verificationRequired` without presenting UI.
4. Let the user complete the real website challenge. The sheet restricts navigation
   to declared source hosts and Cloudflare's verification frame host. WebKit
   subresources are browser-managed; this is not a comprehensive WebKit network sandbox.
5. “Retry request” reloads cookies from that same profile and retries the original
   native request once. The second HTTP response establishes success. A cookie or
   a completed navigation does not.
6. Repeated challenges stop with a recoverable error. Cancellation releases the
   waiting operation; other connections remain independent. Additional same-source
   requests wait behind the single active flow and reuse the updated session.

Cloudflare explicitly documents limited embedded-browser support. Clearance is
visitor/device-bound, and moving cookies to URLSession is not guaranteed to satisfy
every deployment. Changed IP/session/browser conditions can require verification
again. Universal clearance cannot be promised.

If a chosen source works in WebKit but continues to reject native requests, evaluate
a source-scoped browser transport behind the existing host interface. Such a
transport is not implemented or automatically enabled here. Keep the source marked
unsupported until the complete metadata-and-image path is verified. External
Safari is not a cookie-import mechanism. Automated CAPTCHA solvers, proxy
subscriptions, and a central bypass backend are not part of this design.

## Trust and distribution

For this milestone the executable catalogue consists solely of reviewed app-bundled
code. The explicit review list in `Extensions/bundled.json` currently selects MangaDex.
The build embeds selected manifests/bundles into checked-in Swift resources;
creating an adapter alone does not activate it. Offline A/B fixtures remain DEBUG-only.
There is no arbitrary URL/import UI and no unauthenticated remote executable loading.

Before remotely updated packages: choose the distribution route, authenticate
manifests and bundle digests with maintained signing keys, check compatibility,
stage/validate/activate atomically, retain the last working version, and define key
rotation and rollback. Permissions must not expand silently.

JavaScriptCore isolation is a concurrency boundary, not protection from hostile
code. Swift task cancellation does not interrupt synchronous infinite JavaScript.
The host validates exact declared domains or reviewed leading `*.domain`
subdomain scopes, with label-boundary matching, and rejects literal local/private
addresses; DNS rebinding and a hostile publisher are not solved by those checks.
Arbitrary third-party packages remain out of scope until stronger guarantees exist.

## Persistence and integration boundaries

Only the small source-connection inventory is persisted in versioned atomic JSON at
this stage. It contains IDs, labels, enabled state, and extension IDs, never cookies.
Invalid/future versions are surfaced without resetting the file. This is not a
replacement for the planned GRDB library database. Move the existing connection UUIDs
unchanged into that database when its migrations are established.

Views use `SourceAdapter` and capability metadata; they never execute JavaScript or
SQL. The shared HTTP coordinator must also serve future reader/thumbnail/download
pipelines with the same connection context. The current transport is bounded GET
metadata fetching; large-file streaming and source-specific non-GET operations need
explicit host additions.

The TypeScript contract and Swift DTOs are an initial executable subset of the full
plan. Filters, preferences/authentication schemas, parser helpers, package updating,
complete library persistence, mixed-source paste/reader behavior, and downloads
remain separate implementation milestones.

## Acceptance before the first live adapter ships

- Deterministic contract/parser tests and iOS builds pass.
- Verify the actual source domain, API/HTML behavior, permissions, and access requirements.
- Exercise live verification on a physical iPhone: success, cancellation, expired
  clearance, repeated challenges, relaunch, and a changed network.
- Verify reader image requests use the same session context; metadata success alone
  is insufficient.
- Prove that two connections cannot reuse each other's cookies and background jobs
  never open verification UI.
- Report which protected sources work, which do not, and which remain untested.

## Primary references checked

- [Cloudflare challenge response detection](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/)
- [Cloudflare clearance](https://developers.cloudflare.com/cloudflare-challenges/concepts/clearance/)
- [Cloudflare supported browsers and WebView limitations](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/)
- [Apple persistent WebKit profiles](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:))
- [Apple WebKit cookie store](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
- [Apple JavaScriptCore](https://developer.apple.com/documentation/javascriptcore)
