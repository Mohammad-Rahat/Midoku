# iOS Manga Reader — Design handoff

Minimal native iOS direction: warm white, forest accents, charcoal type, quiet separators, and editorial cover art.

## Files
- `manga-reader-design-board.svg`: 20-screen vector design board. Drag into a Figma design file to import vector layers.
- `screens/`: Individual SVG screen files for easier import and iteration.
- `manga-reader-preview.html`: Self-contained clickable preview; open in a browser. Main navigation and the pin/copy/paste reading flows are connected. Utility actions display feedback only; this is a design prototype.
- `design-tokens.json`: Color, typography, spacing, and radius references.
- `build_design.py`: Reproducible source for the supplied vectors and preview.

## Key review flows
1. Browse → MangaDex → Popular → Pin to Home.
2. Browse → MangaDex → manga → chapter action → Copy → Paste 1 → Add chapter.
3. Library → Naruto → Continue → reader preferences.
4. Settings → home sections, extensions, categories, and downloads.

## Design notes
- The five tabs are always labelled. Reader and focused editing screens hide the tab bar.
- Chapter origin appears below chapter details; mixed sources remain visible in the combined entry.
- Category membership, publication status, and reading progress are separate concepts.
- Cover and reader artwork is original abstract vector sample art, not official book covers.
- Shortened lists represent viewport samples. Long content should scroll in the implementation.
- Figma import produces vector layers; native Figma component instances, auto-layout, and prototype links were not created because the Figma editing connection was unavailable. The HTML preview supplies navigation separately.
- No live search, data storage, extension execution, or actual downloads are implemented in this design preview.
