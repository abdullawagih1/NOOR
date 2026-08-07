# LX-1.3 — Media Index

Every recording and screenshot below was inspected before being listed here — videos via `ffmpeg` frame extraction and direct visual review, screenshots via direct visual review. Debug mode (`?debug=1`) was never used; no DevTools, passwords, tokens, cookies, or private data appear in any of them.

## Motion evidence

| Video | Viewport | Scenario | Build | Debug off | Path | Reviewed |
| --- | --- | --- | --- | --- | --- | --- |
| 01 — Desktop full journey | 1440×900 | Full 7-scene natural-pace scroll (~28s of scrolling) | Local production | Yes | `docs/verification/videos/lx-1-3/01-desktop-full-journey.webm` | Yes |
| 02 — Mobile full journey | 390×844 | Full 7-scene scroll | Local production | Yes | `docs/verification/videos/lx-1-3/02-mobile-full-journey.webm` | Yes — frame extracted, correct two-zone layout |
| 03 — Reduced motion | 1440×900 | `prefers-reduced-motion: reduce`, full scroll | Local production | Yes | `docs/verification/videos/lx-1-3/03-reduced-motion.webm` | Yes |
| 04 — WebGL fallback | 1440×900 | `getContext` returns null, full scroll | Local production | Yes | `docs/verification/videos/lx-1-3/04-webgl-fallback.webm` | Yes |
| 05 — Authentication journey | 1440×900 | Cinematic root → Sign in → real login → `/clinician` | Local production, real hosted Supabase, synthetic account | Yes | `docs/verification/videos/lx-1-3/05-authentication-journey.webm` | Yes — frame extracted, real content confirmed, no credentials visible |
| 06 — Reverse traceability | 1440×900 | Focused Scene 7, all 6 layers, natural pace | Local production | Yes | `docs/verification/videos/lx-1-3/06-reverse-traceability.webm` | Yes — frame extracted |
| 07 — Rollback | 1440×900 | Cinematic root → legacy root (in one recording) | Local production, two servers (one per flag) | Yes | `docs/verification/videos/lx-1-3/07-rollback.webm` | Yes — frame extracted |

**Note on "local production build" labeling**: as in LX-1.2, direct HTTP access to the hosted, Deployment-Protected Preview URL was not available this session (no bypass token). Every recording above is from a local production build (`next build && next start`) running the identical code deployed to Preview, confirmed via matching Vercel build-log route tables.

## Screenshot evidence

| Screenshot | Purpose | Path |
| --- | --- | --- |
| Browser matrix — Chromium | Scene 4, real GPU | `browser-chromium-scene4.png` |
| Browser matrix — Firefox | Scene 4, real Gecko | `browser-firefox-scene4.png` |
| Browser matrix — WebKit | Scene 4, real WebKit engine | `browser-webkit-scene4.png` |
| Orientation change | Portrait→landscape at Scene 5 | `orientation-change-scene5.png` |
| WebGL resilience — null context | Static fallback | `resilience-webgl-null.png` |
| WebGL resilience — context loss | Static fallback after real context loss | `resilience-context-loss-scene3.png` |
| No-JS | Complete semantic content, JS disabled | `resilience-no-js.png` |
| Zoom 125/150/200% | 3 screenshots | `zoom-125pct.png`, `zoom-150pct.png`, `zoom-200pct.png` |
| Forced colors | `forced-colors.png` |
| Authenticated root CTA | "Open NOOR" state (carried from LX-1.2, unchanged) | `../lx-1-2/authenticated-root-cta.png` |

## Raw data files (`docs/verification/screenshots/lx-1-3/`)

| File | Contents |
| --- | --- |
| `browser-matrix-results.json` | Console errors, axe violations, canvas presence, scroll-timeline advancement — 3 real engines |
| `viewport-matrix-results.json` | Overflow/CTA-visibility results — 16 viewports + orientation change |
| `resilience-results.json` | WebGL null/throw/context-loss, no-JS, scroll reliability |
| `lifecycle-20-cycle-results.json` | 20-cycle full-navigation memory test |
| `lifecycle-20-cycle-spa-results.json` | 20-cycle real SPA-navigation memory test (the rigorous variant) |
| `scene-fps-lx13.json` | Per-scene FPS + renderer diagnostics, real GPU |
| `quality-downgrade-lowend.json` | Low-end device simulation result |
| `tab-hidden-restore.json` | Tab visibility hide/restore result |
| `keyboard-tab-order.json` | Real keyboard traversal, tab order + focus visibility |
| `zoom-results.json` | 125/150/200% zoom overflow/CTA results |
| `forced-colors-results.json` | Forced-colors CTA visibility |
| `security-network-audit.json` | Network origins + secret-scan results |
| `open-redirect-live-results.json` | 11 live browser-driven open-redirect attack results |
| `auth-e2e-video-results.json` | Real auth E2E step-by-step log, incl. cleanup verification |
| `lighthouse/cinematic-desktop-run{1,2,3}.json` | 3 real Lighthouse runs, cinematic desktop |
| `lighthouse/cinematic-mobile-run{1,2,3}.json` | 3 real Lighthouse runs, cinematic mobile |
| `lighthouse/legacy-mobile-run{1,2,3}.json` | 3 real Lighthouse runs, legacy mobile (control) |
| `lighthouse/cinematic-desktop-post-metadata-fix.json` | Confirms the SEO fix (1.00 SEO score) |

## What was not captured, and why

- No real Safari (macOS)/physical mobile device recordings — hardware not available in this environment (see `NOOR_LAUNCH_RISK_REGISTER.md` R-07).
- No real NVDA screen-reader recording — software not available in this environment (R-06).
- No recording of the actual hosted Vercel Preview URL directly — Deployment Protection blocked automated HTTP access, no bypass token available (same limitation as LX-1.2).
