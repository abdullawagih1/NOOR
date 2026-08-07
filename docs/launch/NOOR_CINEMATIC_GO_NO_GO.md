# NOOR Cinematic Landing — Launch Go/No-Go

Status: **LX-1.3 — Complete.**

## Decision

**NO-GO — NOOR Cinematic Landing is not ready for Production Launch.**

### Blocking issue

- **R-03 — Cinematic mobile Lighthouse Performance median (0.89) falls below the ≥90 target**, measured honestly across 3 real Lighthouse runs against a real local production build on real GPU hardware (not cherry-picked: runs were `0.88, 0.89, 0.92`). Legacy `/`, running the identical auth-check code path on the identical machine, scored a comfortable median `0.96` — ruling out pure environment noise as the full explanation and confirming the cinematic route carries a real, measurable additional cost on mobile.

This is the **only** unresolved BLOCKER-equivalent item preventing a GO decision under this mission's own rule: "0 BLOCKER issues, 0 unaccepted HIGH issues." R-03 is classified HIGH in the risk register and has not been given an explicit accept decision, so the strict, non-subjective-compromise reading of the launch gate is NO-GO.

### Why this isn't a subjective judgment call

The mission's own governing instruction is explicit: *"Do not make a subjective compromise."* A 0.01 gap below a stated numeric target is still a gap. Every other Core Web Vitals target, every accessibility gate, every security gate, and the (now-resolved) production incident all pass cleanly — this is a narrowly-scoped, well-understood, honestly-measured shortfall, not a broad readiness failure, and it does not require redesigning the approved experience to close.

### Everything else genuinely passed

For clarity, since this is a narrow NO-GO, not a broad one:

- The real, active production outage found at the start of this mission (R-01) is fully resolved and re-verified.
- The real open-redirect hardening gap found this mission (R-04) is fully resolved with regression tests.
- The real, investigated SEO metadata-streaming issue carried over from LX-1.2 is **resolved** (not just documented) via Next.js's own official `htmlLimitedBots` config switch — Lighthouse SEO now reads a clean 1.00.
- 0 axe violations across every scanned state (legacy, cinematic desktop/mobile/reduced-motion/WebGL-fallback, `/login`, `/access-denied`).
- Real cross-engine testing (Chromium with real GPU, real Firefox, real WebKit) all render correctly with 0 console errors and 0 axe violations.
- 20 real SPA-style mount/unmount cycles show 0.00MB heap growth and exactly 1 surviving canvas.
- WebGL init failure, real context loss, JavaScript fully disabled, and a simulated renderer-construction exception all fall back to the complete static/semantic experience with the CTA and `<h1>` intact, no raw stack traces, 0 page errors.
- Scene 5 (the LX-1.2 optimization target) shows no regression — 56-61fps across two independent measurement passes.
- The real, previously-missing authentication journey (mission-mandated video) is now recorded, using a synthetic account that was fully created, exercised, and cleaned up against the real hosted Supabase project with verified zero residual rows.
- Zero external network origins, zero secrets found in the compiled client bundle.
- Rollback (cinematic → legacy → cinematic) rehearsed again this mission, confirmed fast and code-revert-free.
- Production remains on `legacy` throughout — confirmed via `vercel env ls production` before and after every change this mission made.

### What would flip this to GO

Either of:

1. **Close the mobile performance gap** — a future mission investigates and reduces the cinematic route's mobile initial-paint cost (candidate: confirm whether `page.tsx`'s static import of `CinematicPublicLanding` costs anything on the legacy-branch server render path even though it's not shipped to the client for that response) and re-measures with the same 3-run methodology, reaching a median ≥0.90.
2. **An explicit, informed user decision to accept R-03** as a known, bounded trade-off — this document does not make that call unilaterally, since the mission explicitly reserves launch-blocking classification from being resolved by assumption.

## Launch Readiness Scorecard

