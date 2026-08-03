# NOOR Landing Performance Budget

Status: **LX-1.0 — In Progress**

## Baseline (measured, real — see `LX-1-0_BASELINE.md` §4)

| Metric | Current `/` (desktop) | Current `/` (mobile, simulated — caveat noted) |
| --- | --- | --- |
| Lighthouse Performance | 1.00 | 0.45 (localhost-throttling artifact, see baseline doc) |
| LCP | 0.5 s | 4.7 s (same artifact) |
| CLS | 0 | 0 |
| First Load JS (`/`) | 114 kB | — |
| Total byte weight | 189 KiB | — |

## Production targets (LX-1.2)

```
Lighthouse Performance:   ≥ 90 mobile   (re-measured against a real Vercel Preview, not localhost)
Lighthouse Accessibility: ≥ 95
Lighthouse Best Practices: ≥ 95
Lighthouse SEO:           ≥ 90

LCP: ≤ 2.5 s
CLS: ≤ 0.1
INP: ≤ 200 ms where measurable
```

These are deliberately *not* "match the current 189 KiB page" — a
10-scene motion-driven narrative page will legitimately ship more than
a 6-card static grid. The budget below exists so that growth is
measured and bounded, not unlimited.

## Bundle budget by contributor

| Contributor | Budget | Loaded when |
| --- | --- | --- |
| `framer-motion` | ≤ 35 kB gzipped, tree-shaken to used primitives | On first scroll interaction with any scene (not in the initial `/` bundle's critical path — the hero's own entrance may ship inline as CSS/lightweight JS if it proves smaller than pulling in Framer Motion above the fold; decided during LX-1.2 based on measured hero-only cost) |
| `gsap` + `ScrollTrigger` | ≤ 30 kB gzipped combined | Only when a ≥768px, non-reduced-motion visitor scrolls within range of Scene 8 |
| Landing images/illustration | 0 raster images planned — all visuals are SVG/CSS/token-driven per `NOOR_LANDING_VISUAL_LANGUAGE.md`; if any raster asset is later introduced, it must be served via `next/image` with explicit `width`/`height` to prevent CLS | N/A |
| `three` | 0 kB — not installed (`NOOR_LANDING_THREEJS_DECISION.md`) | Never |

## Rules (mission §19, restated as commitments)

- No autoplay background video anywhere.
- No uncompressed full-resolution imagery — no raster imagery at all in the current plan.
- No unnecessary client conversion of Server Components.
- No full-page canvas.
- No loading-screen gate before the page is usable.
- Framer Motion is not in the bundle for a visitor who never interacts past first paint if the hero can be expressed more cheaply; GSAP is never in the initial bundle under any circumstance.
- Dynamic `import()` for Scene 8 (the only below-fold advanced timeline).
- Only `transform`/`opacity` animated for anything scroll-linked.
- No persistent `will-change`.
- Scene 8's GSAP/ScrollTrigger is skipped entirely (not created-then-hidden) on low-power/mobile/reduced-motion contexts.
- Server-rendered content preserved for every scene (see Technical Architecture §Hydration behavior).
- No animation contributes to CLS — all motion is opacity/transform, which do not affect layout.

## Measurement plan for prototypes (this mission)

Each of the 6 prototypes built in LX-1.0 is measured independently in
the verification report: additional JS added, a rough main-thread cost
observation from the browser Performance panel equivalent (via
Playwright's tracing where practical), and a qualitative comparison of
CSS/SVG vs. Framer Motion vs. GSAP for the one scene (Scene 8) where
more than one technology was genuinely in contention. This is a spike
measurement to inform LX-1.2's real budget compliance — it is not
itself a claim that LX-1.0's prototype route meets the production
targets above, since the prototype route intentionally also ships
review-only controls (play/pause/scrubber/viewport switch) that will
never exist in production and therefore are excluded from any bundle
comparison.
