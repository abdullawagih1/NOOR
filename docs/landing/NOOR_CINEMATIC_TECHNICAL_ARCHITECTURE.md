# NOOR Cinematic Technical Architecture

Status: **LX-1.1 — Complete.** This document was revised mid-mission
after a real, reproduced blocker — see §"Why raw Three.js, not React
Three Fiber" — so it describes what actually shipped, not the original
plan.

## Why raw Three.js, not React Three Fiber

The mission specified React Three Fiber. It was installed
(`@react-three/fiber@8.18.0`, `@react-three/drei@9.122.0`, matched to
this repo's React 18.3.1 since fiber v9 requires React 19) and
integrated exactly as planned. It did not work: mounting the `<Canvas>`
inside this Next.js 15.5.21 app crashed every time with `TypeError:
Cannot read properties of undefined (reading 'ReactCurrentOwner')`
inside `react-reconciler`'s renderer-creation call.

This was root-caused, not guessed around. In order:

1. Confirmed no duplicate `react`/`react-dom` copies (`npm ls react` — single deduped 18.3.1 everywhere).
2. Bumped `react-reconciler` to `0.29.2` (the exact version whose own `peerDependencies` declares `react: ^18.3.1`) via an override — same crash, identical line number.
3. Tried a webpack `resolve.alias` forcing every chunk to the same on-disk `react`/`react-dom` — first attempt (aliasing to `require.resolve()`'s file path) broke `react/jsx-runtime` resolution entirely (`Module not found`); the corrected version (aliasing to the package directory) then broke **every server-rendered page** (`(0, _react.cache) is not a function`) because it also applied to Next's server compilation, which needs Next's own `react-server`-condition build; scoping the alias to `!isServer` only fixed the server breakage — the original canvas crash remained, unchanged.
4. Tried `transpilePackages: ["three", "@react-three/fiber", "@react-three/drei"]` (the R3F docs' own official Next.js guidance, which only mentions `three`) — no change.
5. Removed the dynamic-import boundary entirely (static top-level import instead of `next/dynamic`) to test whether the async chunk boundary itself was the cause — same crash, ruling that out.
6. At that point, `WebSearch`/`WebFetch` research (not guessing) found multiple GitHub issues (`vercel/next.js#71836`, `#66468`; `pmndrs/react-three-fiber#3417`, `#3440`, `#3446`) reporting the **exact same crash on the exact same stack** — React 18.3.1 + Next.js 15.0–15.6 + `@react-three/fiber` 8.17–8.18. The library maintainer's own response on `#3440`: *"react-three-fiber v8 does not support React 19. We have a v9 release candidate which does."* Several reporters explicitly confirmed they were on React 18, not 19, and hit it anyway — this is a genuine, currently-unresolved upstream incompatibility between `@react-three/fiber` v8's `react-reconciler` usage and Next.js 15's webpack/RSC client-boundary bundling, independent of the installed React major. The only fixes anyone reported were adopting React 19 (a whole-app major version change, out of scope for one prototype route and risky for the rest of this product) or downgrading Next.js (same problem, inverted).

Given neither option was acceptable for a single Development-only
route, the fix was to stop depending on `react-reconciler` at all:
**`@react-three/fiber` and `@react-three/drei` were uninstalled**;
`three` was kept. The Evidence Core is built and animated with plain,
imperative Three.js — a `THREE.Scene`/`THREE.PerspectiveCamera`/
`THREE.WebGLRenderer` owned by a `useRef`, updated inside a
`requestAnimationFrame` loop the component owns directly. This has
zero dependency on any custom React renderer, so the entire bug class
cannot occur. Every geometry, material, camera keyframe, and lighting
decision in `NOOR_EVIDENCE_CORE_DESIGN.md` and
`NOOR_CINEMATIC_CAMERA_MAP.md` is unchanged — only the rendering
technique is different from the original plan.

## Route structure (as shipped)

```
apps/web/app/design/cinematic-landing/
  page.tsx                     Server Component — gated notFound() in production,
                                renders every scene's real, unconditional HTML content
  sceneConfig.ts                Scene boundaries + camera keyframes (framework-agnostic data)
  timelineStore.ts              Tiny external store bridging GSAP -> React/canvas (no new dep)
  useMasterTimeline.ts          GSAP ScrollTrigger bound to the real content wrapper's height
  useTimelineState.ts           useSyncExternalStore read for React (DOM text/nav)
  useQualityTier.ts             coarse device-capability detection + FPS probe
  webglSupport.ts                one-time WebGL availability check
  CanvasErrorBoundary.tsx       catches construction/render failures, falls back to static
  CinematicExperience.tsx       "use client" — owns the motion/static decision, mounts
                                 the fixed background layer + the real content wrapper
  CinematicCanvas.tsx            "use client", dynamically imported — owns a <canvas> ref,
                                 constructs EvidenceCoreScene, runs its own RAF loop
  EvidenceCore/
    EvidenceCoreScene.ts          plain TS class: builds all geometry/materials/lights once,
                                   exposes update(deltaSeconds) and dispose() — no React/JSX
    provenanceThread.ts           plain function building a Mesh (not a component)
    easing.ts                     activation() smoothstep helper (framework-agnostic)
  overlays/
    CinematicNav.tsx, StatusChip.tsx, FinalCta.tsx,
    SceneIllustration.tsx, SceneSectionReveal.tsx (Framer Motion)
  StaticPoster.tsx               CSS-gradient background for the pre-WebGL/fallback paths
  DebugOverlay.tsx               ?debug=1 only, dev-only
```

## Server/client boundaries

`page.tsx` is a Server Component. It renders, unconditionally and in
DOM order, every scene's real headline, supporting copy, status chip,
and (for Scene 7) the final CTA — there is no separate "duplicate"
floating text layer. The fixed 3D canvas renders **behind** this real
content (`position: fixed; inset: 0; z-index: 0`), visible through the
semi-transparent panel each section's text sits on. This avoids the
duplication problem a floating-overlay-plus-separate-accessible-copy
design would have created, and matches the mission's own requirement
that "no content [is] injected only after a scroll-triggered animation
resolves."

`CinematicExperience.tsx` is the one real client boundary. It:
- Reads `useEffectiveReducedMotion()` (same hook as LX-1.0's gallery, reused via a relative import — not duplicated) and `useInitialQualityTier()`.
- If reduced motion, low-power, or WebGL is unavailable: renders `<StaticPoster>` only — `CinematicCanvas` (and therefore `three`) is never imported in this branch, via `next/dynamic(() => import("./CinematicCanvas"), { ssr: false })` gated behind the same condition, so the bundle is never fetched.
- Otherwise mounts `CinematicCanvas` behind the real, scrolling content — the master timeline (`useMasterTimeline`) is bound to that real content wrapper's own natural height (`end: "bottom bottom"`), not an artificial spacer.

## Three.js responsibilities (raw, not R3F)

Exactly: `EvidenceCoreScene`'s constructor builds every mesh/material/
light/particle field once; its `update(deltaSeconds)` method (called
once per RAF frame by `CinematicCanvas`) reads `getTimelineState()`
directly (a plain object read, not a React re-render) and mutates
transforms/materials in place — the same per-scene activation logic
originally planned for `useFrame`, just called imperatively.
`resize()` and `dispose()` are called from `CinematicCanvas`'s
`ResizeObserver` and cleanup effect respectively. No readable text is
ever drawn inside the canvas.

## GSAP responsibilities

One `ScrollTrigger` (`useMasterTimeline.ts`), bound to the real content
wrapper (`start: "top top"`, `end: "bottom bottom"`, `scrub: 0.5`).
`onUpdate` writes `{ progress, sceneIndex, sceneLocalProgress }` into
`timelineStore.ts` — a small subscribable object (no new state-
management dependency), read by `EvidenceCoreScene.update()` directly
and by React text/nav components via `useSyncExternalStore`. Exactly
one master timeline, per the mission's explicit requirement.

## Framer Motion responsibilities

`SceneSectionReveal` (per-section entrance, identical component used
for both motion-enabled and reduced-motion — Framer's own
`useReducedMotion` collapses it to an instant reveal automatically),
`CinematicNav`'s scene-progress dots and reduced-motion toggle, and the
final CTA's link styling. Framer Motion never touches the canvas.

## Dynamic imports

```ts
const CinematicCanvas = dynamic(() => import("./CinematicCanvas").then((m) => m.CinematicCanvas), {
  ssr: false,
  loading: () => null, // the CSS-gradient poster underneath is already visible
});
```
Loaded only inside the branch that already decided motion is enabled,
quality tier is not `static`, and WebGL is available.

## Quality tiers

`useInitialQualityTier()` returns `'high' | 'balanced' | 'static'` from
coarse signals only (no fingerprinting): viewport width,
`navigator.hardwareConcurrency`/`navigator.deviceMemory` where
available. A one-time 60-frame FPS probe (`probeFrameRate`) runs after
first mount and can downgrade `high`→`balanced` (if under 50fps) or
`balanced`→`static` (if under 30fps) — never upgrades. `'static'` is
also forced immediately, no probe needed, when reduced motion is
requested, viewport is very small, or `isWebglAvailable()` returns
false.

## Cleanup behavior

`useMasterTimeline`'s `ScrollTrigger` instance is `.kill()`ed in a
`useEffect` cleanup. `CinematicCanvas`'s RAF loop is cancelled and
`EvidenceCoreScene.dispose()` (which traverses the scene graph
disposing every geometry/material and calls `renderer.dispose()`) runs
on unmount — verified directly (not assumed) by a repeated route
mount/unmount memory check in the verification report.

## Route isolation

`three` is imported **only** inside `CinematicCanvas.tsx` and
`EvidenceCore/*` — never from `apps/web/app/layout.tsx`,
`PublicShell.tsx`, or any shared component. Verified directly: the
compiled `.next/static/chunks/` output contains `three`-referencing
code in exactly two chunk files, neither of which is referenced by any
other route's page chunk (checked by grepping every other route's
compiled page chunk for those chunk hashes — zero matches). See the
verification report for the exact commands and output.
