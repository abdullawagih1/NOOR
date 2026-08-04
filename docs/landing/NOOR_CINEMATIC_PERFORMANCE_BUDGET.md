# NOOR Cinematic Performance Budget

Status: **LX-1.1.1 — Complete.** LX-1.1's numbers below were measured
against the dev server / headless SwiftShader and explicitly deferred
real-GPU, real-production-build verification to a later mission. This
mission is that verification: every number in the "LX-1.1.1 measured
results" section below was captured against a real `next build`
production bundle (via the `NOOR_CINEMATIC_PREVIEW_ENABLED` gate — see
`NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md`), running on this machine's real
Intel GPU, not a software rasterizer. LX-1.1's original numbers are
kept below, unmodified, as a historical record of what was previously
known and why it wasn't trustworthy.

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

## LX-1.1.1 measured results (real GPU, real production build)

### Confirming real hardware acceleration, not SwiftShader

Headless Chromium launched with
`--use-gl=angle --use-angle=gl --ignore-gpu-blocklist --enable-gpu-rasterization`
reports, via `WEBGL_debug_renderer_info`:

```
ANGLE (Intel, Intel(R) RaptorLake-S Mobile Graphics Controller, OpenGL 4.5.0)
```

— this machine's real integrated GPU, not
`ANGLE (Google, Vulkan ... SwiftShader Device)`. This directly
contradicts LX-1.1's assumption that headless always means software
rendering; every FPS/Lighthouse number below was captured under this
confirmed-real-GPU launch configuration, against the
`NOOR_CINEMATIC_PREVIEW_ENABLED=true` production build described in
`NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md`.

### Lighthouse — desktop preset

| Metric | Value | Target | Result |
| --- | --- | --- | --- |
| Performance | **0.94** | ≥ 0.90 | Pass |
| Accessibility | 1.00 | ≥ 0.95 | Pass |
| Best Practices | 1.00 | ≥ 0.95 | Pass |
| SEO | 0.91 | ≥ 0.90 | Pass (single flagged item: no `<meta description>` — correct, this route must never be indexed) |
| LCP | 0.9 s | ≤ 2.5 s | Pass |
| CLS | 0 | ≤ 0.1 | Pass |
| TBT | 190 ms | — | |
| Speed Index | 0.5 s | — | |
| Total byte weight | 302 KiB | — | |

### Lighthouse — mobile preset

| Metric | Value | Target | Result |
| --- | --- | --- | --- |
| Performance | **0.95** | ≥ 0.90 mobile | Pass |
| LCP | 1.8 s | ≤ 2.5 s | Pass |
| CLS | 0 | ≤ 0.1 | Pass |
| TBT | 200 ms | — | |
| Speed Index | 2.9 s | — | |
| Total byte weight | 305 KiB | — | |

Both scores exceed the ≥90 target this mission specifically set out to
verify honestly — previously only claimed under a dev-mode/SwiftShader
caveat that made the number untrustworthy pre-launch.

### FPS — real GPU, per scene (checkpoint average)

| Scene | FPS |
| --- | --- |
| 1 — Trusted Source | 60 |
| 2 — Secure Intake | 60 |
| 3 — Human Review | 61 |
| 4 — Structured Knowledge | 58 |
| 5 — Retrieval | **40** |
| 6 — Product Vision | 60 |
| 7 — Reverse Traceability (mid) | 61 |
| 7 — Reverse Traceability (final composition) | 60 |

Every scene holds at or near 60fps on real hardware except Scene 5,
which dips to 40fps — the ranked-candidate row's DOM-projected rank
badges recompute screen position every 2nd RAF frame for 3 anchors
simultaneously while the query beam animates; worth a future
optimization pass (e.g., widening the projection interval further) but
well above the point of visible stutter and not a regression blocker.
This is a categorical improvement over LX-1.1's SwiftShader numbers
(which ranged 1–46fps and degraded sharply toward Scene 7) — confirming
the earlier degradation pattern was a software-rasterizer artifact, not
a real performance problem in the scene graph itself.

### Memory (real GPU build, 5-cycle mount/unmount)

| Metric | Value |
| --- | --- |
| Heap before | 12.7 MB |
| Heap after 5 mount/unmount cycles | 12.7 MB |
| Delta | 0.00 MB |

Zero measurable growth against the real production build — a cleaner
result than LX-1.1's dev-server-artifact-inflated +150 MB (itself
already explained as an HMR/module-registry artifact, not a real leak,
via the `/` ↔ `/login` control experiment referenced below).

### Production route sizes (real `next build` output)

```
Route                            Size    First Load JS
/design/cinematic-landing        5.3 kB     156 kB
```

`three` remains dynamically imported only once motion is confirmed
active, isolated to this route's own chunks — reconfirmed this mission
by grepping the compiled chunk manifest for every other route (see
`docs/verification/lx-1-1-1-cinematic-polish-verification.md` §Route
isolation for the exact command and output).

### Production `/` (regression check, unaffected)

Unchanged from LX-1.1 — Performance 1.00, Accessibility 1.00, Best
Practices 1.00, SEO 1.00, LCP 0.6s, CLS 0, 194 KiB. Reconfirmed this
mission to ensure none of the LX-1.1.1 changes leaked cost onto the
real production landing page.

## Historical record: LX-1.1's original numbers (dev server / SwiftShader — superseded above)

### `/design/cinematic-landing` — measured against the dev server

| Metric | Value | Note |
| --- | --- | --- |
| Performance | 0.70 | Dev-mode; superseded by the real-GPU production 0.94/0.95 above |
| Accessibility | 1.00 | |
| Best Practices | 1.00 | |
| SEO | 0.91 | |
| LCP | 0.7 s | |
| CLS | 0 | |
| TBT | 1,370 ms | Dev-mode; superseded by the real 190/200 ms above |
| Total byte weight | 4,616 KiB | Dev-mode (unminified `three`, source maps, HMR client); superseded by the real 302/305 KiB above |

### FPS (headless SwiftShader — software rasterizer, not real GPU)

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

Confirmed via `WEBGL_debug_renderer_info` at the time to be
`ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device...))` — CPU software
rendering, not representative of real user hardware. Explicitly
deferred to a later mission at the time; this mission is that
follow-up, and the real numbers above supersede this table.

### Memory (dev server, 5-cycle mount/unmount)

+150 MB growth observed, investigated via a control experiment
bouncing `/` ↔ `/login` (zero Three.js involvement) which reproduced
the same order-of-magnitude growth (+112 MB) — proving the growth was
a Next.js dev-server HMR/module-registry artifact, not specific to
this route's cleanup code. WebGL context disposal itself was already
verified directly at the time (8 cycles, zero context-loss warnings).

## Bundle isolation strategy (re-verified, not assumed)

`three` is imported only inside `CinematicCanvas.tsx`/`EvidenceCore/*`,
dynamically, gated behind the motion-active decision. Re-verified this
mission by grepping the compiled production chunk output for every
other route's page chunk — zero references to the `three`-containing
chunk files anywhere outside `/design/cinematic-landing`'s own page
chunk.

## What remains for a future mission

- Scene 5's 40fps dip — investigate widening the rank-badge
  DOM-projection interval or reducing simultaneous anchor updates.
- Real-GPU measurement on actual mobile hardware (this mission's
  "mobile preset" Lighthouse run is still a desktop-machine emulation
  of mobile viewport/network conditions, not a physical mobile device).
