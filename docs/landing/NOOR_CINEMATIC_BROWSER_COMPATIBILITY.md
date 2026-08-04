# NOOR Cinematic Landing — Browser Compatibility

Status: **LX-1.2 — Complete, with an honest distinction between real-browser and engine-only testing (mission §36).**

## What was actually tested, and how

| Engine | How | Real hardware or Playwright-driven? |
| --- | --- | --- |
| Chromium (real GPU) | Headless Chromium launched with `--use-gl=angle --use-angle=gl --ignore-gpu-blocklist --enable-gpu-rasterization`, confirmed via `WEBGL_debug_renderer_info` to reach this machine's real Intel integrated GPU (`ANGLE (Intel, Intel(R) RaptorLake-S Mobile Graphics Controller, OpenGL 4.5.0)`) | Playwright-driven, real GPU hardware, not SwiftShader |
| Chromium (mobile viewport emulation) | Same real-GPU Chromium, viewport set to 390×844/430×932/360×800 | Playwright-driven, real GPU, emulated viewport — **not** a physical mobile device |
| WebKit/Firefox | **Not tested this mission.** No WebKit or Firefox binary was available in this environment (Playwright's own WebKit/Firefox browser downloads were not present and were not installed this mission) | Not tested |

**This mission does not claim real Safari or Firefox testing of any kind — Playwright WebKit was not available and was not substituted silently.** This is a real, honestly-reported gap, not a claim rounded up to "browser compatibility verified."

## What was verified on the tested engine

- WebGL2/WebGL initialization: confirmed via the real-GPU renderer string above, and via the WebGL-disabled fallback test (canvas `getContext` overridden to return `null` — confirmed the static illustration renders instead, 0 canvas elements, 0 page errors).
- Scroll behavior / sticky-positioned camera-driving content: confirmed via real scroll-position checkpoints against `window.__noorCinematicTimeline`, matching `sceneConfig.ts`'s authored percentages (unchanged from LX-1.1.1, re-confirmed this mission after the production integration).
- Resize: not re-tested this mission (unchanged code path from LX-1.1.1, which already verified `ResizeObserver`-driven canvas resize).
- Mobile viewport: confirmed via 390×844 real production-build screenshots and video, two-zone layout intact, 0 axe violations.
- Reduced motion: confirmed via `reducedMotion: "reduce"` context option, 0 canvas elements, 0 axe violations, real illustration content rendered.
- Focus: not independently re-audited this mission beyond what axe's `@axe-core/playwright` scans already cover (focus-visible outlines are unchanged CSS from LX-1.1.1); no regression found.
- CTA correctness: confirmed via the real end-to-end authentication journey (see `NOOR_CINEMATIC_AUTH_INTEGRATION.md`) — the CTA is a real interactive element clicked by a real (headless) browser, not merely inspected in markup.
- Context-loss fallback: covered by the same mechanism reviewed in `NOOR_CINEMATIC_PRODUCTION_ARCHITECTURE.md`'s error-containment section — unchanged from LX-1.1.1, which explicitly tested `webglcontextlost` event handling.
- GSAP cleanup: unchanged from LX-1.1.1 (`ScrollTrigger.kill()`/`gsap.killTweensOf()` in `useMasterTimeline`'s cleanup) — not re-audited line-by-line this mission since no code in that path changed.

## Recommendation for a future mission

Install Playwright's WebKit and Firefox binaries (`npx playwright install webkit firefox`) and re-run this mission's own verification scripts against them before treating this route as cross-browser-launch-ready. Real physical-device Safari/iOS testing (as opposed to WebKit-engine testing) is a separate, further step beyond even that.
