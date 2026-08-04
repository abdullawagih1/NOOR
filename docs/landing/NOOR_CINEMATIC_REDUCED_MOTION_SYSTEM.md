# NOOR Cinematic Reduced-Motion System

Status: **LX-1.1.1 — Complete.** LX-1.1's reduced-motion path was a
single CSS gradient with no content — the exact "reduced motion is
mostly empty" defect named in the rejection (mission §3.8). This
document records the real replacement system.

## Architecture

`StaticPoster.tsx` (rendered whenever motion is inactive — reduced
motion, low-power/static quality tier, or WebGL unavailable) now reads
`useVisibleSceneId()` and renders that scene's complete
`ReducedMotionIllustration`, positioned in its own visual zone
(mirroring the motion-enabled layout's canvas/text split).

```
StaticPoster
 └─ useVisibleSceneId(7)         ← plain IntersectionObserver, no GSAP
      └─ ReducedMotionIllustration({ sceneKey })
           └─ one complete, hand-built SVG per scene
```

## Why a separate scroll-tracking hook was necessary

`useMasterTimeline` only creates a `ScrollTrigger` when motion is
active (`useMasterTimeline(motionActive, contentRef)`) — in reduced
motion, `timelineStore.sceneIndex` never advances past 0. A real
consequence of this was caught during verification, not assumed: the
nav's scene-progress dots and `aria-live` announcement stayed
permanently stuck on "Scene 1" regardless of real scroll position,
while the illustration (already using the correct hook) showed the
right scene — a genuine accessibility inaccuracy (screen readers would
announce the wrong scene). **Fixed** by having `CinematicNav` also
fall back to `useVisibleSceneId()` whenever `useMotionActive()` is
false, matching the illustration's source of truth.

`useVisibleSceneId` uses a plain `IntersectionObserver` on the real,
server-rendered `<section id="scene-N">` elements — mission §23's "no
scrub timeline" in this path, honored structurally (there is no GSAP
import anywhere on this code path at all).

## Per-scene illustrations (`ReducedMotionIllustrations.tsx`)

Every element mission §23 explicitly lists is present as a real SVG,
not a small icon:

| Scene | Illustration content |
| --- | --- |
| Trusted Source | 4 layered document planes + a page-marking texture pattern + a "Source registered — verified" checkmark badge |
| Secure Intake | The verification gateway ring with a valid document inside (checkmark) AND a second, separate rejected document with an explicit "×" and "Invalid source — stopped" label — both paths shown, not just the happy path |
| Human Review | Two side-by-side panels (original page / extracted representation) with visible line placeholders, a highlighted finding region on each, and an "accepted, path unlocked" checkmark |
| Structured Knowledge | The source page with 3 highlighted spans, each connected by a real line to a labeled "Chunk N" block |
| Retrieval | A query arrow entering 3 ranked candidate cards, each with a numbered badge (1/2/3) and a relevance score, plus dashed connector lines back to the query |
| Product Vision | The workspace panel with a synthetic statement, a "Product vision" ribbon, and 3 connected evidence-link blocks |
| Reverse Traceability | All 6 layers stacked as a single connected list (Intelligence statement → Supporting evidence → Retrieved chunk → Exact source span → Original page → Trusted guideline), each with a circular marker and a connecting line to the next — the complete chain in one static diagram |

## Content equivalence

Every scene's real, server-rendered headline/body/status-label/CTA
text is identical in the reduced-motion path — `page.tsx` renders one
DOM tree for both paths; only the fixed background layer's content
(canvas vs. illustration) differs. Nothing is reduced-motion-exclusive
content, and nothing is hidden from the motion-enabled path.

## What reduced motion never does

Camera movement, object morphing, particles, parallax, `ScrollTrigger`
pinning, or scroll-scrubbing — confirmed directly: `canvas` element
count is 0 in every reduced-motion Playwright check in this mission's
verification report, meaning `CinematicCanvas` (and therefore `three`,
`gsap`, and `ScrollTrigger`) never even loads on this path.
