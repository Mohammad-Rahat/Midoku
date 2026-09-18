# Midoku visual foundation

## Identity

The identity is your approved open-book icon: layered ivory paper, a gentle central fold and a forest-green field. Preserve this exact artwork for the app icon. Use a rounded tile containing it in About, onboarding and the optional branded startup view.

Detail belongs in the book artwork. Keep navigation, lists and controls calm and clear. Use paper-like backgrounds, restrained separators, comfortable spacing and minimal shadows. Manga covers provide most of the color inside content screens.

## Palette

| Role | Light | Dark |
| --- | --- | --- |
| Background | `#FAFAF7` | `#101913` |
| Surface | `#FFFFFF` | `#18241D` |
| Elevated surface | `#F0F2ED` | `#233329` |
| Primary text | `#202D26` | `#FAF8F0` |
| Secondary text | `#606D63` | `#B0BCAE` |
| Foreground accent | `#376A50` | `#9BC8AA` |
| Filled button | `#376A50` | `#376A50` |
| Text on filled button | `#FAFAF7` | `#FAFAF7` |
| Decorative separator | `#E0E6DD` | `#35483B` |
| Destructive action text | `#B64032` | `#FF9A8D` |

The icon contains subtle texture and varied green pixels. The flat brand color remains the intended `#376A50`. Do not attempt to match every pixel of the rendered icon with a gradient behind every screen.

## Type and rhythm

- Use the native system font with semantic SwiftUI styles and Dynamic Type.
- Use bold large titles, semibold section headings and regular body text.
- Start with 16–24 pt outer padding and the spacing scale 4, 8, 12, 16, 24, 32 and 48.
- Corner radii: 8 pt for small labels, 12 pt for inputs, 14 pt for buttons and 16 pt for cards. Use about 23% of width for the in-app brand tile.
- Keep interactive areas at least 44 × 44 pt. Label all symbol-only buttons for VoiceOver.
- Use explicit labels or selection indicators along with color. Decorative separators should never be the sole indication that a control exists.
- Respect Reduce Motion. Do not animate page curls or spin the book as a loading indicator.

## Apply across the five tabs

**Home:** Use a simple title and pinned extension feeds. Display extension name and pinned tab under each section heading. Use covers in horizontal shelves with a clear route to the source. Use the Home empty illustration and a Browse action before anything has been pinned.

**Library:** Keep categories easy to scan above the cover grid. Edited metadata belongs to the local library entry. In the detail screen, use compact cover thumbnails for chapters and always show the originating extension below the chapter details. Copy/paste and source mixing use native sheets and menus.

**Browse:** Use small extension icons with clear text names, a visible global search action and native filter sheets. The bundled extension placeholder is a fallback for missing icons; it must not replace an available source identity.

**History:** Use a quiet chronological list with a chapter thumbnail, title, source and last-opened time. Empty history should feel neutral. Avoid achievement language or unnecessary visual noise.

**Settings:** Use native grouped rows, simple SF Symbols and short descriptions. Show the Midoku wordmark in About. Keep theme controls and Home/category/extension management consistent with the rest of the app.

**Reader:** Let page artwork dominate. Use a black canvas and subdued native controls. All chapter ordering, source attribution and reading state behavior remain as described in the product plan.

## Images and placeholders

- Manga cover ratio: 2:3, with gentle rounded corners applied in the UI.
- Chapter thumbnail ratio: 16:9; crop provider artwork predictably and fall back to the bundled chapter placeholder.
- Source fallback: square, with a grid mark inside a soft adaptive surface.
- Empty states: 192 × 160 pt artwork, live title, live explanation and at most one primary action.
- Use the detailed icon at 40 pt or larger in the app; use native symbols for smaller controls.
- Do not treat user-provided cover art as decorative when it is the only accessible title identifier. Expose a useful label or equivalent adjacent text.

## Existing plan

This asset pack refines the existing green/ivory direction. Product behavior and navigation stay as specified in `plan.md`. Keep this guide next to the plan and point your implementation agent to both. The five tabs remain Home, Library, Browse, History and Settings.
