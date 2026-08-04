# LX-1.1.1 — Cinematic Art Direction, Mobile Choreography, and Motion Polish — Verification Report

Status: **Cinematic Polish Implementation Complete, Pending User Visual and Motion Approval.**

This report consolidates every check run for the LX-1.1.1 corrective
pass that followed LX-1.1's rejection. Every number and screenshot
path below is real — captured this mission, not assumed or carried
forward from LX-1.1 without re-verification. Where a number is a
genuine improvement over LX-1.1's own report (real GPU vs.
SwiftShader, real production build vs. dev server), both are shown so
the improvement is traceable.

## 1. What was rejected, and the fix for each item

See `docs/landing/NOOR_CINEMATIC_ART_DIRECTION.md` for the full
before/after table. Summary:

| # | Rejected (mission §3) | Status |
| --- | --- | --- |
| 3.1 | Debug UI leaking into acceptance media | Fixed — recording script no longer passes `?debug=1`; state read via `window.__noorCinematicTimeline` instead |
| 3.2 | Weak Evidence Core identity | Fixed — N-spine (two page-layer towers + evidence bridge + aperture), one persistent object across all 7 scenes |
| 3.3 | Core too small/dark | Fixed — camera starts at `z:4.6` (was `z:6.5`), ambient 0.85 (was 0.55), key light 1.9 (was 1.1) |
| 3.4 | Dashboard-like typography | Fixed — fluid `clamp()` headlines, no boxed card |
| 3.5 | Weak first three scenes | Fixed — 4 sequential verification nodes (Scene 2), persistent aperture lock with real pulse (Scene 3) |
| 3.6 | Traceability not a signature interaction | Fixed — dedicated marker + DOM label tracking 6 named layers |
| 3.7 | Mobile layout rejected | Fixed — independent camera path, two-zone (46vh visual / copy) layout, single-active-scene exclusivity |
| 3.8 | Reduced motion visually incomplete | Fixed — 7 complete SVG illustrations, tracked via `useVisibleSceneId()` |
| 3.9 | Logo/nav too weak | Fixed — symbol + wordmark + descriptor, safe-area padding |
| 3.10 | Recording too fast | Fixed — `holdThenMove()` camera pattern, ~55% hold / 45% move per scene; total scroll distance widened 6→8.5 desktop viewport-heights |
| 3.11 | Real-GPU performance unverified | Fixed — confirmed real Intel GPU reachable from headless Chromium; all numbers below are real-GPU, real-production-build measurements |

## 2. Evidence Core review

The core is now one persistent object (`EvidenceCoreScene.ts`): two
page-layer towers forming the N-mark's two verticals, a diagonal
"evidence bridge" thread connecting them, and a central aperture that
plays three narrative roles (review lock → query entry → workspace
anchor) across the 7 scenes. See screenshots
`scene1-source-established-desktop.png` through
`scene7-final-cta-desktop.png` in
`docs/verification/screenshots/lx-1-1-1/` — all inspected directly
before writing this report, not assumed correct from code review
alone.

## 3. Scene-by-scene review

Full detail in `docs/landing/NOOR_CINEMATIC_COMPOSITION_MAP.md` and
`docs/landing/NOOR_CINEMATIC_SCENE_TIMELINE.md`. Checkpoint state
captured directly from `window.__noorCinematicTimeline` at each
labeled scroll position (`verification-results.json`):

| Scroll % | Checkpoint | sceneIndex | sceneLocalProgress |
| --- | --- | --- | --- |
| 0% | scene1-source-established | 0 | 0.03 |
| 10% | scene1-hold | 0 | 0.78 |
| 16% | scene2-verification-gateway | 1 | 0.19 |
| 20% | scene2-invalid-rejected | 1 | 0.52 |
| 30% | scene3-finding-locked | 2 | 0.16 |
| 37% | scene3-accepted-unlocked | 2 | 0.62 |
| 47% | scene4-spans-chunks | 3 | 0.19 |
| 62% | scene5-ranked-candidates | 4 | 0.25 |
| 76% | scene6-product-vision | 5 | 0.32 |
| 86% | scene7-intelligence-statement | 6 | 0.12 |
| 93% | scene7-source-span | 6 | 0.56 |
| 99.5% | scene7-final-cta | 6 | 0.95 |

