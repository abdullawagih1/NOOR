# The NOOR Brand

Official reference for how Noor's name, logo, and colors may be used
across the product, documentation, and any external materials. See also
`docs/brand/noor-logo-usage.md` (asset-level rules) and
`docs/design/noor-color-system.md` (full palette derivation).

## Name

- **Visible brand mark:** `NOOR`
- **Product name in prose:** `Noor — Clinical Intelligence OS`
- Do not use `NOOr`, `Noor AI Assistant`, or other casing/naming
  variants — `NOOR` (mark) / `Noor` (prose) are the only two approved
  forms.

## Logo

- **Official source:** `apps/web/public/brand/source/noor-logo-original.jpeg`
  (1254×1254 JPEG, approved by the user, preserved byte-for-byte — see
  its sha256 in `docs/design/noor-color-system.md`).
- The logo is a stylized "N": the left stroke is a network/data-node
  graphic in navy-to-blue, the right stroke is a medical cross inside a
  teal-to-emerald rounded form with a small emerald "signal" glow, above
  the wordmark `NOOR` and the descriptor `CLINICAL INTELLIGENCE`.
- **Never redraw, recolor, restretch, or regenerate the logo.** Every
  asset in `apps/web/public/brand/` is a crop of the original artwork —
  see `docs/brand/noor-logo-usage.md` for exactly which crops are
  approved and where each is used.
- No approved dark-background or monochrome variant exists yet (see
  Known Limitations). Until one is produced and validated, only place
  the logo on white or near-white surfaces.

## Clear space and minimum size

- Keep at least 8% of the asset's own width as clear space on every
  side (already baked into the padding used when each derived asset was
  cropped — see the generation notes in
  `docs/design/noor-color-system.md`).
- Do not render the full lockup (mark + wordmark + descriptor) below
  ~120px tall — the descriptor line becomes illegible first. Below that,
  use the navigation crop (mark + wordmark, no descriptor) or the
  symbol-only crop.

## Palette

| Role | Hex | Used for |
|---|---|---|
| Deep Navy | `#032855` | Headings, primary text (`ink`) |
| Clinical Blue | `#045092` | Buttons, primary CTAs, links (`primary`) |
| Primary Teal | `#078A88` | Navigation-active state, focus ring (`accent`) |
| Emerald | `#09B993` | Restrained success/highlight emphasis |
| Soft Cyan | `#B6DAE0` | Supporting surfaces (auth side panels) |
| Blue-Gray | `#6E9DA8` | Supporting neutral text/borders |
| White | `#FFFFFF` | Canvas |

Full scales, derivation method, and contrast verification:
`docs/design/noor-color-system.md`.

## Gradient

`linear-gradient(135deg, #045092 0%, #078A88 52%, #09B993 100%)` — one
official gradient, matching the "N" mark's own hue progression. Used
sparingly: a thin accent line (login page, design-system swatch page).
Never a button, badge, table header, or card background, and never over
dense clinical review text.

## Typography

- Latin: **Inter** (via `next/font/google`, self-hosted, no CDN call).
- Arabic: **IBM Plex Sans Arabic** (same mechanism).
- Full type scale: `packages/ui/tokens/typography.ts`.

## Tone

Clinical, calm, trustworthy, accessible, data-aware. Not a consumer
app, not a marketing landing page, not a decorative concept. See ADR
0013 and the existing design-system ADR 0005.

## Component principles

- Color is never the only signal — every status carries an icon and a
  text label (`SemanticStatusBadge`, `packages/ui/tokens/colors.ts`).
- Brand colors never override clinical safety semantics — danger/
  warning/critical keep their pre-existing red/amber regardless of the
  brand refresh. See ADR 0013 §"Brand colors never override clinical
  safety semantics."
- One shared token source (`packages/ui/tokens/*`) — no feature page
  hardcodes a hex value.

## Prohibited usage

- Redrawing, recoloring, or regenerating the "N" mark, the network
  graphic, the medical cross, or the wordmark.
- Placing the current (white-background) logo directly on a dark
  surface.
- Using the brand gradient as a default button/badge/card treatment.
- Using the brand palette to recolor a danger/warning/critical state.
- Any casing of the name other than `NOOR` / `Noor — Clinical
  Intelligence OS`.

## Asset paths

```text
apps/web/public/brand/
  source/noor-logo-original.jpeg   — preserved original, never edited
  noor-logo-primary.png            — full lockup (login, About panel)
  noor-logo-navigation.png         — mark + wordmark, no descriptor (top nav)
  noor-symbol.png (+ -512/-192/-180/-32/-16) — mark only, squared on white
  favicon.ico                      — 16/32/48px, from the symbol crop
  social-preview.png               — 1200×630 Open Graph image
```

This document does not constitute a registered trademark filing.
