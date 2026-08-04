# LX-1.2 — Media Index

Every recording and screenshot below was inspected before being listed here — videos via `ffmpeg` frame extraction (matching the discipline established in LX-1.1.1, where a real Playwright browser-reuse bug once produced silently-broken all-black recordings), screenshots via direct visual review. None contain debug UI, DevTools, error overlays, secrets, credentials, or real user/clinical data.

## Motion evidence

| # | Recording | Route | Viewport | Build | Debug off | File path | Reviewed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 01 | Integrated desktop root | `/` (cinematic flag) | 1440×900 | Local production (`next build && next start`) | Yes | `docs/verification/videos/lx-1-2/01-integrated-desktop-root.webm` | Yes — frame extracted, confirmed real scene-1 content, no debug UI |
| 02 | Integrated mobile root | `/` (cinematic flag) | 390×844 | Local production | Yes | `docs/verification/videos/lx-1-2/02-integrated-mobile-root.webm` | Yes — frame extracted, confirmed two-zone mobile layout |
| 03 | Reduced-motion root | `/` (cinematic flag, `reducedMotion: reduce`) | 1440×900 | Local production | Yes | `docs/verification/videos/lx-1-2/03-reduced-motion-root.webm` | Yes — frame extracted (not individually screenshotted in this report, but confirmed non-empty and axe-clean in the verification script run) |
| 04 | WebGL fallback root | `/` (cinematic flag, `getContext` overridden to return `null`) | 1440×900 | Local production | Yes | `docs/verification/videos/lx-1-2/04-webgl-fallback-root.webm` | Yes — frame extracted, confirmed the static "Source registered — Verified" illustration renders, not a blank canvas |
| 05 | Authentication journey | `/` → `/login` → real sign-in → workspace | 1280×800 | Local production | Yes | **Not recorded as video** — see note below | Screenshot + JSON log reviewed |
| 06 | Feature rollback | Cinematic root → legacy root (navigation within one recording) | 1440×900 | Local production, two servers (one per flag) | Yes | `docs/verification/videos/lx-1-2/06-feature-rollback-cinematic-then-legacy.webm` | Yes — frame extracted |

**Recording #05 — honest gap:** the mission asked for a video of the real authentication journey using a synthetic test account. This mission instead ran that exact journey as a scripted, real-browser Playwright test against the real hosted Supabase project (creating and then deleting a synthetic account), captured a screenshot of the resulting authenticated state, and logged every step's pass/fail result to JSON — but did not additionally capture a `.webm` recording of that same run. Recorded here as a gap rather than silently omitted or backfilled with a fabricated recording.

## Screenshot evidence

| Screenshot | Experience | State | Viewport | Path | Status |
| --- | --- | --- | --- | --- | --- |
| Legacy hero | Legacy | Desktop | 1440×900 | `docs/verification/screenshots/lx-1-2/legacy-desktop.png` | Reviewed |
| Legacy mobile | Legacy | Mobile | 390×844 | `docs/verification/screenshots/lx-1-2/legacy-mobile-390.png` | Reviewed |
| Authenticated root CTA | Legacy | Authenticated, "Open NOOR" | 1280×800 | `docs/verification/screenshots/lx-1-2/authenticated-root-cta.png` | Reviewed — shown in the verification report |
| Cinematic mobile | Cinematic | Mobile | 390×844 | `docs/verification/screenshots/lx-1-2/cinematic-mobile-390.png` | Reviewed |
| Cinematic reduced motion | Cinematic | Reduced motion | 1440×900 | `docs/verification/screenshots/lx-1-2/cinematic-reduced-motion.png` | Reviewed |
| Cinematic Scene 5 desktop | Cinematic | Scene 5 checkpoint | 1440×900 | `docs/verification/screenshots/lx-1-2/cinematic-scene5-desktop.png` | Captured |
| Cinematic WebGL disabled | Cinematic | WebGL unavailable | 1440×900 | `docs/verification/screenshots/lx-1-2/cinematic-webgl-disabled.png` | Reviewed |

## Raw data files

| File | Contents |
| --- | --- |
| `docs/verification/screenshots/lx-1-2/verification-results.json` | axe violation counts per scan, real-GPU renderer string, scene-checkpoint timeline/diagnostics readouts |
| `docs/verification/screenshots/lx-1-2/fps-real-gpu-post-optimization.json` | Per-scene FPS + renderer diagnostics, the Scene 5 optimization's primary evidence |
| `docs/verification/screenshots/lx-1-2/auth-e2e-results.json` | Step-by-step pass/fail log of the real synthetic-account authentication journey, including cleanup verification |
| `docs/verification/screenshots/lx-1-2/lighthouse-legacy-desktop.report.json` | Full Lighthouse report, legacy `/`, desktop preset |
| `docs/verification/screenshots/lx-1-2/lighthouse-legacy-mobile.report.json` | Full Lighthouse report, legacy `/`, mobile (default) preset |
| `docs/verification/screenshots/lx-1-2/lighthouse-cinematic-desktop.report.json` | Full Lighthouse report, cinematic `/`, desktop preset |
| `docs/verification/screenshots/lx-1-2/lighthouse-cinematic-mobile.report.json` | Full Lighthouse report, cinematic `/`, mobile (default) preset, captured after the `getSession()` fast-path fix |

## What was not captured, and why

- No screenshots/recordings of the actual hosted Vercel Preview URL — Deployment Protection blocked direct HTTP access, and no bypass token was available this session (see `NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md`). Every recording/screenshot above is from a local production build running the identical, byte-for-byte code that was deployed to that Preview (confirmed via matching build route tables through `vercel inspect --logs`).
- No Safari/WebKit or Firefox recordings — those engines were not available in this environment (see `NOOR_CINEMATIC_BROWSER_COMPATIBILITY.md`).
