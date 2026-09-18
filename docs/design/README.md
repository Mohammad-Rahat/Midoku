# Midoku design references

The user supplied two complementary design packages:

- [UI design kit](manga-reader-design-kit/README.md): screen composition,
  navigation references, manga/chapter layouts, and a clickable HTML prototype.
- [Midoku brand guide](Midoku/BRAND-GUIDE.md): approved app icon, adaptive
  colors, typography, illustrations, and placeholder usage.

Use the UI kit for screen structure and the newer brand pack for final identity
and light/dark color choices. Labels such as “Reader” or “The Reader” in the older
references mean Midoku. MangaSee/ComicK and manga entries in those references are
sample content; the intended first live adapters remain MangaDex and Comix.

## App resources

- `Midoku/Resources/MidokuAssets.xcassets`: the complete supplied native catalog,
  copied without modifying artwork. Includes one app icon set, 13 adaptive
  color sets, brand artwork, six empty-state sets, and three placeholder sets.
- `Midoku/Resources/LaunchScreen.storyboard`: the supplied adaptive background.
- `Midoku/DesignSystem/`: supplied SwiftUI theme, brand components, symbol
  mappings, and empty-state views adapted for the current app.
- App icon set: `AppIcon` (the supplied `MidokuAppIcon` set renamed to match
  the target's existing selection). The existing global `AccentColor` mirrors
  `MidokuAccent`; SwiftUI components use the semantic Midoku color names.

Home, Library, and History use the branded empty states. Browse and extension
management use the source placeholder. Home and Library actions navigate to
Browse. Empty-state artwork centers when it fits and scrolls at larger text sizes.
No artificial splash delay has been introduced; the optional branded splash
component is available for future real initialization work.

The full UI kit and the brand guide/tokens/original master/overview/SVG sources
are retained here outside app target membership. Full-screen preview images and
the HTML prototype are references, not native screen implementations.

## Artwork provenance

The catalog was copied from the user-supplied `Midoku-Assets` directory.
Every catalog file matched the source bytes at import, and the original approved
master matched the SHA-256 in [the manifest](Midoku/asset-manifest.json).
The icon set directory was subsequently renamed to `AppIcon`; its contents and
all artwork remain unchanged. The source package's image references were checked
before Xcode compilation.

The older UI kit's populated flows remain implementation references for the
corresponding product-plan milestones. Importing the references does not mark
those features complete.
