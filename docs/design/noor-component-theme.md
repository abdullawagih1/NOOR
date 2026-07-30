# NOOR Component Theming (UX-1)

How the shared component library (`packages/ui`) and the app's feature
layers pick up the brand refresh. See `docs/design/noor-color-system.md`
for the palette itself.

## The token pipeline (unchanged architecture, changed values)

```text
packages/ui/tokens/colors.ts   (brandColors / brandColorsDark / semanticStates)
        ↓
packages/ui/tokens/index.ts    (tokensToCssVariables — the ONE place that renders CSS vars)
        ↓
packages/ui/components/TokensStyleTag.tsx   (injected once, in app/layout.tsx)
        ↓
apps/web/tailwind.config.ts    (Tailwind utilities reference the CSS vars, not raw hex)
        ↓
Every component:  bg-primary, text-ink, bg-canvas, border-border, ...
```

This pipeline already existed before UX-1 — re-branding the whole
product was a token-value change plus a handful of component-level
class updates, not a rewrite. No feature page hardcodes a hex value
(verified: zero `#`/`bg-[#...]`/Tailwind-default-palette matches across
`apps/web/app` and `apps/web/lib`).

## New semantic slots

| Slot | Value | Used for |
|---|---|---|
| `primary` / `primary-active` / `primary-soft` | Clinical Blue family | Buttons, CTAs, links |
| `accent` / `accent-active` / `accent-soft` | Primary Teal family (**new** — split out from `primary`) | Navigation-active state, focus ring |
| `ink` | Deep Navy | Headings, high-contrast text |
| `body` / `muted` / `muted-soft` | Navy-tinted grays | Body text, secondary text, placeholders |

Before UX-1, the focus ring and the navigation-active state both reused
`primary`. They're now split so the logo's own "blue interaction / teal
wayfinding" distinction is real, not just described in the docs:
`Button`/`IconButton`/`Checkbox`/`Radio`/`Select`/`TextInput`'s
`focus-visible:outline-*` classes now target `accent`, and
`WorkspaceNav`'s active pill uses `bg-accent-soft text-accent-active`
instead of the old `bg-primary-soft text-primary-active`.

## Five new status buckets

`packages/ui/tokens/colors.ts`'s `semanticStates` gained five keys that
didn't exist before, each with a distinct icon (not just a distinct
label on a reused color):

| Key | Icon | Replaces this collapsed mapping |
|---|---|---|
| `queued` | clock | `queued` job status used to reuse `inactive` |
| `retryScheduled` | rotate-cw | `retry_scheduled` used to reuse `underReview` |
| `ocrRequired` | scan-line | `ocr_required` used to reuse `underReview` |
| `reprocessingRequired` | rotate-ccw | `reprocessing_required` used to reuse `underReview` |
| `deadLettered` | ban (deeper maroon than `critical`'s red) | `dead_lettered` used to reuse `critical` |

The concrete, real gap this closes: before UX-1, an extraction review's
`ocr_required` and `reprocessing_required` statuses were **visually
identical** (same color, same icon, different label text only) despite
meaning materially different things — one says "a page needs OCR," the
other says "a human rejected this attempt and it must be redone." They
are now visually distinct in addition to being textually distinct.

Every feature-level status map that had a real, meaningfully-different
status collapsed onto a too-generic bucket was updated to the new key:
`apps/web/lib/documents/ui.tsx` (`queued`, `retry_scheduled`,
`dead_lettered`), `apps/web/lib/extraction-review/ui.tsx`
(`ocr_required`, `reprocessing_required`), `apps/web/lib/ocr/ui.tsx`
(`reprocessing_required`, `queued`). Statuses that were already
correctly distinct (guideline lifecycle's `draft`/`ready_for_review`/
`approved`/`active`/`superseded`/`withdrawn`, all six mapped to six
different existing buckets) were left untouched.

## What intentionally did not change

- **Danger/warning/critical** keep their pre-existing red/amber — the
  brand refresh never touches a safety-relevant hue (ADR 0013 §4.3).
- **`aiGenerated`/`evidenceConflicting`** keep their existing indigo/
  violet — these flag "not yet human-approved" content, and staying
  deliberately off-brand reinforces "this is different from normal
  trusted content."
- **The application shell stays a single top nav**, not a sidebar — see
  ADR 0013 §"Application-shell scope was sized to what actually
  exists."

## Logo placement

| Location | Asset | Notes |
|---|---|---|
| `WorkspaceHeader` (all 5 workspaces) | `noor-logo-navigation.png` | New — no logo existed here before |
| `/login` | `noor-logo-primary.png` | New — replaces a plain "Noor V1" text eyebrow |
| `/design-system` | All three variants | New "Official brand" section |
| Browser tab / app icon | `favicon.ico` / `noor-symbol-*.png` | New — none existed before |
| Open Graph / social card | `social-preview.png` | New |

## Gradient usage (exhaustive list — nowhere else)

1. A 4px accent line under the logo on `/login`.
2. A 12px accent line in the design-system page's "Official brand"
   section.

No button, badge, card, or table header uses the gradient as a default.
