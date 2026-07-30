# ADR 0013: NOOR Brand and Design System Alignment

Status: Accepted
Sprint: UX-1

## Context

The user supplied and approved an official NOOR logo (a stylized "N"
combining a network/data-node graphic with a medical-cross symbol,
rendered in a deep-navy-to-teal-to-emerald gradient, with a "NOOR /
CLINICAL INTELLIGENCE" wordmark). Before this sprint, the product had
**no logo, no favicon, and no app icons anywhere** — `apps/web/public/`
was empty. The existing design-system foundation (ADR 0005, "50%
Better/25% NHS/15% Carbon/10% warm") was sound but its color palette
(a generic deep-teal/emerald pair, `#087F73`) was never derived from any
approved brand asset. This sprint makes the approved logo the single
source of truth for Noor's visual identity.

## Decisions

### The logo is never redrawn — only cropped

Every derived asset (`apps/web/public/brand/*`) is produced by cropping
and re-encoding the original approved JPEG
(`apps/web/public/brand/source/noor-logo-original.jpeg`, preserved
byte-for-byte, sha256-verified against the file the user supplied). Crop
boundaries were measured directly from the source image's own content
(a row/column scan for non-near-white pixels — see
`docs/design/noor-color-system.md`), not eyeballed. No pixel of the mark,
wordmark, or descriptor was redrawn, recolored, or regenerated.

### Brand anchors were sampled, then validated against the mission's own reference values

Independent pixel sampling of the logo (dominant-color binning across
the "N" mark, the network graphic, and the wordmark) produced anchors
that fell inside the same hue/lightness range as the mission's supplied
reference hex values (Deep Navy `#032855`, Clinical Blue `#045092`,
Primary Teal `#078A88`, Emerald `#09B993`). Rather than deriving a
second, independently-computed set of anchors that risked encoding raw
JPEG chroma-subsampling artifacts (several raw samples had a suspicious
`R=0` channel — a known JPEG compression artifact at sharp gradient
edges, not a real design intent), the mission's reference values were
adopted as final, with the sampling serving as validation rather than as
the source of truth. See `docs/design/noor-color-system.md` for the
full sampling method and the exact comparison.

### Semantic color slots stay stable; only their values changed

`packages/ui/tokens/colors.ts` already separated raw brand colors
(`brandColors`) from semantic component slots consumed by every shared
component (`bg-primary`, `text-ink`, `bg-canvas`, …) via Tailwind
utilities backed by CSS custom properties (`packages/ui/tokens/index.ts`
→ `TokensStyleTag`). This meant re-branding the entire application was
almost entirely a **token-value change, not a component rewrite**:
`primary` (buttons/CTAs) now resolves to Clinical Blue, `accent`
(navigation-active state, focus ring — a new slot, split out from
`primary`) resolves to Primary Teal, and `ink` (headings) resolves to
Deep Navy. This mirrors the logo's own internal structure: the left half
of the "N" (network/data) is blue, the right half (medical cross) is
teal-to-emerald.

### Brand colors never override clinical safety semantics

`danger`/`critical`/`warning` keep their pre-existing, universally-
recognized red/amber hues untouched — the brand palette is never used to
recolor a safety-relevant state. Positive/neutral states (`verified`,
`informational`, `processing`) were shifted to the brand's own emerald/
blue hues, since reinforcing brand identity on a *positive* outcome
carries no safety risk. See `packages/ui/tokens/colors.ts`'s
`semanticStates` and `docs/design/noor-accessibility-review.md`.

### Five new, previously-collapsed status buckets

Auditing every feature's status→color mapping found several genuinely
different statuses collapsed onto the same `underReview`/`inactive`
bucket, most notably `ocr_required` and `reprocessing_required` on
extraction/OCR reviews, which were **visually identical** before this
sprint (same color, same icon, differing only by label text) despite
meaning materially different things. Five new semantic states were
added — `queued`, `retryScheduled`, `ocrRequired`,
`reprocessingRequired`, `deadLettered` — each with its own icon, color,
and accessible description, not a label-only distinction. See
`docs/design/noor-component-theme.md`.

### Application-shell scope was sized to what actually exists

The mission's brief described a sidebar-shell redesign. The actual
Noor web app has no sidebar — `apps/web/app/WorkspaceHeader.tsx` is a
single shared horizontal top-bar (permission-filtered pill nav + role
badge + sign-out) rendered by all five workspace layouts
(admin/clinician/knowledge/quality/reviewer). Inventing a new sidebar
architecture where none exists would be real architectural scope creep,
not brand alignment. The logo and the teal active-state were added to
this one shared component instead, which every workspace already
inherits.

### Gradient use is deliberately restrained

One gradient token (`--noor-gradient-brand`, blue→teal→emerald,
matching the "N" mark's own hue progression) exists. It is used in
exactly two places: a thin accent line on the login page and the
design-system swatch page. It is not a button, badge, table-header, or
card default — dense clinical review surfaces stay flat and calm per
the mission's own "clinical clarity before decoration" principle.

## Consequences

- A future brand refinement touches `packages/ui/tokens/colors.ts` in
  one place; every consuming component picks it up automatically.
- The five new semantic states are additive — no existing status
  mapping was removed, only reassigned to a more precise bucket.
- Dark mode (`brandColorsDark`), which already existed before this
  sprint, was updated in lockstep with the light palette rather than
  left to drift.
