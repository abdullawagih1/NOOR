# NOOR Cinematic Landing — Runtime Reliability

Status: **LX-1.3 — Complete.**

## WebGL failure injection

| Scenario | Method | Canvas after | CTA visible | H1 visible | Page errors | Raw stack shown |
| --- | --- | --- | --- | --- | --- | --- |
| `getContext` returns `null` | `HTMLCanvasElement.prototype.getContext` overridden | 0 | Yes | Yes | 0 | No |
| Renderer construction throws synchronously | `getContext` overridden to throw | 0 | Yes | — | 0 | No |
| Real `WEBGL_lose_context` during Scene 3 | Extension's `loseContext()` called mid-scroll | 0 (fell back) | Yes | Yes | 0 | No |

Every scenario converges on the same result: the static/semantic experience takes over completely, the CTA and heading remain reachable, and no raw JavaScript stack trace is ever shown to the user. Screenshots: `docs/verification/screenshots/lx-1-3/resilience-webgl-null.png`, `resilience-context-loss-scene3.png`. Raw data: `docs/verification/screenshots/lx-1-3/resilience-results.json`.

## JavaScript disabled

Real `javaScriptEnabled: false` Playwright context against the production build. Result:

- `<h1>` text present and correct: "Clinical intelligence begins with a source you can trust."
- 0 canvas elements (no attempt to run client JS at all).
- Primary CTA `href="/login"` present and correct.
- 1,673 characters of real body text present — the semantic narrative is genuinely server-rendered, not dependent on JS to exist.

Screenshot: `docs/verification/screenshots/lx-1-3/resilience-no-js.png`.

## Scroll reliability

| Test | Result |
| --- | --- |
| Fast-forward to end | `progress` reaches 1.0 |
| Fast-reverse to start | `progress` returns to 0.0 |
| Jump to middle | `progress` lands at ~0.5 |
| Full page reload mid-scroll | Canvas survives, re-initializes cleanly |

Raw data: `docs/verification/screenshots/lx-1-3/resilience-results.json` (`scrollReliability`).

## Tab visibility (hidden/restored)

Simulated `document.hidden`/`visibilitychange` while parked at Scene 4 (~50% progress). After a hidden period and restoration: scroll progress unchanged (`0.4999` before and after — RAF-driven state does not drift or reset while hidden), canvas remains visible. Raw data: `docs/verification/screenshots/lx-1-3/tab-hidden-restore.json`.

## Quality downgrade (High → Balanced)

Simulated a low-end device (`navigator.hardwareConcurrency = 2`, `navigator.deviceMemory = 2`, both read-only getters overridden via `addInitScript`, not a real fingerprint transmitted anywhere). Result: the scene initializes at the `balanced` tier (`activeParticles: 380`, vs. `850` on the default `high`-tier profile measured in the same session) — confirms `useInitialQualityTier()`'s coarse capability check genuinely changes runtime behavior. Raw data: `docs/verification/screenshots/lx-1-3/quality-downgrade-lowend.json`.

## 20-cycle Three.js mount/unmount lifecycle stress test

Two independent methodologies, both real:

1. **Full-navigation cycles** (`page.goto()` repeatedly, `/` ↔ `/login`, 20×): heap flat at 9.54MB across every sample, 0.00MB delta, 1 canvas remaining. (Caveat: a full `page.goto()` resets the browser's JS realm each time, so this variant mostly proves "no crash across repeated navigation," not in-page disposal specifically.)
2. **Real SPA-style cycles** (clicking real `<Link>` elements — `Sign in` → `/login` → logo → `/` — 20×, keeping one live JS heap the whole time, the rigorous version of this test): heap flat at 9.54MB across every sample, **0.00MB delta**, exactly **1 canvas** remaining, RAF loop confirmed still active. This is the test that actually exercises `EvidenceCoreScene.dispose()`, `cancelAnimationFrame`, and `ScrollTrigger.kill()` repeatedly within one live page — and it shows no measurable growth.

Raw data: `docs/verification/screenshots/lx-1-3/lifecycle-20-cycle-results.json`, `lifecycle-20-cycle-spa-results.json`.

## Scene-by-scene FPS (regression check against LX-1.2's optimization)

| Scene | LX-1.2 (post-optimization) | LX-1.3 (this mission, run 1) | LX-1.3 (this mission, run 2) |
| --- | --- | --- | --- |
| 1 | 61 | 59 | 61 |
| 2 | 60 | 58 | 60 |
| 3 | 60 | 60 | 60 |
| 4 | 60 | 56 | 60 |
| 5 | 61 | 60 | — |
| 6 | 60 | 61 | — |
| 7-mid | 60 | 61 | — |
| 7-final | 60 | 60 | — |

No regression — Scene 5 (the LX-1.2 optimization target) remains solidly above the ≥45fps sustained-minimum target across every measurement this mission. Real GPU reconfirmed: `ANGLE (Intel, Intel(R) RaptorLake-S Mobile Graphics Controller, OpenGL 4.5.0)`. Raw data: `docs/verification/screenshots/lx-1-3/scene-fps-lx13.json`, `fps-real-gpu-post-optimization.json` (carried from LX-1.2 for the second comparison run).
