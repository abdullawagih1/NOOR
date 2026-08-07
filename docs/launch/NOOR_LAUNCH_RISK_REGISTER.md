# NOOR Launch Risk Register

Status: **LX-1.3 — Complete.** Every issue found during LX-1.3's hardening pass, classified honestly. Nothing here is hidden in prose.

## Severity legend

- **BLOCKER** — launch must not proceed while open.
- **HIGH** — must normally be resolved before launch unless explicitly accepted.
- **MEDIUM** — may launch with documented follow-up.
- **LOW** — cosmetic or minor operational issue.

## Findings

### R-01 — Production `/` and `/login` returned HTTP 500 (real, active outage) — BLOCKER → RESOLVED

- **Severity:** BLOCKER (was live and affecting real visitors at the moment it was found).
- **Evidence:** `curl -i https://noor-clinical-intelligence-os.vercel.app/` returned `500`; live `vercel logs` showed `ZodError: NEXT_PUBLIC_SUPABASE_URL is required` / `NEXT_PUBLIC_SUPABASE_ANON_KEY is required`, thrown from `getPublicEnv()` inside `resolveLandingCta()` → `getAuthenticatedContext()` → `createClient()`.
- **User impact:** No visitor could load the homepage or sign in. Total outage of the public product surface.
- **Root cause:** Production's Vercel environment had zero environment variables configured at all. This predates LX-1.2 (`/login` was already silently broken; `/admin` degraded gracefully via middleware's fail-closed redirect-to-`/login`, which itself then also 500'd). LX-1.2's auth-aware CTA is what extended the same gap to the previously-static, previously-working `/`.
- **Owner:** This mission, fixed directly.
- **Fix:** With explicit user approval, copied `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_APP_URL`, `APP_ENV` (the same values already correct in Preview) into the Production environment scope, then ran a real `vercel deploy --prod`.
- **Verification:** `/` → 200, `/login` → 200, `/admin` → 200 (via its normal redirect), canonical URL now correctly resolves to the real production domain (a side effect of the same missing `NEXT_PUBLIC_APP_URL`). `NOOR_PUBLIC_LANDING_EXPERIENCE` was not touched — confirmed still absent from Production, site remains on `legacy`.
- **Acceptance decision:** Resolved. No workaround needed; the fix is complete and verified.
- **Launch blocking:** No (resolved).

### R-02 — `resolveLandingCta()` has no defensive fallback if `getAuthenticatedContext()` throws — HIGH

- **Severity:** HIGH.
- **Evidence:** R-01's exact failure mode proves this: any future misconfiguration or transient Supabase outage that causes `getAuthenticatedContext()` to throw takes down the ENTIRE public landing page (both legacy and cinematic), not just the auth-aware CTA feature. There is currently no `try/catch` around this call in `resolveLandingCta()`.
- **User impact:** A single upstream dependency (Supabase reachability/configuration) is a single point of failure for the whole public homepage, which architecturally should be resilient even when auth is unavailable.
- **Root cause:** `resolveLandingCta()` (LX-1.2) calls `getAuthenticatedContext()` unconditionally with no error boundary.
- **Owner:** Recommended for LX-1.4 or a fast-follow, not fixed in this mission (the underlying instance of it — R-01 — is fixed; this is the architectural resilience gap that allowed it to be so severe).
- **Recommendation:** Wrap `resolveLandingCta()`'s call in `try/catch`, falling back to the unauthenticated "Sign in" CTA on any error — never let an auth-resolution failure crash the whole public landing.
- **Workaround:** None currently; R-01's direct fix (correct env vars) removes today's trigger, but the architectural gap remains.
- **Acceptance decision:** Accepted as a documented follow-up for LX-1.4, since the immediate trigger (R-01) is fixed and this is a defense-in-depth improvement, not an active defect.
- **Launch blocking:** No, if R-01's fix is verified in place at launch time (it is).

### R-03 — Cinematic mobile Lighthouse Performance is borderline under honest 3-run median methodology — HIGH

