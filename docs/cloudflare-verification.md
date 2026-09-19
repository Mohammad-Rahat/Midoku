# Cloudflare verification follow-up

## Reference and confirmed differences

Read Aidoku's [CloudflareHandler.swift](https://github.com/Aidoku/Aidoku/blob/8ae2da15d9edef05d0e6f27e0799c629883d0890/Aidoku/Core/Sources/Cloudflare/CloudflareHandler.swift),
popup handler and UserAgentProvider at commit `8ae2da15d9edef05d0e6f27e0799c629883d0890`.
The behavioral reference is a real URL load into an attached native WebKit view,
matching the native request's UA/rendering mode, revealing the same view for a
challenge, waiting for fresh clearance plus a non-challenge page, and retrying
the native request once. This is an independent Midoku implementation, not a
copy of Aidoku's GPL-licensed source.

Aidoku does not run frames through Midoku's adapter HTTP policy. Midoku's previous
delegate allowed `about:blank` but rejected `about:srcdoc`. Cloudflare explicitly
requires both in its [mobile integration documentation](https://developers.cloudflare.com/turnstile/get-started/mobile-implementation/).
This is a confirmed compatibility defect, not proof it was the sole cause of
the user's observed device loop.

Midoku also deleted/reseeded cookies through WebKit's global default store while
replaying the rejected request's complete Cookie header. This could replay stale
clearance and separated cookies from their source profile's other browser state.
The earlier default-store experiment did not resolve the user's device issue.

## Current behavior

- Create an ordinary WKWebView with the connection's persistent profile, without
  extraction scripts or content blockers. Match native UA and rendering mode.
- Attach it to a native view controller before loading. Initially keep it small,
  then expand the same view three seconds after navigation, or after twelve
  seconds on a slow load. No intermediate reload or cookie-store transfer.
- Preserve browser cookies and local storage. Do not delete clearance on each
  attempt. Compare against all previously applicable clearance values instead.
- Pass permitted request headers and the same UA, but let WebKit construct Cookie
  from its current jar. No global HTTPCookieStorage or default WebKit profile.
- Allow required local and Cloudflare subframes; deny external top-level pages,
  unsafe schemes, origin lookalikes, credentials and unexpected ports. Native
  adapter permissions are unchanged. Extraction uses the same frame policy.
- Complete only after a successful finished source navigation, fresh matching
  clearance, and a non-challenge DOM. Navigation revisions invalidate old async
  observations; completion and cancellation cannot trigger duplicate retries.
- A separate 90-second watchdog pauses a stuck attempt. Reload constructs a new
  browser using the same source profile. Cancel releases the waiting request.
- Connection details expose only HTTP status, a fixed page-state label, whether
  clearance is absent/unchanged/new, and frame/block counts. No cookie values,
  HTML, full URLs, challenge tokens or credentials are displayed or logged.

The deliberate difference from Aidoku is session isolation: its global cookie jar
cannot be used in Midoku, where multiple source connections must remain separate.
The existing serialized foreground flow and one native retry remain in place;
background metadata, image preloads and downloads never open this sheet.

## Verification and remaining device checks

Tests cover required frames and negative permissions, Cookie-header ownership,
UA preservation, invalid headers, fresh/old/expired/foreign cookies, DOM states,
HTTP completion, navigation races, cancellation, and duplicate completion. The
existing coordinator suite verifies one native retry and no background presentation.
The IPA workflow runs these Swift tests, extension tests and the iOS archive.

Passing those checks cannot establish production Cloudflare clearance. On a
physical device/LiveContainer, open NovelCrow, finish any visible interaction,
then test search, details, chapters and actual images. Also test Reload, Cancel,
relaunch, stale sessions and a second independent connection. If verification
still loops, capture the expanded Connection details panel; it distinguishes
blocked frames, missing clearance and a native-retry failure without exposing secrets.

Do not claim universal clearance, Safari cookie import or an automated CAPTCHA
solver. The previous two builds failed the user's device test; this build still
needs that acceptance check.
