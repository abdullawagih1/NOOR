# Sprint Current: LX-1.1.1 — Cinematic Art Direction, Mobile Choreography, and Motion Polish

**Status:** LX-1.1.1 — Cinematic Polish Implementation Complete,
Pending User Visual and Motion Approval. See
`docs/verification/lx-1-1-1-cinematic-polish-verification.md` for the
full record.

This is a **corrective pass on the same separate, dedicated
landing-experience workstream** as LX-1.1 — not a platform sprint. It
does not touch the database, RLS, permissions, Worker, or any backend
code, and it does not replace the production `/` landing page.
Workstreams `S1-A` through `S1-E2`, `UX-1`/`UX-1.1`, `LX-1.0`, and
`LX-1.1` remain closed exactly as previously verified; the platform's
next step is still `S1-E3 — Hybrid Retrieval` (unchanged).

## Why this pass exists

The user reviewed LX-1.1's real video/screenshot evidence and rejected
it across every dimension: weak Evidence Core identity, the core too
small and too dark, dashboard-like typography, weak early scenes,
reverse traceability not reading as a signature interaction, a mobile
layout with real copy overlap/clipping, a reduced-motion path that was
visually empty, weak logo/nav, recordings that moved too fast, and
real-GPU performance that had never actually been measured (LX-1.1's
numbers came from headless SwiftShader software rendering, explicitly
caveated as unrepresentative at the time). Full before/after mapping:
`docs/landing/NOOR_CINEMATIC_ART_DIRECTION.md`.

## Objectives

- [x] Redesign the Evidence Core as one persistent, recognizable object: two page-layer towers forming the N-mark's two verticals, a diagonal evidence-bridge thread, and a central aperture playing three roles (review lock → query entry → workspace anchor) across scenes.
- [x] Bigger, brighter core: camera starts at `z:4.6` (was `z:6.5`); ambient 0.55→0.85, key light 1.1→1.9, new fill light.
- [x] Editorial typography: fluid `clamp()` headlines, no boxed/dashboard-style card.
- [x] `holdThenMove()` camera pattern — ~55% hold / ~45% move per scene; total scroll distance widened 6→8.5 desktop viewport-heights (answers "recording too fast").
- [x] Reverse traceability made a signature interaction: 6 named layers, each with a real moving marker + DOM label, not a label fade.
- [x] Independent mobile camera path (hand-authored, not scaled from desktop) + two-zone layout (46vh visual zone / copy zone below).
- [x] Universal single-scene exclusivity (not mobile-only), gated by a new `MotionActiveContext` so reduced motion is never affected.
- [x] Complete per-scene SVG illustrations for reduced motion (`ReducedMotionIllustrations.tsx`), tracked via a new `useVisibleSceneId()` `IntersectionObserver` hook.
- [x] Nav/logo polish: symbol + wordmark + descriptor, safe-area padding; nav falls back to `useVisibleSceneId()` in reduced motion (fixes a real stuck-on-Scene-1 bug).
- [x] `NOOR_CINEMATIC_PREVIEW_ENABLED` Preview-only production-build gate (server-side, orthogonal to Vercel Deployment Protection) + `export const dynamic = "force-dynamic"` (fixes a real `useSearchParams()` static-export failure and a real build-time-baked-env-var bug).
- [x] Real-GPU access from headless Chromium confirmed directly (`ANGLE (Intel, Intel(R) RaptorLake-S Mobile Graphics Controller, OpenGL 4.5.0)`, not SwiftShader) and used for all FPS/Lighthouse measurement.
- [x] Two real accessibility violations found via `@axe-core/playwright` and fixed: `aria-hidden-focus` (native `inert` DOM property) and `page-has-heading-one` (Scene 1's headline is now a real `<h1>`).
- [x] 7 clean acceptance recordings, none with `?debug=1` — a genuine Playwright browser-reuse bug (all-black frames) found via `ffmpeg` frame extraction and fixed.
- [x] 8 planning docs written/updated + master verification report.
- [x] Committed Preview-gate regression test (`apps/web/tests/cinematic-preview-gate.test.ts`).
- [x] Full `apps/web` (22 tests)/`packages/clinical-schemas` (6 tests) verification, typecheck, and lint — all clean.
- [x] Status docs updated (this file, PROJECT_STATE, MASTER_BACKLOG, CHANGELOG, KNOWN_LIMITATIONS).
- [x] React Three Fiber explicitly **not** retried, per this mission's own instruction — plain imperative Three.js architecture from LX-1.1 unchanged.

## Real bugs found and fixed this workstream

1. Desktop text overlap/clipping — not just mobile. Root cause: `items-center` centering a text block inside an oversized (8.5-viewport-height) section, so the centered point sat outside the viewport for most of the scroll range. Fixed with `position: sticky` replacing flex-centering.
2. Multiple scenes' text visible simultaneously on every viewport (single-scene exclusivity had not existed at all). Fixed, then had to be re-gated behind `MotionActiveContext` after reasoning through the consequence for reduced motion (`sceneIndex` never advances there) — caught before shipping, not via a failed test.
3. Reduced-motion nav stuck permanently on "Scene 1" while the illustration correctly advanced — a real accessibility inaccuracy (wrong scene announced to screen readers). Fixed by having the nav share the illustration's `useVisibleSceneId()` source of truth.
4. `aria-hidden-focus` axe violation — hidden sections' links stayed keyboard-focusable. Fixed with the native `inert` DOM property (set imperatively via ref; not in this TS/React version's JSX prop types).
5. `page-has-heading-one` axe violation — every scene used `<h2>`, zero `<h1>` on the page. Fixed by promoting Scene 1's headline.
6. `next build` failure the first time the Preview flag let real prerendering happen: `useSearchParams()` requires a Suspense boundary for static export. Fixed with `export const dynamic = "force-dynamic"`.
7. A statically-exported page bakes in the Preview env var's build-time value permanently — confirmed directly (setting it only at server-start had no effect after a build without it). Fixed by the same `force-dynamic` change.
8. Debug overlay (`?debug=1`) correctly hard-disabled in production, which blocked verification scripts from reading state against the Preview build. Fixed by exposing a harmless `window.__noorCinematicTimeline` test-safe global unconditionally.
9. 5 of 7 acceptance video recordings were all-black — confirmed via `ffmpeg` frame extraction, not assumed from file size. Root cause: reusing one GPU-flagged `chromium.launch()` browser instance across sequential `recordVideo` contexts. Fixed by giving each recording its own fresh browser launch.

## Next step

```text
User review of the clean desktop, mobile, reduced-motion, and
reverse-traceability recordings
```

Do not start production landing implementation (LX-1.2) automatically.
The platform's own next step remains `S1-E3 — Hybrid Retrieval`,
unaffected by this workstream.
