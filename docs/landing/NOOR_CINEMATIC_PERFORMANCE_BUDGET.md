# NOOR Cinematic Performance Budget

Status: **LX-1.3 — Complete, with one open finding.** Prior LX-1.1.1/LX-1.2 real-GPU numbers are kept below as history.

## LX-1.3 update — honest 3-run Lighthouse methodology surfaced a real mobile gap

Single-run Lighthouse numbers (LX-1.2's own methodology) are noisy on a shared local development machine. LX-1.3 ran **3 real Lighthouse passes** per state and reports the full run set plus the median (never cherry-picking the best run, per mission §13):

| Route/variant | Runs | Median |
| --- | --- | --- |
| Cinematic desktop | 0.95, 1.00, 1.00 | **1.00** |
| Cinematic mobile | 0.88, 0.89, 0.92 | **0.89** — below the ≥90 target |
| Legacy mobile (control, same auth-check code path) | 0.98, 0.95, 0.96 | 0.96 — comfortably clears the target |

The legacy-mobile control run (same machine, same methodology, same auth-check cost) comfortably clearing 90+ every time rules out pure environment noise as the full explanation for cinematic's shortfall — the cinematic route carries a real, measurable additional mobile cost. **This is the sole reason LX-1.3's Go/No-Go decision is NO-GO.** See `docs/launch/NOOR_LAUNCH_RISK_REGISTER.md` R-03 and `docs/launch/NOOR_CINEMATIC_GO_NO_GO.md`. Not chased to a fix this mission (would require further investigation without risking a rushed change to the frozen visual direction) — recommended as the first item for a follow-up mission before any LX-1.4 launch decision.

Scene-by-scene FPS, by contrast, shows **zero regression** from the LX-1.2 optimization — all 7 scenes held 56-61fps across two independent real-GPU passes this mission. Full detail: `docs/landing/NOOR_CINEMATIC_RUNTIME_RELIABILITY.md`.

## LX-1.2 — Scene 5 optimization (mission §16)

LX-1.1.1's real-GPU measurement found Scene 5 (Retrieval) as the one
FPS outlier: 40fps against 58-61fps everywhere else. Profiled before
changing anything (`renderer.info` counters via a new
`EvidenceCoreScene.getDiagnostics()` + `window.__noorCinematicDiagnostics`,
same exposure pattern as `timelineStore`'s existing test-safe global):

| Metric | Scene 4 (before Scene 5) | Scene 5 (the outlier) | Scene 6 (after) |
| --- | --- | --- | --- |
| Draw calls | 25 | 29 | 47 |
| Triangles | 3,698 | 4,410 | 6,720 |
| Active particles | 850 (full) | 850 (full) | 850 (full) |

Scene 5 wasn't obviously more expensive by these raw counters than
neighboring scenes — the real cost was **simultaneity**: the ambient
particle field, all 5 structured blocks + their provenance threads,
the query beam, and still-visible verification/spine geometry were
all on screen and being updated together, the one moment every major
subsystem overlaps.

### Changes made (EvidenceCoreScene.ts / provenanceThread.ts)

1. **Eliminated 2 real per-frame allocations** that ran for the
   entire page's lifetime, not gated to any scene: `updateSpineNodes()`
   spread `[...leftTowerPages, ...rightTowerPages]` into a brand-new
   array every single frame (now built once in the constructor,
   `allTowerPages`); `updateLighting()` called `PENDING_KEY.clone()`
   every frame (now reuses a cached `THREE.Color` scratch instance).
2. **Shared materials**: the 5 structured blocks and their 5
   provenance threads each independently constructed an
   equivalent-but-distinct material (10 instances with identical
   parameters). Now one shared `MeshStandardMaterial` and one shared
   `MeshBasicMaterial` cover all 10 meshes — zero visual difference,
   fewer redundant GPU material/shader-program binds.
3. **Reduced provenance-thread tube resolution** from 24 tubular × 6
   radial segments to 14 × 5 — roughly 45% fewer triangles per thread,
   applied to all 7 thread meshes in the scene (the bridge, the panel
   thread, and the 5 block threads), invisible at this camera distance
   for a tube this thin.
4. **Thinned the ambient particle field specifically during Scene 5's
   own window** via `BufferGeometry.setDrawRange()` (no reallocation,
   fully reversible, restored to 100% by Scene 6) — the particle field
   is pure atmosphere, not a required story element, so this is a
   safe, targeted reduction rather than a global one.
5. **Skipped redundant "settled" writes**: `updateSpineNodes()` now
   caches each spine node's last-written opacity and skips the
   `.opacity=`/`.scale.setScalar()` write when the value hasn't
   changed frame-to-frame.

### Preserved, unchanged

All 5 structured blocks (3 candidate + 2 non-candidate), all 3 rank
badges (DOM-projected, unchanged), the human-judgment/exact-source
narrative (carried by scene copy, not a 3D object, so untouched by
any of the above), and full provenance continuity (every thread still
renders, just at lower geometric resolution).

### Before/after — real GPU, real production build

| Scene | LX-1.1.1 (before) | LX-1.2 (after, run 1) | LX-1.2 (after, run 2) |
| --- | --- | --- | --- |
| 1 | 60 | 61 | — |
| 2 | 60 | 60 | — |
| 3 | 61 | 60 | — |
| 4 | 58 | 60 | — |
| **5** | **40** | **61** | **56** |
| 6 | 60 | 60 | — |
| 7-mid | 61 | 60 | — |
| 7-final | 60 | 60 | — |

Two independent runs both clear the ≥45fps sustained-minimum target by
a wide margin (61fps and 56fps respectively) — Scene 5 is no longer a
measurable outlier. Real GPU reconfirmed both runs:
`ANGLE (Intel, Intel(R) RaptorLake-S Mobile Graphics Controller, OpenGL 4.5.0)`.
Raw data: `docs/verification/screenshots/lx-1-2/fps-real-gpu-post-optimization.json`.

## LX-1.2 — production-integration Lighthouse (real local build, real GPU)

| Route/variant | Preset | Performance | Accessibility | Best Practices | SEO | LCP |
| --- | --- | --- | --- | --- | --- | --- |
| Legacy `/` | Desktop | 1.00 | 1.00 | 1.00 | 0.92 | 0.6s |
| Legacy `/` | Mobile (simulated throttling) | 0.83–0.94 across 3 runs | 1.00 | 1.00 | 0.92 | 2.5–2.7s |
| Cinematic `/` | Desktop | 1.00 | 1.00 | 1.00 | 0.92 | 0.7s |
| Cinematic `/` | Mobile (simulated throttling) | 0.87 → 0.94 after a real fix (below) | 1.00 | 1.00 | 0.92 | 2.9–3.3s |

**Mobile-preset run-to-run variance (0.83–0.94 for the same route) is
real and honestly reported, not smoothed over** — Lighthouse's
simulated mobile CPU/network throttling on a shared local development
machine is measurably noisier than a dedicated lab environment; the
scores cluster at or above the ≥0.90 target in most runs but not all.
A production-grade measurement should ultimately come from a real
Vercel Preview/PageSpeed Insights run under real network conditions,
not a busy local machine — not performed this mission (see
`NOOR_CINEMATIC_BROWSER_COMPATIBILITY.md` for what direct Preview HTTP
verification could and couldn't reach).

**A real fix, found and applied this mission:** `getAuthenticatedContext()`
(used by every request to `/` now, to resolve the auth-aware CTA)
unconditionally called `supabase.auth.getUser()` — which, by Supabase's
own design, always revalidates the JWT against the Auth server over
the network, even for a visitor with no session cookie at all. Fixed
by calling the free, local-only `getSession()` first; only a request
that actually has a session cookie pays for the network-validated
`getUser()` call. Measured improvement on the cinematic mobile
Lighthouse run: Performance 0.87 → 0.94, LCP 3.3s → 2.9s, TBT
240ms → 130ms — a real, isolated before/after comparison on the same
route, same machine, same throttling profile.

**SEO 0.92 (not 1.00) on every dynamic route** — a single audit point
(`meta-description`) lost to a real, investigated Next.js 15
framework behavior, not a regression this mission introduced from
scratch (confirmed present on `/login`, untouched by this mission,
too). Full root-cause writeup: `NOOR_CINEMATIC_SEO_METADATA.md`.

## History: LX-1.1.1's real-GPU numbers below

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
