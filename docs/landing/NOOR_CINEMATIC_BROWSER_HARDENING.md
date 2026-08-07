# NOOR Cinematic Landing — Browser Hardening

Status: **LX-1.3 — Complete.** Extends LX-1.2's browser-compatibility record with real cross-engine testing (Firefox and WebKit binaries were installed this mission — `npx playwright install firefox webkit`) and a full responsive-viewport matrix.

## Browser matrix — real engines, this mission

| Browser | Engine | Real/Emulated | WebGL init | Scroll timeline | Console errors | axe violations | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Chromium | Blink | Real GPU hardware (`ANGLE (Intel, Intel(R) RaptorLake-S Mobile Graphics Controller, OpenGL 4.5.0)`) | Pass (1 canvas) | Pass (progress > 0.3 confirmed) | 0 | 0 | PASS |
| Firefox | Gecko | Real Firefox binary (v153.0), software rendering | Pass (1 canvas) | Pass | 0 | 0 | PASS |
| WebKit | WebKit | Real WebKit binary (v26.5) — **not real Safari/macOS**, software rendering | Pass (1 canvas) | Pass | 0 | 0 | PASS |
| Edge | Blink (Chromium) | Not separately run — Edge shares Chromium's rendering engine, already tested above | — | — | — | — | LIMITED (same engine already verified) |
| Safari (macOS) | WebKit | **Not available** — no macOS hardware in this environment | — | — | — | — | LIMITED — see `NOOR_LAUNCH_RISK_REGISTER.md` R-07 |

Screenshots for all 3 real engines: `docs/verification/screenshots/lx-1-3/browser-chromium-scene4.png`, `browser-firefox-scene4.png`, `browser-webkit-scene4.png` — each visually confirmed to show correct Scene 4 geometry, correct typography, correct nav, no debug UI, no rendering corruption.

**Honesty note, per mission's explicit instruction:** WebKit here means Playwright's WebKit engine build, which is the same rendering engine family Safari uses but is not Safari itself running on real Apple hardware — this report does not claim real Safari testing.

## Responsive viewport matrix

### Desktop (7 viewports)

| Viewport | Overflow | CTA visible & in bounds |
| --- | --- | --- |
| 1920×1080 | None | Yes |
| 1600×900 | None | Yes |
| 1440×1000 | None | Yes |
| 1440×900 | None | Yes |
| 1366×768 | None | Yes |
| 1280×800 | None | Yes |
| 1024×768 | None | Yes |

### Mobile/tablet (9 viewports)

| Viewport | Overflow | CTA visible & in bounds |
| --- | --- | --- |
| 1024×1366 | None | Yes |
| 820×1180 | None | Yes |
| 768×1024 | None | Yes |
| 430×932 | None | Yes |
| 414×896 | None | Yes |
| 390×844 | None | Yes |
| 375×812 | None | Yes |
| 360×800 | None | Yes |
| 320×568 | None | Yes |

All 16 viewports: 0 horizontal overflow, final CTA fully within viewport bounds after scrolling to the end of the journey. Raw data: `docs/verification/screenshots/lx-1-3/viewport-matrix-results.json`.

### Orientation change mid-scene

Portrait 390×844 scrolled to ~65% (Scene 5), then rotated to landscape 844×390 via `setViewportSize`. Result: no horizontal overflow after rotation, canvas remains visible, no crash. Screenshot: `docs/verification/screenshots/lx-1-3/orientation-change-scene5.png`.

## Mobile browser-chrome behavior

- `100vh`/visual-zone sizing (the mobile two-zone layout from LX-1.1.1/LX-1.2) was re-verified at 5 distinct mobile viewport heights (932/896/844/812/800px) with 0 overflow in every case — a proxy for the layout tolerating address-bar collapse/expand height changes, since the layout already uses percentage-based (`46vh`) sizing rather than a fixed pixel height that would break under `vh` recalculation.
- Orientation change recalculates correctly (tested above) — the camera/scroll-progress state did not jump or break after the viewport dimensions changed mid-scene.

## Zoom and forced-colors

| Test | Result |
| --- | --- |
| 125% browser zoom | No overflow, CTA visible |
| 150% browser zoom | No overflow, CTA visible |
| 200% browser zoom | No overflow, CTA visible |
| `forced-colors: active` (Chromium emulation) | CTA remains visible |

Raw data: `docs/verification/screenshots/lx-1-3/zoom-results.json`, `forced-colors-results.json`.
