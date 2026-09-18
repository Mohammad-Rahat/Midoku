# Midoku

Native manga reader in development. Read [the product plan](Midoku/plan.md) and
[current progress](docs/progress.md) for the distinction between implemented features and future work.

## Development

Open `Midoku.xcodeproj` in Xcode. The current project uses Xcode 27's JSON-style
`project.xcproj` format. The existing app target, signing configuration, bundle ID,
and configured deployment setting are preserved.

The app has five-tab navigation, persistent Settings, managed Home pins, reading
History/positions, foreground downloads/offline access, and a source-independent
extension foundation. See [settings behavior, storage, and verification](docs/settings.md)
for implemented scope and the remaining personal-library dependencies. Settings → Extensions manages registered bundled sources. In Debug builds,
Settings → Extension Lab runs the two offline TypeScript fixtures through JavaScriptCore.
MangaDex is bundled for testing: add it in Settings → Extensions, then open
Browse → MangaDex for feeds, search, filters, entry details, chapters, and direct reading. The chapter action menu downloads individual chapters; Settings manages the queue.
There is no remote extension installer yet.

The supplied [UI design kit and Midoku brand assets](docs/design/README.md) are
stored in the repository. The app uses their icon, adaptive palette, and empty-state
illustrations. The rest of the kit guides later product-plan screens.

## Extension authoring

Start with the [extension author guide](Extensions/README.md): setup, manifest rules,
every method and data shape, a complete search example with offline tests, Cloudflare
handling, and registration in the app. See [the architecture decision](docs/extension-architecture.md)
for host boundaries and future distribution work.
See the [MangaDex adapter notes](Extensions/sources/dev.midoku.mangadex/README.md)
for defaults, live checks, and current UI limits. Comix remains unimplemented.

## Checks

```sh
cd Extensions
npm ci
npm test
cd ..
swift test
```

Build the iOS app in Xcode as well. The Swift package tests compile the same extension
core files used by the app; they do not build another application. The checked-in,
generated fixtures allow Swift tests and app builds without installing Node first.

Use the same Xcode toolchain for CLI checks as the IDE. In environments that restrict
default compiler caches, see the commands recorded in [progress](docs/progress.md).

Cloudflare support uses a visible WebKit verification session and a bounded request
retry. Actual acceptance by protected sources requires source-specific physical-device
testing; passing fixture checks does not establish live Cloudflare compatibility.

