# NOOR Cinematic Art Direction

Status: **LX-1.1.1 — Complete.** This is the corrective art-direction
record for the polish pass that followed LX-1.1's rejected "cinematic
motion proof of concept." Every decision below maps to a specific
user-named defect (mission §3) and its concrete fix.

## Starting point: what was rejected and why

| Rejected issue (mission §3) | Root cause in the LX-1.1 code | Fix |
| --- | --- | --- |
| Debug UI visible in acceptance media | The *acceptance recording script itself* passed `?debug=1` to every video — the product code already correctly hid the overlay by default | Removed `?debug=1` from every acceptance recording; exposed a harmless `window.__noorCinematicTimeline` test global (mission §37) so verification scripts don't need the debug UI at all |
| Weak Evidence Core identity | The core was a document stack + a separate, unrelated verification ring/lock/blocks — no persistent, recognizable silhouette | Rebuilt as one object: two page-layer towers ARE the N-mark's two verticals, connected by one diagonal "evidence bridge" thread and one central "aperture" that plays a different role per scene — see `NOOR_EVIDENCE_CORE_DESIGN.md` |
| Core too small and too dark | Scene 1's camera started at `z: 6.5`, ambient light intensity 0.55 | Camera now starts at `z: 4.6` (holds even closer, `z: 3.3`, by the scene's end); ambient 0.85, key light 1.9 (up from 1.1), a new fill light added |
| Dashboard-like typography | `text-2xl`/`text-3xl` inside a `backdrop-blur` card with a dark semi-transparent background box | Fluid `clamp(2.1rem, 4.6vw, 4rem)` headline, no boxed card — a directional gradient wash instead |
| Weak first three scenes | Single ring/lock objects with little camera engagement | Scene 2 now has 4 distinct sequential verification nodes; Scene 3's aperture lock is now the same persistent object used throughout, with a real emerald pulse and a fixed, honored accept-threshold |
| Reverse traceability not a signature interaction | Camera silently reused Scenes 6→1's keyframes with no distinct per-layer marker | A dedicated traceability marker (ring) + DOM label now tracks each of the 6 named layers explicitly |
| Mobile layout not accepted | Desktop camera/text positions scaled down; canvas full-viewport, competing with text | Independent mobile camera keyframes (never scaled); a fixed 46vh visual zone + a separate copy zone below it — see `NOOR_CINEMATIC_MOBILE_CHOREOGRAPHY.md` |
| Reduced motion visually incomplete | `StaticPoster` was a plain gradient, no content | Full per-scene SVG illustrations, tracked by real scroll position via `IntersectionObserver` — see `NOOR_CINEMATIC_REDUCED_MOTION_SYSTEM.md` |
| Logo and navigation too weak | A single small logo image, no wordmark | Logo + a real "NOOR / Clinical Intelligence OS" text wordmark, larger, with safe-area padding |
| Recording too fast | Camera moved continuously across each scene's full range | `holdThenMove()` — camera holds for ~55% of a scene, moves in the remaining ~45%; total scroll distance widened 6→8.5 desktop viewport-heights |
| Real-GPU performance not verified | LX-1.1's FPS/Lighthouse numbers were measured on headless SwiftShader | Confirmed this machine's real Intel GPU is reachable from headless Chromium via `--use-gl=angle --use-angle=gl --ignore-gpu-blocklist --enable-gpu-rasterization`; all LX-1.1.1 performance numbers are real-GPU, real-production-build measurements |

## Color and lighting (unchanged palette, changed intensity)

The brand palette itself did not change — `packages/ui/tokens/colors.ts`
remains the sole source. What changed is contrast and intensity:
ambient light raised from 0.55→0.85, key light 1.1→1.9, a new fill
point light added, and the aperture's emissive intensity raised
substantially at the accepted/verified state so the "verification
pulse" reads as a genuine event, not a subtle tint shift. Deep Navy
environment, Clinical Blue key light, Teal provenance, Emerald
verification, Soft Cyan atmosphere — same five-color system as
`NOOR_CINEMATIC_CONCEPT.md`, applied with more contrast.

## Typography

Editorial scale via fluid `clamp()`, no fixed pixel jump between
breakpoints: scene headlines run `clamp(2.1rem, 4.6vw, 4rem)` (~34–64px
depending on viewport), matching the mission's 52–72px desktop target
closely while staying legible on narrow viewports without a separate
mobile-only class. The final CTA heading uses `clamp(1.9rem, 3.6vw,
3.25rem)`. No boxed card — text sits directly over the scene with a
soft directional gradient wash for contrast, matching mission §9's
explicit rejection of "small floating cards for primary narrative
copy."

## What stayed exactly the same

The seven-scene narrative arc, the brand palette, the "no
@react-three/fiber" architecture decision, the Development-only route
gating (extended, not replaced, with the Preview exception — see
`NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md`), and the underlying
provenance-thread/particle-field visual language from
`NOOR_EVIDENCE_CORE_DESIGN.md`. This was an art-direction and
choreography correction, not a re-architecture.
