# Sprint Current: LX-1.1 — High-Fidelity Cinematic Landing Prototype

**Status:** LX-1.1 — High-Fidelity Cinematic Prototype Complete,
Pending User Visual and Motion Approval. See
`docs/verification/lx-1-1-cinematic-prototype-verification.md` for the
full record, including a genuine upstream library incompatibility that
forced a mid-mission architecture pivot, and 4 real bugs found and
fixed (3 hydration mismatches + a missing LCP `priority` hint).

This is a **separate, dedicated landing-experience workstream** — not
a platform sprint. It does not touch the database, RLS, permissions,
Worker, or any backend code, and it does not replace the production
`/` landing page. Workstreams `S1-A` through `S1-E2`, `UX-1`/`UX-1.1`,
and `LX-1.0` remain closed exactly as previously verified; the
platform's next step is still `S1-E3 — Hybrid Retrieval` (unchanged).
LX-1.0's own gallery route (`/design/landing-experience`) is preserved
untouched, per this mission's own instruction, as a technical state
reference — it is not the shipped direction.

## What this workstream does

The user explicitly rejected LX-1.0's prototype gallery as
insufficient ("card → Play button → step change → static frame").
LX-1.1 replaces it with a real, continuous, scroll-driven cinematic
3D experience at a new Development-only route
(`/design/cinematic-landing`, 404s in production): one persistent
"Evidence Core" 3D object that visibly transforms across 7 narrative
scenes — trusted source, secure intake, human review, structured
knowledge, retrieval, product vision, and a signature reverse-
traceability finale — with real camera choreography driven by page
scroll (GSAP `ScrollTrigger`), never a nested scroller and never a
Play button.

## The real blocker and pivot

`@react-three/fiber` (the mission's specified 3D library) was
installed, integrated, and found genuinely non-functional in this
exact stack: every canvas mount crashed with `TypeError: Cannot read
properties of undefined (reading 'ReactCurrentOwner')`. This was
root-caused through 6 documented attempts (dependency version bumps,
webpack aliasing, `transpilePackages`, removing the dynamic-import
boundary) before `WebSearch`/`WebFetch` research confirmed it against
multiple independent GitHub reports of the exact same crash on the
exact same React 18.3.1 + Next.js 15.x + `@react-three/fiber` 8.17–8.18
combination — a currently-unresolved upstream incompatibility, not a
local misconfiguration. The library maintainer's own fix requires
React 19, an unacceptable whole-app risk for one prototype route.

**Resolution:** `@react-three/fiber`/`@react-three/drei` were removed;
`three` was kept. The Evidence Core is built with plain, imperative
Three.js (a class with `update()`/`dispose()` methods, no custom React
renderer) — zero dependency on `react-reconciler`, so the bug class
cannot occur. Every geometry/camera/lighting design decision is
unchanged from the original plan; only the rendering technique
differs. Full account: `docs/landing/NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md`.

## Objectives

- [x] Audit LX-1.0's gallery and record why it doesn't satisfy the approved direction.
- [x] Install, integrate, root-cause-fail, and remove `@react-three/fiber`/`@react-three/drei`; ship raw `three` instead — `docs/landing/NOOR_LANDING_THREEJS_DECISION.md` amended, not silently rewritten.
- [x] 9 new planning docs: cinematic concept, Evidence Core geometry design, camera map, scene timeline, technical architecture, performance budget, accessibility plan, mobile strategy, fallback strategy.
- [x] Evidence Core built: document stack, verification ring + invalid-path object, review gate with a real scroll-gated lock/unlock, structured blocks + provenance threads, retrieval ranking + query beam, product-vision workspace panel, particle field, 3-light system with state-driven color.
- [x] Master scroll timeline (one `ScrollTrigger`, bound to the real content wrapper's natural height — no artificial spacer, no nested scroller).
- [x] Real, server-rendered, unconditional text content for all 7 scenes — no duplicate floating-text layer.
- [x] Reduced-motion, mobile, low-power, and WebGL-unavailable paths all converge on one static fallback (`StaticPoster` + the same real section content) — confirmed 0 canvas elements in that path.
- [x] Debug mode (`?debug=1`, dev-only) with live scene/progress/FPS/quality-tier readout.
- [x] 3 real hydration-mismatch bugs found (via Next's dev overlay, not inspection) and fixed.
- [x] Route isolation verified directly (grep of compiled chunks, not inferred from size) — `three` reaches only this one route.
- [x] Production route protection verified on a real server (`curl` 200 on `/`, 404 on the new route); `next.config.mjs` confirmed byte-identical to its pre-mission state.
- [x] 14 calibrated motion-state screenshots + 3 real video recordings (desktop/mobile/reduced-motion journeys).
- [x] `@axe-core/playwright` scans: 0 violations across desktop/reduced-motion/mobile/RTL/WebGL-disabled.
- [x] Lighthouse (production `/` unaffected; cinematic route measured against dev server, the only place reachable pre-launch, with the numbers honestly caveated).
- [x] FPS measured and investigated (confirmed headless SwiftShader software rendering, not real hardware) and a memory-growth finding investigated to its real (dev-server-artifact) root cause rather than accepted at face value.
- [x] Full `apps/web`/`packages/ui`/`packages/clinical-schemas` verification — all clean.
- [x] Status docs updated (this file, PROJECT_STATE, MASTER_BACKLOG, CHANGELOG, KNOWN_LIMITATIONS).

## Real bugs found and fixed this workstream

1. The `@react-three/fiber` v8 + Next.js 15 incompatibility itself (§ above) — not a "bug" in this codebase, but a genuine, researched, cited upstream blocker that forced a real architecture decision.
2–4. Three hydration mismatches, all the same root cause: `useReducedMotion()` resolves synchronously on the client's first render while SSR always assumes no preference. Found in `CinematicNav.tsx` (a structural mismatch — an entire `<label>` present/absent), `CinematicExperience.tsx` (canvas-vs-static-poster branch), and `SceneSectionReveal.tsx` (an attribute mismatch, `opacity`/`transform`, reproduced identically across all 7 scene sections). All fixed with the same `mounted`-gate pattern. This pattern may exist elsewhere in `apps/web` — not audited this mission, recorded in `KNOWN_LIMITATIONS.md`.
5. A missing `priority` hint on the nav logo, the page's actual LCP element — a real, correctly-flagged Next.js warning, fixed.

## Next step

```text
User review of the complete cinematic prototype and recorded motion
```

Do not start production landing implementation (LX-1.2) automatically.
The platform's own next step remains `S1-E3 — Hybrid Retrieval`,
unaffected by this workstream.
