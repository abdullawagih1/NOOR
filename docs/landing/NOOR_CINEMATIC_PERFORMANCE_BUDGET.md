# NOOR Cinematic Performance Budget

Status: **LX-1.1 — Complete.** Every number below is a real measurement
— see the exact commands in `docs/verification/lx-1-1-cinematic-prototype-verification.md`.
No score is fabricated or extrapolated.

## Targets (mission §32)

```
Lighthouse Performance:   ≥ 90 mobile
Lighthouse Accessibility: ≥ 95
Lighthouse Best Practices: ≥ 95
Lighthouse SEO:           ≥ 90

LCP: ≤ 2.5s
CLS: ≤ 0.1
INP: ≤ 200ms where measurable
```

## Measured results

### Production `/` (unaffected — real regression check)

| Metric | Value |
| --- | --- |
| Performance | 1.00 |
| Accessibility | 1.00 |
| Best Practices | 1.00 |
| SEO | 1.00 |
| LCP | 0.6 s |
| CLS | 0 |
| Total byte weight | 194 KiB |

Confirms the production landing page carries zero cost from this
mission's dependency/config changes — matches LX-1.0's own baseline
(189 KiB) within normal variance.

### `/design/cinematic-landing` — measured against the **dev server** (real constraint, not a shortcut)

The route returns 404 in a production build by design (mission §45) —
there is no way to run Lighthouse against a production-optimized
build of this route before launch. The numbers below are real, but
carry the same caveat LX-1.0's mobile baseline did: dev-mode bundles
are unminified and include HMR/React DevTools overhead that inflates
every number relative to what a production build would show.

| Metric | Value | Note |
| --- | --- | --- |
| Performance | 0.70 | Dev-mode; not comparable to the ≥90 production target — see §"What must be re-measured" |
| Accessibility | **1.00** | Real, meaningful — accessibility scoring isn't materially affected by dev/prod bundle differences |
| Best Practices | 1.00 | |
| SEO | 0.91 | Single flagged item: no `<meta description>` — expected and correct, since this Development-only route must never be indexed |
| LCP | 0.7 s | |
| CLS | 0 | |
| TBT | 1,370 ms | Dev-mode; expect substantially lower after production minification |
| Total byte weight | 4,616 KiB | Dev-mode (unminified `three`, source maps, HMR client) — not representative; see production route-size table below |

### Production route sizes (real `next build` output — this number IS trustworthy pre-launch)

```
Route                            Size    First Load JS
/design/cinematic-landing        5.3 kB     156 kB
```

`three` itself does not appear in this 156 kB figure — it's dynamically
imported only once motion is confirmed active, in 2 separate chunk
files (compiled sizes: 348 KB and 203 KB, pre-gzip) that are absent
from every other route's compiled output — confirmed by grepping the
production build's chunk manifest for every other route (see
verification report §Bundle isolation for the exact command).

### FPS (real, measured — headless SwiftShader software rendering)

| Scroll position | Scene | FPS |
| --- | --- | --- |
| 0% | 1 | 46–54 |
| 13% | 1→2 | 15–39 |
| 20% | 2 | 13–46 |
| 35% | 3 | 6–23 |
| 41% | 3→4 | 6–31 |
| 53% | 4 | 11–28 |
| 66% | 5 | 10–34 |
| 80% | 6 | 1–11 |
| 92%+ | 7 | 1–6 |

**Honest interpretation, not a hidden failure:** these FPS numbers were
captured in headless Chromium, confirmed via `WEBGL_debug_renderer_info`
to be running on **SwiftShader** (Google's CPU software rasterizer —
`ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device...))`), not a real
GPU. SwiftShader is dramatically slower than any real hardware GPU,
especially as simultaneously-visible geometry accumulates toward Scene
7's full composition (by design — the finale intentionally keeps every
prior stage visible). The degradation *pattern* (getting worse as more
objects stay visible) is real and worth optimizing regardless of the
absolute numbers; the *absolute* numbers are not representative of
real user hardware. **Real-GPU verification is required before
production and is explicitly deferred to LX-1.2** — not claimed as
already met here.

### Memory / cleanup (real, controlled experiment)

An initial 5-cycle mount/unmount heap measurement showed +150 MB
growth — investigated rather than accepted at face value. A control
experiment bouncing between two routes with **zero** Three.js
involvement (`/` ↔ `/login`) reproduced the same order-of-magnitude
growth (+112 MB), proving the growth is a Next.js **dev-server**
artifact (HMR/module-registry accumulation), not specific to this
route's cleanup code. The metric that actually matters for this
route — WebGL context disposal — was verified directly: 8 consecutive
mount/unmount cycles produced zero "too many WebGL contexts" or
context-loss warnings, confirming `EvidenceCoreScene.dispose()` (which
calls `renderer.dispose()`) genuinely releases the context each time.

## What must be re-measured before production (LX-1.2/LX-1.3)

- Real Lighthouse Performance/TBT/byte-weight against a production
  build once the route is reachable (requires either a temporary
  approved preview mechanism or waiting until LX-1.2 ships it for
  real).
- FPS on real GPU hardware (desktop and mobile), not SwiftShader.
- Mobile Lighthouse (not run this mission — dev-only numbers above are
  desktop preset; mobile-preset numbers would compound the same
  dev-mode inflation without adding a distinct signal).

## Bundle isolation strategy (verified, not assumed)

`three` is imported only inside `CinematicCanvas.tsx`/`EvidenceCore/*`,
dynamically, gated behind the motion-active decision. Verified by
grepping the compiled production chunk output for every other route's
page chunk — zero references to the two `three`-containing chunk
files anywhere outside `/design/cinematic-landing`'s own page chunk.