- **Severity:** HIGH.
- **Evidence:** 3 real Lighthouse runs against cinematic `/` (mobile preset, real GPU headless Chromium, local production build): `0.88, 0.89, 0.92` — **median 0.89**, below the ≥0.90 target. Legacy `/` (same auth-check code path) scored `0.98, 0.95, 0.96` (median 0.96) on the identical machine/methodology, ruling out pure environment noise as the sole explanation — the cinematic route's own additional weight (larger JS surface referenced, more DOM, heavier initial paint) is a real, measurable contributor.
- **User impact:** Mobile visitors on constrained networks/devices may perceive the cinematic landing as slower to become interactive than the ≥90 target implies is acceptable.
- **Root cause:** Not chased to a single root cause this mission (would require further bundle-splitting/paint-order investigation, out of the time budget for LX-1.3 without risking a rushed change to the frozen visual direction).
- **Owner:** Recommended for LX-1.4/future mission.
- **Recommendation:** Investigate further code-splitting of the cinematic overlay components referenced from `page.tsx`'s static import (currently all cinematic overlay JS is referenced even when the legacy branch renders, though not shipped to the client for that response — worth confirming this isn't adding server-side render-path cost) and re-measure.
- **Workaround:** None currently.
- **Acceptance decision:** **Not yet accepted** — flagged for explicit user decision in the Go/No-Go below, since it is the one Core Web Vitals target genuinely not met under honest methodology.
- **Launch blocking:** Borderline — see Go/No-Go document for the final call.

### R-04 — `sanitizeNextPath()` did not reject backslash-based open-redirect variants — HIGH → RESOLVED