Confirms both the hold-then-move pacing (large `sceneLocalProgress`
jumps between adjacent checkpoints within a hold phase are small; the
scene boundaries land close to `sceneConfig.ts`'s authored
percentages) and that Scene 7's 6 traceability stops are each reached
in sequence.

## 4. Mobile acceptance report

Verified at 390×844, 430×932, 360×800 (`verification-results.json`
`.mobile`):

| Viewport | Active scenes at once | Horizontal overflow | Final CTA fully visible |
| --- | --- | --- | --- |
| 390×844 | 1 | No | Yes |
| 430×932 | 1 | No | Yes |
| 360×800 | 1 | No | Yes |

Screenshots: `mobile-final-cta-390x844.png`,
`mobile-final-cta-430x932.png`, `mobile-final-cta-360x800.png` — all
inspected directly, confirming the final CTA sits fully inside the
viewport with no clipping, no overlapping copy, and the visual/copy
zone split holding. See `docs/landing/NOOR_CINEMATIC_MOBILE_CHOREOGRAPHY.md`
for the 5 specific bugs found (screenshot-driven, not assumed) and
fixed en route to this result.

## 5. Reduced-motion report

`reducedMotionConsistency` (`verification-results.json`): nav
announcement read `"Scene 4 of 7: Structure the knowledge. Keep the
provenance."` at 50% scroll — matching the illustration shown at that
same scroll position (confirmed against `reduced-motion-scroll50.png`)
— proving the nav-consistency bug (Scene 1 stuck forever) is fixed.
`canvasCount: 0` confirms `CinematicCanvas`/`three`/`gsap` never load
on this path at all. All 7 scene illustrations are complete SVGs (not
empty backgrounds) — see `docs/landing/NOOR_CINEMATIC_REDUCED_MOTION_SYSTEM.md`
for the full per-scene content table.

## 6. Reverse traceability report

Scene 7's `TRACEABILITY_LAYERS` (6 named layers:
intelligence-statement → supporting-evidence → retrieved-chunk →
source-span → original-page → trusted-guideline) each drive a
dedicated `traceabilityMarker` (a bright ring) moving between real
world-space anchor positions, plus a DOM label
(`AnchorLabels.tsx`) naming the current layer — captured directly in
`scene7-intelligence-statement-desktop.png` and
`scene7-source-span-desktop.png`, and in the dedicated
`04-reverse-traceability.webm` recording (frame-verified, see §9).

## 7. Performance report (real GPU, real production build)

Full detail and historical comparison in
`docs/landing/NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`. Headline results:

| Metric | LX-1.1 (dev/SwiftShader) | LX-1.1.1 (prod/real GPU) | Target | Result |
| --- | --- | --- | --- | --- |
| Lighthouse Performance (desktop) | 0.70 | **0.94** | ≥ 0.90 | Pass |
| Lighthouse Performance (mobile) | not run | **0.95** | ≥ 0.90 | Pass |
| Lighthouse Accessibility | 1.00 | 1.00 | ≥ 0.95 | Pass |
| Lighthouse Best Practices | 1.00 | 1.00 | ≥ 0.95 | Pass |
| Lighthouse SEO | 0.91 | 0.91 | ≥ 0.90 | Pass |
| LCP (desktop) | 0.7s | 0.9s | ≤ 2.5s | Pass |
| LCP (mobile) | — | 1.8s | ≤ 2.5s | Pass |
| CLS | 0 | 0 | ≤ 0.1 | Pass |
| TBT (desktop) | 1,370ms | 190ms | — | Improved |
| Total byte weight | 4,616 KiB (dev, unminified) | 302 KiB (desktop) / 305 KiB (mobile) | — | Improved |
| FPS range across scenes | 1–54 (SwiftShader) | 40–61 (real GPU) | — | Improved; Scene 5's 40fps dip noted for future work |
| Memory delta, 5 mount/unmount cycles | +150MB (dev-server artifact, investigated) | 0.00MB | — | Improved |

