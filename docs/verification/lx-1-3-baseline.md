# LX-1.3 — Launch Readiness Baseline

Captured at the start of LX-1.3, commit `6aa3ea7` (LX-1.2's closing commit). Includes the repository-audit table (mission §7) and the fresh baseline capture (mission §8).

## 0. A production incident found and fixed before any other LX-1.3 work

Before capturing any baseline, `curl` against the real production URL
returned **HTTP 500** on both `/` and `/login`. Root-caused via live
`vercel logs` (not guessed): Production's Vercel environment had zero
environment variables configured — `NEXT_PUBLIC_SUPABASE_URL`/
`NEXT_PUBLIC_SUPABASE_ANON_KEY` were missing entirely. This predates
LX-1.2 (`/login` was already silently broken; `/admin` degraded
gracefully via middleware's fail-closed redirect), but LX-1.2's new
auth-aware CTA is what extended the same missing-env-var crash to the
previously-static, previously-working `/` route — turning a partial
gap into a full homepage outage.

Fixed, with explicit user approval before touching Production: copied
`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_APP_URL`, `APP_ENV` (the same
values already correctly configured in Preview) into the Production
environment scope, then triggered a real `vercel deploy --prod`.
Re-verified directly: `/` → 200, `/login` → 200, `/admin` → 200 (via
its normal redirect-to-login, not the env-crash fail-closed path). A
side effect also fixed: the canonical URL (`<link rel="canonical">`)
now correctly resolves to the real production domain instead of
`http://localhost:3000` (it was resolving against `metadataBase`,
which reads `NEXT_PUBLIC_APP_URL` — also missing until this fix).
`NOOR_PUBLIC_LANDING_EXPERIENCE` was NOT touched — Production remains
on `legacy`, confirmed via `vercel env ls production` before and after.
Full detail in `docs/launch/NOOR_LAUNCH_RISK_REGISTER.md` item R-01.

## 1. Repository audit table

| Area | Current State | LX-1.2 Claim | Verified | Gap | Action |
| --- | --- | --- | --- | --- | --- |
| Feature flag resolver | `getPublicLandingExperience()`, exact-match `"cinematic"`, fails closed | Matches | Yes — read directly | None found this pass | Expanded malformed-value test matrix (LX-1.3) |
| Root route selection | `page.tsx` selects one branch server-side, `dynamic="force-dynamic"` | Matches | Yes | None | — |
| Legacy component | `LegacyPublicLanding.tsx`, byte-identical copy | Matches | Yes | None | — |
| Cinematic component | `CinematicPublicLanding.tsx`, shared by `/` and `/design/cinematic-landing` | Matches | Yes | None | — |
| Three.js bundle boundary | `next/dynamic(..., {ssr:false})` in `CinematicCanvas` | Matches | Re-verified via live HTTP response (no `three` chunk ref on `/`, `/login`) | None | — |
| Auth redirect resolver | `resolvePostLoginDestination()`, never returns `/` | Matches | Yes — unit tests + prior real E2E | None | — |
| Root CTA resolver | `resolveLandingCta()`, "Sign in"/"Open NOOR" | Matches | Yes | **Real production incident**: calls `getAuthenticatedContext()` unconditionally with no defensive handling for a Supabase/env failure — see item 0 above | Production env restored; defensive fallback evaluated in LX-1.3 hardening (see Resilience Report) |
| `robots.ts`/`sitemap.ts` | Present, correct disallow list | Matches | Yes | None | — |
| CSP/security headers | **None configured anywhere** — no `headers()` in `next.config.mjs`, no `vercel.json` | Not previously documented | Confirmed absent | Real gap, pre-existing, not cinematic-specific | Documented as MEDIUM in risk register, not introduced by or fixed in this mission (out of whole-app scope) |
| Existing observability | None (confirmed again) | Matches LX-1.2 finding | Yes | None | — |
| Vercel project config | `noor` project, linked correctly | Matches | Yes | **Production auto-deploys `main` via GitHub integration** — not previously documented as an operational fact | Documented in this baseline and the rollback runbook update |
| Deployment Protection | Enabled on Preview | Matches | Re-confirmed (302 on unauth request) | None | — |
| Preview environment variables | Supabase + cinematic/landing flags present | Matches | Yes | None | — |
| Production environment variables | **Was completely empty before this mission's fix** | Not documented in LX-1.2 (only checked for the landing-experience flag specifically, not the base Supabase vars) | Fixed this mission | See item 0 | Fixed |
| CI workflow | `.github/workflows/pr.yml`, lint/typecheck/test/build for web, clinical-schemas, Worker, RLS | Unchanged | Confirmed via green CI on the last 2 pushes | None | — |

## 2. Fresh baseline capture — production legacy

Captured **after** the incident fix above (the only state worth baselining):

- `/`: HTTP 200, real legacy hero content confirmed.
- `/login`: HTTP 200.
- `/admin` (unauthenticated): HTTP 200 after following its redirect to `/login`.
- Canonical: `https://noor-clinical-intelligence-os.vercel.app` (correct).
- `robots.txt`/`sitemap.xml`: present (added in LX-1.2, unaffected by this incident).
- Further Lighthouse/screenshot/metadata detail: see `docs/verification/lx-1-3-hardening-report.md`.

## 3. Baseline capture — protected cinematic Preview

Deployment Protection remains enabled on Preview (unchanged, re-confirmed via a `302` on an unauthenticated request). As in LX-1.2, no bypass token is available in this session, so direct HTTP content verification of the hosted Preview URL was not possible. Every measurement in this mission's hardening report is against a real local production build running byte-identical code (confirmed via matching Vercel build-log route tables), honestly labeled as such rather than claimed as hosted-Preview verification.