| Domain | Gate | Result | Evidence | Blocking |
| --- | --- | --- | --- | --- |
| Architecture | Component boundaries, bundle isolation | PASS | `NOOR_CINEMATIC_PRODUCTION_ARCHITECTURE.md`, live HTTP chunk-reference checks | No |
| Feature flag | Fails closed on all malformed inputs | PASS | `public-landing-feature-flag.test.ts` (14 checks incl. LX-1.3 adversarial matrix) | No |
| Rollback | Cinematic↔legacy, no code revert | PASS | Rehearsed twice (LX-1.2 + LX-1.3), both timed and verified | No |
| Desktop UX | 7 viewports, 0 overflow, CTA visible | PASS | `viewport-matrix-results.json` | No |
| Mobile UX | 9 viewports + orientation, 0 overflow | PASS | `viewport-matrix-results.json` | No |
| Reduced motion | Complete static narrative, 0 canvas | PASS | `resilience-results.json`, video 03 | No |
| WebGL fallback | `getContext` null, context loss, render-throw all degrade safely | PASS | `resilience-results.json` | No |
| Performance (desktop) | Lighthouse ≥90 | PASS (median 1.00) | 3-run Lighthouse | No |
| Performance (mobile) | Lighthouse ≥90 | **FAIL (median 0.89)** | 3-run Lighthouse | **Yes — R-03** |
| Core Web Vitals | LCP/CLS/TBT | PASS | Lighthouse reports (desktop); mobile LCP elevated but CLS 0 | No (tracked under R-03) |
| Scene runtime (FPS) | ≥45fps sustained, Scene 5 no regression | PASS (56-61fps all scenes) | `scene-fps-lx13.json` | No |
| Memory (20-cycle) | No monotonic growth | PASS (0.00MB delta, 1 canvas) | `lifecycle-20-cycle-spa-results.json` | No |
| Accessibility (automated) | 0 serious/critical axe violations | PASS | `browser-matrix-results.json`, axe scans across 8 states | No |
| Keyboard | Logical order, visible focus | PASS | `keyboard-tab-order.json` | No |
| Screen reader | Real NVDA pass | **LIMITED** (no screen reader available in this environment) | `NOOR_LAUNCH_RISK_REGISTER.md` R-06 | No |
| Zoom | 125/150/200% | PASS | `zoom-results.json` | No |
| Forced colors | CTA/focus visible | PASS (Chromium emulation only) | `forced-colors-results.json` | No |
| Chrome | Real GPU | PASS | `browser-matrix-results.json` | No |
| Edge | Chromium-based, not separately tested | **LIMITED** (Edge uses the same Chromium engine tested; no separate Edge binary run) | — | No |
| Firefox | Real Gecko engine | PASS | `browser-matrix-results.json` | No |
| WebKit/Safari | Real WebKit engine (not real Safari/macOS) | PASS (LIMITED to engine, not real Safari hardware) | `browser-matrix-results.json`, `NOOR_LAUNCH_RISK_REGISTER.md` R-07 | No |
| SEO | Raw HTML metadata, `<head>` placement | PASS (1.00, fixed this mission) | Lighthouse post-fix run | No |
| Metadata | Title/description/canonical/OG | PASS | Direct DOM/HTTP inspection | No |
| Social preview | Existing approved asset, no debug UI | PASS | Reused from LX-1.2 (unchanged) | No |
| Security | Secrets, external requests | PASS | `security-network-audit.json` (0 secrets, 0 external origins) | No |
| CSP | App-wide header configured | **LIMITED** (no CSP anywhere in the app — pre-existing, whole-app scope) | `NOOR_LAUNCH_RISK_REGISTER.md` R-05 | No |
| Auth | Real E2E, redirect never defaults to `/` | PASS | Video 05, `auth-e2e-video-results.json` | No |
| Open redirects | 11 attack variants, incl. backslash/encoded tricks | PASS (1 real gap found and fixed) | `redirect.test.ts`, `open-redirect-live-results.json` | No |
| No-JS | Complete semantic content | PASS | `resilience-results.json` (h1/CTA/6-7 scene keywords present) | No |
| Bundle isolation | `three` never leaks to other routes | PASS | Live HTTP response chunk-reference checks | No |
| Product truth | Every public claim traced to evidence | PASS | `NOOR_LANDING_CAPABILITY_TRUTH_MATRIX.md` re-audit, no status changes | No |
| Synthetic content | No real clinical/patient data | PASS | Direct scene-copy review, unchanged from LX-1.1.1 | No |
| Observability | Readiness documented | PASS (gap honestly documented, no vendor added) | `NOOR_CINEMATIC_OBSERVABILITY.md` | No |
| CI | Green | PASS | GitHub Actions run for this mission's push | No |

**LIMITED items (5) do not block launch** — they represent honestly-disclosed testing-environment constraints (no screen reader, no separate Edge binary, no real Safari/macOS, no real physical device, pre-existing whole-app CSP gap), not failures of the cinematic landing itself.

## Final Status

**LX-1.3 — Hardening Complete, Launch Readiness Failed, Blockers Remaining**

## Recommended Next Task

**Resolve the listed launch blockers and repeat the failed LX-1.3 gates**

Specifically: close the mobile-performance gap (R-03) via targeted investigation and re-measurement, or obtain an explicit, informed user decision to accept it as a bounded trade-off — then re-run the mobile Lighthouse gate (3 fresh runs, honest median) before returning to this document.
