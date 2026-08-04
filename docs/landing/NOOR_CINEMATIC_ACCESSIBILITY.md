# NOOR Cinematic Accessibility

Status: **LX-1.1 — In Progress** (checklist below is verified against
real `@axe-core/playwright` scans and manual checks in the verification
report, not asserted from design intent alone)

## LX-1.2 addendum — production-integration accessibility findings

Real axe scans against the production-integrated route (both the
public `/` root with the cinematic flag enabled, and the auth
surfaces it links to) found and fixed 2 genuine, pre-existing
violations unrelated to the cinematic scene content itself:

- `landmark-one-main`/`region` on `/login` and `/access-denied` —
  `AuthShell.tsx`'s `AuthSplitShell`/`AuthCardShell` wrapped their
  content in plain `<div>`s with no `<main>` landmark at all.
  Pre-existing since before this mission (confirmed: these shells
  were never touched by any of this mission's actual feature work).
  Fixed by promoting the form-column container to `<main>` and the
  brand/logo column to `<header>`.

Zero violations after the fix, across: legacy root (desktop + mobile),
cinematic root (desktop + mobile + reduced-motion + WebGL-disabled),
`/login`, `/access-denied`. See
`docs/verification/lx-1-2-production-integration.md` for the full scan
matrix and raw results.

## Canvas semantics

The `<Canvas>` element and every element inside it carry
`aria-hidden="true"` — the canvas contains no unique readable content
(mission §40's explicit requirement); every fact the canvas visually
represents also exists as real DOM text in the scene overlays.

## Complete semantic story in DOM

Every scene's headline, supporting copy, and status label is rendered
by the Server Component (`page.tsx`) unconditionally, in narrative
order, regardless of whether the canvas ever mounts. A screen reader
or a JS-disabled crawler reads the complete 7-scene narrative exactly
once, top to bottom.

## Heading order

`h1` — page headline (Scene 1's, since it is the page's true title).
`h2` — each subsequent scene's headline, in DOM order. No skipped
levels.

## Keyboard

- The minimal nav (logo, sign-in, motion-preference control) is fully keyboard-operable.
- The final CTA and "explore again" secondary action are real `<a>`/`<button>` elements.
- No custom scroll-jacking intercepts keyboard scroll (Space/PageDown/arrow keys/Home/End all work natively, since the master timeline reads scroll, never writes it).
- No keyboard trap anywhere.

## Focus

Visible focus rings reuse the existing `focus-visible:outline
focus-visible:outline-2 focus-visible:outline-offset-2
focus-visible:outline-accent` pattern from `PublicShell.tsx`.

## Reduced motion

`prefers-reduced-motion: reduce` renders `StaticFallbackExperience`
exclusively — no canvas, no scroll-scrubbing, no camera travel, no
particles, no parallax, no pinning. Every headline, status label, and
CTA from the motion-enabled path is preserved in the same order. See
`NOOR_CINEMATIC_FALLBACK_STRATEGY.md`.

## Screen reader order

DOM order matches narrative order in every path (motion-enabled and
static) — verified directly by asserting the accessible-name sequence
of the page's landmark regions.

## Zoom

Verified usable at 200% browser zoom: text reflows, the sticky canvas
container does not clip readable content, no horizontal scroll is
introduced.

## No content on hover only

Every status label, finding marker, and CTA is visible without
hovering — hover states (if any) only add emphasis, never reveal new
information.

## No meaning by color alone

Status labels ("Available foundation" / "Internal evaluation
foundation" / "Product vision") are always text, never a color-only
signal. The emerald verification pulse in Scene 3 is accompanied by
the DOM status chip's own text change, not relied on alone.

## No flashing / vestibular safety

No element flashes more than 3 times per second (none flash at all).
Camera movement is always damped (see Camera Map §Damping) — no rapid
zoom, no snap-cuts, no continuous unprompted rotation, satisfying the
mission's vestibular-safety requirement directly, not just by
incidental design.

## Static fallback content parity

`StaticFallbackExperience` is verified to contain the same 7 headlines,
supporting copy, status labels, and both CTAs as the motion-enabled
path — checked by a direct text-content diff in the verification
report, not by inspection alone.

## RTL

An isolated `dir="rtl"` structural preview (matching the `/design-
system` and LX-1.0 precedent) confirms: unmirrored logo, LTR-preserved
technical labels, and a semantically-correct (not auto-mirrored)
provenance/CTA layout. Full Arabic-content translation is out of scope,
exactly as LX-1.0 already stated — not newly claimed here.
