# NOOR Logo Usage

Asset-level rules. See `docs/brand/NOOR_BRAND.md` for the broader brand
reference.

## The one approved source

`apps/web/public/brand/source/noor-logo-original.jpeg` — the exact file
the user supplied and approved, 1254×1254 JPEG, preserved unmodified.
Every other file under `apps/web/public/brand/` is a crop of this file's
own pixels — none were redrawn, recolored, or AI-regenerated. Crop
boxes were measured from the source's own content bounding box (a row/
column scan for non-near-white pixels), not eyeballed — see
`docs/design/noor-color-system.md` for the exact pixel coordinates used.

## Which asset, where

| Asset | Dimensions | Use |
|---|---|---|
| `noor-logo-primary.png` | 1046×926 | Login page, password reset, About/welcome panels, README |
| `noor-logo-navigation.png` | 997×824 | Top navigation bar (`WorkspaceHeader`) |
| `noor-symbol.png` (+ sized variants) | 998×998 square (+512/192/180/32/16) | Favicon source, app icons, anywhere only the mark fits |
| `favicon.ico` | 16/32/48 | Browser tab icon |
| `social-preview.png` | 1200×630 | Open Graph / Twitter card image |

## Allowed

- Cropping the symbol area from the original artwork (done —
  `noor-symbol.png`).
- Cropping the wordmark area together with the symbol, excluding the
  smaller descriptor line for small-scale legibility (done —
  `noor-logo-navigation.png`).
- Using the complete logo at a smaller size, as long as the descriptor
  line stays legible (roughly ≥120px tall).
- Using the "N" symbol alone as a favicon/app icon, since it is an
  exact, unmodified crop of the original.

## Not allowed

- Redrawing the "N", the network graphic, or the medical cross.
- Replacing the wordmark with app typography (e.g., rendering "NOOR" in
  Inter next to a cropped symbol) — this would silently swap the
  wordmark's own typography for a different one. Where a compact
  lockup with real legible text is needed, use
  `noor-logo-navigation.png`'s real cropped wordmark, not a re-typeset
  substitute.
- Recoloring, restretching, or compressing the logo's own aspect ratio.
  Every placement in the app sets only `height` and lets `width` follow
  automatically (`h-* w-auto` in Tailwind, or an explicit `width`/
  `height` pair on `next/image` matching the crop's real aspect ratio),
  so CSS never distorts it.
- Placing the current white-background artwork on a dark surface
  without an approved dark/reversed variant (none exists yet — see
  Known Limitations in `SPRINT_CURRENT.md`).
- Generating a new logo, a new "N" variant, or a monochrome variant with
  an image model. If a dark-background or monochrome variant is ever
  needed, it must be produced by a human designer from the master
  artwork and approved the same way the primary logo was, then added
  here as a new named asset — not synthesized.

## Background

The source artwork was designed for a white base. Every placement in
the app sits on `bg-canvas` (`#FFFFFF`) or a very light tint
(`surface-soft`) — never on a saturated brand color or a dark surface.

## Favicon/icon generation

`apps/web/public/brand/noor-symbol.png` is squared on a white canvas
(12% padding) directly from the "N" mark's own content bounding box,
then resized (Lanczos) into `favicon.ico` (16/32/48) and the app-icon
sizes (512/192/180). At 16–32px the fine network-graphic lines are not
individually legible — this is an accepted, expected limitation of
using the full detailed mark at favicon scale rather than a simplified
mark, since simplifying it would mean redrawing it (prohibited).
