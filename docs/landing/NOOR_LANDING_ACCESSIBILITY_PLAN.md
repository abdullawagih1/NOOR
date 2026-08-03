# NOOR Landing Accessibility Plan

Status: **LX-1.0 — In Progress**

## Reduced motion (mission §18)

Every animated concept in `NOOR_LANDING_STORYBOARD.md` has a named,
specific reduced-motion equivalent — never a generic "just turn off the
animation" catch-all. Reduced-motion behavior across the whole page:

- Preserves all content (nothing is reduced-motion-only content that vanishes).
- Preserves narrative order (scenes render in the same DOM order either way).
- Preserves state meaning (a "verified" chip still reads "Verified" whether or not it animated there).
- Removes pinning (Scene 8 never pins under reduced motion).
- Removes scroll scrubbing (Scene 8 becomes a manually-advanced static sequence).
- Avoids large transforms (max 16px translate even in the motion-enabled path; reduced-motion drops this to 0).
- Avoids parallax (none exists anywhere in this plan — parallax was never proposed, since it adds spatial complexity without narrative payoff for a clinical audience).
- Avoids forced delays (no scene requires waiting for an animation to finish before its content or its CTA is usable).
- Keeps CTAs immediately available (both CTAs are real anchor/link elements present in the initial server-rendered HTML, not revealed by any animation).

## Keyboard and focus

- Every interactive element (both real CTAs, and the prototype gallery's play/pause/reset/scrubber controls) is a real, tabbable, native element (`<button>`, `<a>`) — never a `<div onClick>`.
- Focus-visible states use the existing `focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent` pattern already established in `PublicShell.tsx`, reused verbatim.
- Scene 8's manual "Next stage"/"Previous stage" controls (the reduced-motion/mobile equivalent) are the *only* way to progress that scene when motion is off — confirmed keyboard-operable, confirmed to move focus sensibly (to the newly-revealed stage's heading, not left behind on the button after the 5th press when the sequence completes).

## Screen-reader behavior

- Reading order matches visual/DOM order for every scene (no CSS-only reordering that would desync visual and AT reading order).
- Status labels (`Available`, `In development`, `Product vision`, `Evaluation framework — internal, not yet clinician-facing`) are real text in the accessible name/description of their section, not conveyed by color or icon alone.
- The evidence-flow strip (Scene 1), the validation channel (Scene 3), and the traceability breadcrumb (Scene 8) each have adjacent plain-text labels for every stage — nothing is "canvas-only meaning" (mission §18) since no canvas is used anywhere on this page (§`NOOR_LANDING_THREEJS_DECISION.md`).
- No content is hidden permanently before its entrance animation — server-rendered HTML contains the final content from first paint; `aria-hidden` is never used to hide content that a sighted user can eventually see, only for genuinely decorative elements (e.g. the thin gradient accent line under the logo).

## Scroll behavior

- No scroll trapping anywhere, including Scene 8 — `ScrollTrigger`'s pin releases normally at both ends of its range; a visitor can always continue scrolling past it.
- No horizontal-scroll storytelling on any viewport (mission §12/§24 both prohibit this for mobile; this plan extends the prohibition to desktop too, for consistency).

## Mobile

- Touch scrolling stays fully native everywhere — no scene intercepts touch gestures for its own purposes.
- No deep stacked overlays, no long pinned sections (Scene 8's pin is desktop-only, per Storyboard/Technical Architecture).
- CTA access stays simple — both CTAs remain single-tap reachable at hero and at the final section.

## RTL

- The RTL structural preview (prototype gallery only, matching the existing isolated `dir="rtl"` demo precedent in `/design-system`) is checked for: unmirrored logo, semantically-correct (not auto-mirrored) arrow/connector direction, LTR-preserved technical labels (checksums/IDs), and preserved Arabic line-height. Full Arabic-content translation validation is out of scope (English copy only this mission) and is logged as a future localization acceptance gate.

## No flashing / no rapid repeated movement

- Every entrance/emphasis animation fires once per scene entry (`whileInView once: true`, except Scene 8's continuous scrub, which is a smooth position-mapped progress, not a flash or repeat).
- Nothing blinks, strobes, or repeats on a timer anywhere on the page.

## Automated verification

`@axe-core/playwright` is run against the prototype gallery route (see
`docs/verification/lx-1-0-narrative-motion-prototype.md` for the actual
run output) in both motion-enabled and reduced-motion states, at
desktop and mobile viewports, and against the RTL structural preview.