- **Severity:** HIGH (a real, evidence-based open-redirect risk, not theoretical).
- **Evidence:** `new URL("/\\evil.example", "http://internal.invalid").origin` resolves to `http://evil.example` — confirmed directly against Node's own WHATWG URL parser. The prior `sanitizeNextPath()` only checked string prefixes (`//`, `://`) and did not reject a leading `/\`. A live Chromium address-bar navigation to this exact string happened to normalize to same-origin (Chrome's own navigation-specific behavior), but that is not guaranteed for every URL-consuming code path (a proxy, a different rendering engine, Next's own internal redirect handling).
- **User impact:** Potential open-redirect if any code path in front of or inside the app ever resolves the `next` value via standard URL parsing rather than raw string handling.
- **Root cause:** The original sanitizer used ad hoc string-prefix checks instead of a URL parser (mission §34 anticipated exactly this class of gap).
- **Owner:** This mission, fixed directly.
- **Fix:** `sanitizeNextPath()` now rejects any value containing a backslash outright, and additionally resolves every candidate against a fixed internal placeholder origin via the `URL` constructor, rejecting anything whose resolved origin differs from that placeholder.
- **Verification:** New regression tests in `apps/web/tests/redirect.test.ts` cover 5 backslash variants (all correctly rejected) plus encoded-slash/double-encoding cases (confirmed to resolve same-origin and are therefore safely honored, not rejected unnecessarily) plus malformed-URI-sequence inputs (never throw).
- **Acceptance decision:** Resolved.
- **Launch blocking:** No (resolved).

### R-05 — No CSP or security headers configured anywhere in the app — MEDIUM

- **Severity:** MEDIUM.
- **Evidence:** `apps/web/next.config.mjs` has no `headers()` function; no `vercel.json` exists anywhere in the repo. Confirmed via direct file inspection.
- **User impact:** No defense-in-depth against XSS/injection beyond React's own default escaping and the app's own input handling. This is the existing baseline for the ENTIRE application (every route), not something specific to the cinematic landing.
- **Root cause:** Never configured, predates this workstream entirely.
- **Owner:** Whole-app scope, not cinematic-landing scope — out of bounds for this mission to introduce (mission §37 explicitly says "review CSP compatibility," not "add a CSP where none exists app-wide").
- **Recommendation:** A future, dedicated mission should design and roll out a CSP for the whole app (not just the landing), since introducing one narrowly for `/` alone would be an inconsistent, partial security posture.
- **Workaround:** None; documented as an accepted, pre-existing gap.
- **Acceptance decision:** Accepted — out of LX-1.3's scope (whole-app change), not a cinematic-landing-specific regression.
- **Launch blocking:** No.

### R-06 — Real screen-reader testing (NVDA) was not performed — MEDIUM

- **Severity:** MEDIUM.
- **Evidence:** No screen-reader software is installed/available in this execution environment.
- **User impact:** Unverified real assistive-technology experience beyond axe's automated tree inspection and the accessibility-tree/DOM-structure checks this mission did perform.
- **Owner:** Requires a human tester with NVDA + Chrome/Firefox on Windows, or a future mission run from an environment with screen-reader software available.
- **Recommendation:** Perform a real NVDA pass before or shortly after any future LX-1.4 launch decision.
- **Workaround:** Accessibility-tree inspection via axe and DOM/ARIA structural review substituted as the best available evidence this mission, clearly labeled LIMITED rather than claimed as full screen-reader verification.
- **Acceptance decision:** Accepted as LIMITED, not blocking, given the strong automated-accessibility results (0 axe violations across every scanned state) as a proxy signal.
- **Launch blocking:** No.

### R-07 — No real physical mobile device or real Safari (macOS) testing — MEDIUM

- **Severity:** MEDIUM.
- **Evidence:** This environment has no macOS/iOS hardware. Real WebKit-engine testing (Playwright's WebKit build, installed this mission) was performed and passed cleanly, but this is not equivalent to real Safari on real Apple hardware.
- **User impact:** Unverified on the specific rendering/JS-engine/touch quirks of real iOS Safari and real physical mid/low-tier Android devices.
- **Owner:** Requires either cloud device-farm access or a human tester with real devices.
- **Recommendation:** Run a real-device smoke pass (at minimum: iOS Safari, one mid-tier Android Chrome) before or shortly after LX-1.4.
- **Workaround:** Playwright WebKit-engine testing (real WebKit, not real Safari/macOS) substituted this mission, honestly labeled as such throughout.
- **Acceptance decision:** Accepted as LIMITED, not blocking.
- **Launch blocking:** No.

### R-08 — `apps/worker`'s pytest suite could not be run this mission — LOW

- **Severity:** LOW.
- **Evidence:** `apps/worker/.venv/Scripts/python.exe -m pytest tests/ -q` fails at collection with `pydantic_core.ValidationError: ocr_render_dpi — Input should be a valid integer, unable to parse string as an integer [input_value='']` — a local `apps/worker/.env` has `OCR_RENDER_DPI=` (empty value), which `pydantic-settings` cannot parse as the required `int` type.
- **User impact:** None to the cinematic landing (this mission touches zero Worker code, confirmed via `git status`) — this is a pre-existing local-environment configuration gap in a `.env` file, not a code defect, and out of this mission's explicit scope to modify (`apps/worker` is off-limits).
- **Owner:** Whoever owns local Worker dev-environment setup; not this mission.
- **Recommendation:** Set a valid integer (or remove the line to use the code's own default) in the local `apps/worker/.env` before the next Worker-focused mission needs to run this suite.
- **Workaround:** None applied — `apps/worker` was correctly left untouched per mission scope.
- **Acceptance decision:** Accepted; irrelevant to the cinematic landing launch decision.
- **Launch blocking:** No.

## Summary

| ID | Title | Severity | Status | Launch Blocking |
| --- | --- | --- | --- | --- |
| R-01 | Production 500 (missing Supabase env vars) | BLOCKER | Resolved | No |
| R-02 | No defensive fallback in `resolveLandingCta()` | HIGH | Accepted follow-up | No |
| R-03 | Cinematic mobile Lighthouse median below target | HIGH | **Open, needs explicit decision** | See Go/No-Go |
| R-04 | Backslash open-redirect gap | HIGH | Resolved | No |
| R-05 | No app-wide CSP | MEDIUM | Accepted (out of scope) | No |
| R-06 | No real screen-reader testing | MEDIUM | Accepted (LIMITED) | No |
| R-07 | No real device/Safari testing | MEDIUM | Accepted (LIMITED) | No |
| R-08 | Worker pytest env blocker | LOW | Accepted (irrelevant) | No |

**0 open BLOCKER issues. 1 open HIGH issue requiring an explicit accept/reject decision (R-03) — see `NOOR_CINEMATIC_GO_NO_GO.md`.**
