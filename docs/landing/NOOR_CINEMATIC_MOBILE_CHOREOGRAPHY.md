# NOOR Cinematic Mobile Choreography

Status: **LX-1.1.1 — Complete.** LX-1.1's mobile experience was
explicitly rejected (mission §3.7): copy blocks overlapped during
transitions, multiple scene texts were visible simultaneously,
headings clipped, the final CTA clipped, and the canvas competed with
text — because mobile reused the desktop composition at a smaller
scale rather than an independently designed layout. Every defect below
was found via a real screenshot or a real DOM assertion, not assumed.

## The two-zone system

```
┌─────────────────────────────┐
│  Fixed nav (safe-area aware) │
├─────────────────────────────┤
│                             │
│   Visual zone (46vh)        │  ← fixed position, canvas or static illustration
│   The Evidence Core lives   │
│   here and only here        │
│                             │
├─────────────────────────────┤
│                             │
│   Copy zone (remaining vh)  │  ← normal document flow, one scene at a time
│   Headline / body / status  │
│   / CTA                     │
│                             │
└─────────────────────────────┘
```

`CinematicExperience.tsx`'s fixed background layer is
`h-[46vh] sm:h-auto` — on mobile it never exceeds the top 46% of the
viewport; on `sm:` and above it reverts to the desktop full-viewport
treatment. Every scene's `<section>` in `page.tsx` carries matching top
padding (`pt-[calc(46vh+1.5rem)] sm:pt-32`) so text never starts above
the visual zone's lower edge, on the very first section or any other.

## Real bugs found and fixed here (not assumed)

1. **Text centered in an oversized flex container clips at the viewport edge.** A screenshot at 35% scroll showed Scene 3's headline cut off at the top with "Available foundation" from an adjacent transition also visible — traced to `items-center` centering a text block inside an 8.5-viewport-height-tall section; for most of that section's scroll range, the centered point sits above or below the actual viewport. **Fixed** by making the text wrapper `position: sticky` (top offset matching the visual-zone height) instead of a flex-centered point — the standard scrollytelling technique, keeping copy fully visible for the section's entire scroll duration.
2. **Multiple scenes' text simultaneously visible — on desktop too, not just mobile.** The same screenshot proved this wasn't mobile-specific. **Fixed** by applying single-scene exclusivity (opacity + `aria-hidden` + `inert`) on every viewport whenever the GSAP timeline is active, not gated to mobile as LX-1.1.1's first pass assumed.
3. **A decorative icon collided with the nav for the first few percent of scroll on Scene 1 specifically.** Before any scrolling happens, a `position: sticky` element sits at its natural flow position, not yet at its stuck offset — Scene 1's content, with no preceding scroll, started flush against the page top. **Fixed** by giving every `<section>` (not just the sticky child) matching top padding.
4. **`aria-hidden` alone does not remove focusable content from the tab order.** A real `@axe-core/playwright` scan at 390/430/360px flagged `aria-hidden-focus`: Scene 7's "Sign in to NOOR" link stayed keyboard-reachable inside an `aria-hidden` wrapper whenever that scene wasn't current. **Fixed** with the native `inert` DOM property (set imperatively via a ref, since this TypeScript/React version's JSX types don't expose it as a prop), which removes both focusability and AT exposure together.
5. **The page had no `<h1>`** — axe's `page-has-heading-one` flagged this on mobile scans. Every scene used `<h2>`. **Fixed** by making Scene 1's headline the page's one `<h1>` (it genuinely is the page's thesis statement) and keeping Scenes 2–7 as `<h2>`.

## Independent mobile camera path

`MOBILE_CAMERA_PATHS` in `sceneConfig.ts` is hand-authored, not derived
by scaling `DESKTOP_CAMERA_PATHS` (LX-1.1's approach, and the literal
defect named in the rejection). Mobile keyframes start closer
(`z: 3.6` vs. desktop's `z: 4.6`), travel less laterally, and use a
narrower FOV range — see `NOOR_CINEMATIC_CAMERA_MAP.md` for the full
table.

## Reduced particle/geometry budget

Mobile uses the `balanced` or `static` quality tier by default
(`useInitialQualityTier()` checks viewport width alongside
`navigator.hardwareConcurrency`) — fewer particles (380 vs. 850),
`antialias: false`, capped device-pixel-ratio at 1.5.

## Verified viewports

430×932, 390×844, 360×800 — all three confirmed via real DOM
assertions (not just visual inspection): exactly one
`[data-scene-active="true"]` element at any time, zero horizontal
overflow, the final CTA's bounding box fully inside the viewport at
99% scroll, and 0 `@axe-core/playwright` violations. See
`docs/verification/lx-1-1-1-cinematic-polish-verification.md` for the
exact numbers and screenshot paths.
