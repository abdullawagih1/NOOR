# NOOR Landing Motion System

Status: **LX-1.0 — In Progress**

## Motion hierarchy (importance order — decoration is nearly absent)

```
Causality → State change → Navigation feedback → Narrative emphasis → Decoration
```

Every motion token below is justified by one of the first four
categories. No token exists purely for decoration.

## Motion categories and responsibility split

| Category | Responsibility | Technology |
| --- | --- | --- |
| Entrance | Section/component first appearance | Framer Motion (`whileInView`) |
| Exit | Rare — used only where a state is genuinely replaced (e.g. Scene 4's finding resolution) | Framer Motion (`AnimatePresence`) |
| Emphasis | Highlighting a finding, a status change, a ranked result | Framer Motion (`animate`) |
| Transformation | Span→chunk assembly (Scene 5), file validation (Scene 3) | Framer Motion + light SVG |
| Progress | Evidence-flow strip (Scene 1), ranked list stagger (Scene 6) | Framer Motion (`staggerChildren`) |
| Provenance | The chunk↔source connector line (Scene 5), the traceability breadcrumb (Scene 8) | SVG (`pathLength`) driven by Framer Motion or GSAP depending on scene |
| Review decision | Human review gate unlock (Scene 4) | Framer Motion (`layout`) |
| Scroll timeline | Reverse traceability only (Scene 8) | GSAP + ScrollTrigger, desktop only |
| Hover / Focus | CTA buttons, cards | Framer Motion (`whileHover`/`whileFocus`) + native `:focus-visible` |
| Loading | Not applicable — landing has no async data fetching | — |
| Reduced motion | Every scene has a defined static equivalent | CSS `@media (prefers-reduced-motion: reduce)` + a shared `useReducedMotion` gate |

## Motion tokens

```ts
// Duration scale
fast: 150ms        // hover/focus feedback
standard: 260ms     // most entrances, chip flips
narrative: 550ms    // hero sequence, section reveals with multiple steps
// Scroll-scrubbed transformations (Scene 8) are scroll-position-driven,
// not duration-driven — see "Scrub rules" below.

// Easing
entrance: cubic-bezier(0.16, 1, 0.3, 1)   // "ease-out-expo" — confident, no bounce
emphasis: cubic-bezier(0.34, 1.16, 0.64, 1) // a restrained, single-overshoot spring-like ease, used ONLY for the review-decision unlock (Scene 4) — nowhere else, so it stays meaningful
exit: cubic-bezier(0.4, 0, 1, 1)

// Spring presets (Framer Motion)
snappy:  { type: "spring", stiffness: 380, damping: 32 }  // hover/focus
settle:  { type: "spring", stiffness: 210, damping: 26 }  // entrances

// Stagger
listItem: 60ms between children (Scene 1, Scene 6)
maxStaggerGroupSize: 6 items — beyond that, fall back to a single group fade (never stagger more than 6 discrete items; it stops reading as causal and starts reading as decoration)

// Scroll activation thresholds
whileInView margin: "-10% 0px -10% 0px" (fires slightly before full entry, not at the exact viewport edge)
whileInView once: true for every scene except Scene 8

// Maximum motion distance
translateY on entrance: 16px (never more — this is a clinical surface, not a marketing bounce)
translateX on Scene 3's channel: contained within the channel's own width, never off-screen

// Maximum blur
0 — no blur-based reveals anywhere on the landing page (blur is expensive and reads as decorative haze, explicitly against §5.4)

// Maximum scale
1.0 → 1.02 on hover only; never on entrance

// Pinning rules
Only Scene 8, only at ≥768px width, only via GSAP ScrollTrigger `pin: true`; pin duration is exactly the scene's own content height × a 4x scroll multiplier (~400vh) — never pins longer than needed to complete the 5-stage sequence

// Scrub rules
Scene 8 only: `scrub: 0.5` (slight smoothing, not instant, not laggy) tied to `ScrollTrigger` progress 0→1 mapped linearly across the 5 stages

// Reduced-motion alternatives
Every `whileInView`/stagger/pin/scrub in this document has a defined static replacement — see the per-scene "Reduced-motion equivalent" column in NOOR_LANDING_STORYBOARD.md. The mechanism: a single `useReducedMotion()` (Framer Motion's built-in hook, backed by the media query) read once per client island; when true, entrance variants render already-resolved and ScrollTrigger is never instantiated at all (not instantiated-then-disabled — never created, so no scroll listener attaches).
```

## Global rules

- No animation exceeds 700ms except the scroll-driven Scene 8 timeline, which is explicitly scroll-position-driven, not clock-driven.
- No section blocks initial content behind a required animation — every scene's final content exists in the DOM immediately (server-rendered where possible); motion only reveals/emphasizes, never gates comprehension.
- No `will-change` left persistently set; applied only for the duration of an active transform and removed on completion/unmount.
- Only `transform` and `opacity` are animated for anything triggered by scroll, to stay off the main thread's layout/paint cost.
- CTA buttons are never animated on entrance in a way that delays their availability — they are interactive the instant they're visible.