GPU confirmed real via `WEBGL_debug_renderer_info`:
`ANGLE (Intel, Intel(R) RaptorLake-S Mobile Graphics Controller, OpenGL 4.5.0)`.
Raw data: `fps-real-gpu.json`, `lighthouse-real-gpu.report.json`,
`lighthouse-real-gpu-mobile.report.json`.

## 8. Accessibility report

`axe` (`verification-results.json`, `@axe-core/playwright`):

| Scan | Violations |
| --- | --- |
| desktop-motion-enabled | 0 |
| desktop-reduced-motion | 0 |
| mobile-390 | 0 |
| mobile-430 | 0 |
| mobile-360 | 0 |
| RTL structural (`rtl.axeViolations`) | 0 |

Zero violations across every state, including the two real
violations found and fixed en route this mission
(`aria-hidden-focus` via the native `inert` DOM property;
`page-has-heading-one` via Scene 1's headline becoming a real
`<h1>`). Screenshots: `rtl-structural.png`, `webgl-disabled.png`.

## 9. Motion and screenshot evidence

7 clean recordings in `docs/verification/videos/lx-1-1-1/`, **none**
passing `?debug=1`:

| File | Content | Size |
| --- | --- | --- |
| `01-full-desktop-journey.webm` | Full 7-scene desktop scroll | 3.24 MB |
| `02-human-review.webm` | Scene 3 (lock → unlock) | 1.35 MB |
| `03-structured-knowledge.webm` | Scene 4 (spans → chunks) | 1.22 MB |
| `04-reverse-traceability.webm` | Scene 7 (6-layer traversal) | 1.52 MB |
| `05-mobile-journey.webm` | Full mobile scroll, 390×844 | 1.60 MB |
| `06-reduced-motion-journey.webm` | Full reduced-motion scroll | 1.29 MB |
| `07-static-webgl-fallback.webm` | WebGL-disabled fallback | 0.90 MB |

Every video was inspected via `ffprobe`/`ffmpeg` frame extraction
before this report was written — not assumed correct from file size
alone. This was necessary because a real bug (reusing one
GPU-flagged `chromium.launch()` browser instance across sequential
`recordVideo` contexts) initially produced all-black frames for 5 of
the 7 videos; fixed by giving each recording its own fresh browser
launch, then re-verified frame-by-frame afterward.

## 10. Regression review

- Production `/`: Lighthouse Performance/Accessibility/Best
  Practices/SEO all 1.00, LCP 0.6s, CLS 0, 194 KiB — unchanged from
  LX-1.1's own baseline, confirming zero cost leaked onto the real
  public landing page from this mission's changes.
- Route/bundle isolation: `three`'s two compiled chunks appear only
  in `/design/cinematic-landing`'s own production chunk output —
  reconfirmed by grepping the full chunk manifest for every other
  route.
- Preview gate: production build 404s on `/design/cinematic-landing`
  without `NOOR_CINEMATIC_PREVIEW_ENABLED=true`, 200 with it set,
  verified via curl against the identical build artifact with no
  rebuild between checks (`docs/landing/NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md`
  §Local reproduction). Now also covered by a committed regression
  test, `apps/web/tests/cinematic-preview-gate.test.ts`.
- All 21 pre-existing `apps/web` tests + the 1 new Preview-gate test
  (22 total) pass. `packages/clinical-schemas` tests (6) pass.
  `apps/web` and `packages/ui` typecheck clean. `next lint` reports
  no warnings or errors on the touched directory.

## 11. Git status at time of writing

All LX-1.1.1 changes are present as uncommitted modifications/new
files; nothing has been committed yet for this mission (commits
follow immediately after this report). Pre-existing untracked files
(`apps/web/public/brand.zip`, `docs/verification/screenshots/ux-1-1.zip`,
`logo.jpeg`) are unrelated to this mission and were left untouched.

## Final status

**LX-1.1.1 — Cinematic Polish Implementation Complete, Pending User
Visual and Motion Approval.**

Recommended next task: **User review of the clean desktop, mobile,
reduced-motion, and reverse-traceability recordings.**
