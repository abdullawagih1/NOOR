# NOOR Landing Technical Architecture

Status: **LX-1.0 — In Progress**

## Guiding shape

```
Server-rendered landing content
→ Small client animation islands
→ Framer Motion for component interaction
→ GSAP only for the Section 8 timeline
```

The landing page (when built in LX-1.2) remains a Server Component at
its root — headline text, copy, structural markup, and metadata are
all server-rendered HTML, matching the production `/` page's current
approach exactly. The page is **not** converted into one large Client
Component.

## Server Component boundaries

- Page shell, all headline/body copy, section structure, `PublicShell` header/footer: Server Components.
- Each scene's *static content* (labels, status chips' text, accessible names) is server-rendered; only the *animation behavior wrapping it* is a Client Component.

## Client animation-island boundaries

One small `"use client"` wrapper per scene (`HeroEvidenceFlow`,
`SourceVerificationScene`, `SecureIntakeScene`, `HumanReviewScene`,
`StructuredKnowledgeScene`, `RetrievalScene`, `VisionScene`,
`TraceabilityTimeline`, `GovernanceGrid` — governance/final-CTA scenes
may not need a client boundary at all, since their motion is a single
`whileInView` fade that could alternatively ship via a shared
`MotionBoundary` helper). Each island:

- Receives fully-formed content as props/children from its Server Component parent — it animates content, it does not fetch or own it.
- Reads `useReducedMotion()` once, at the top, and branches its own internal variants — never a second component tree.
- Cleans up on unmount (relevant to Scene 8's GSAP/ScrollTrigger instance specifically; Framer Motion components clean up automatically as part of React's unmount lifecycle).

## Framer Motion responsibility

Scenes 1–7, 9, 10 — all entrances, staggers, layout transitions, hover/
focus states, and their reduced-motion variants (`useReducedMotion`).

## GSAP responsibility

Scene 8 only. `gsap` + `ScrollTrigger` are dynamically imported
(`next/dynamic` with `ssr: false`, or a lazy `import()` inside a
`useEffect`) so they never enter the initial bundle for visitors who
never scroll that far, and never load at all for reduced-motion/mobile
visitors who get the static alternative instead.

## IntersectionObserver / ScrollTrigger usage

- Scenes 1–7, 9, 10: Framer Motion's `whileInView` (backed internally by `IntersectionObserver`) — no manual observer code needed.
- Scene 8: `ScrollTrigger.create({ trigger, pin: true, scrub: 0.5, start, end })`, destroyed via `ScrollTrigger.getById(...).kill()` (or the returned instance's `.kill()`) in the component's cleanup function — verified by a dedicated test (see §Testing approach).

## Dynamic imports

```ts
// TraceabilityTimeline.tsx — illustrative shape, implemented in the prototype route
const gsapModulePromise = import("gsap");
const scrollTriggerModulePromise = import("gsap/ScrollTrigger");
```

Loaded only when: (a) the viewport is ≥768px, and (b)
`prefers-reduced-motion` is not set to reduce. Both conditions are
checked before the dynamic import fires, not after.

## Hydration behavior

Every scene's server-rendered HTML already contains the resolved,
readable content (final text, final labels). Client hydration attaches
*behavior* (the animation), never *content* — so a visitor whose JS is
slow, blocked, or disabled still sees a complete, correctly-ordered
page; they simply see it without motion, which is functionally
identical to the reduced-motion path.

## Reduced-motion detection

A single shared hook, `useNoorReducedMotion()` (thin wrapper over
Framer Motion's `useReducedMotion`), used by every client island. CSS
also carries a parallel `@media (prefers-reduced-motion: reduce)` block
for anything expressed in pure CSS (e.g., the hover `scale(1.02)`),
so the guarantee holds even before JS hydrates.

## Cleanup and unmount behavior

- Framer Motion: automatic.
- GSAP/ScrollTrigger (Scene 8 only): explicit `.kill()` in a `useEffect` cleanup; verified by the prototype gallery's route-unmount/remount test (§31 of the mission) — navigating away from and back to the prototype route must not accumulate duplicate ScrollTrigger instances or leak listeners.

## Mobile fallbacks

Every scene's mobile fallback is defined per-scene in
`NOOR_LANDING_STORYBOARD.md`. Architecturally, this means:
`useReducedMotion() || !isDesktopViewport` collapses to the same static
code path — mobile does not get its own separate implementation of
Scene 8; it reuses the exact reduced-motion component tree.

## Testing approach

- Component-level: no dedicated unit-test framework exists for `apps/web` beyond the `tsx`-run script files already used for schema/error tests (see `apps/web/package.json`'s `test` script) — landing components are verified through the Playwright prototype-gallery checks in §31/§32 of the mission instead, matching this repository's established practice of favoring real browser verification over component unit tests for UI work.
- Browser-level: ad hoc Playwright capture scripts (matching the pattern established in every prior sprint's screenshot evidence), run against the Development-only prototype route, producing the evidence catalogued in the verification report.

## Bundle strategy

- `framer-motion`: imported directly inside each client island (tree-shakes to only the primitives used); never imported from a Server Component.
- `gsap`/`ScrollTrigger`: dynamically imported, Scene 8 only, gated by viewport + reduced-motion checks as above.
- No animation library is imported from `apps/web/app/layout.tsx` or any shared root-level module — a visitor who never scrolls past the hero never downloads GSAP at all.
