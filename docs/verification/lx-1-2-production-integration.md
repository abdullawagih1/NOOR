# LX-1.2 — Production Cinematic Landing Implementation and Controlled Integration — Verification Report

Status: **LX-1.2 — Production Cinematic Landing Integration Complete, Pending LX-1.3 Hardening and User Preview Approval.**

## 1. Scope confirmation

No backend/database/RLS/permissions/Worker code was touched. `supabase/migrations/`, `apps/worker/`, and every clinical-processing subsystem are unchanged — confirmed via `git status` (see §12 below): only `apps/web/**` and `docs/**` files are modified/added.

## 2. Feature-flag matrix

| Environment | `NOOR_PUBLIC_LANDING_EXPERIENCE` | Root experience | `/design/cinematic-landing` | Deployment Protection | Verified |
| --- | --- | --- | --- | --- | --- |
| Local development | `cinematic` (recommended) | Cinematic | Available (dev) | N/A | Yes — real local production build |
| CI (`apps/web` tests) | both, unit-tested | N/A | N/A | N/A | Yes — 5 flag-value + 9 malformed-value cases |
| Vercel Preview | `cinematic` | Cinematic | Available (`NOOR_CINEMATIC_PREVIEW_ENABLED=true`) | Enabled, confirmed active (302) | Partially — deployment/build confirmed via CLI; HTTP content blocked by protection, no bypass token available |
| Production | absent (confirmed via `vercel env ls production` — 0 rows) | Legacy | Unavailable (404) | N/A (not gated the same way) | Yes — real `curl` against the live production URL, unchanged legacy content confirmed |

## 3. Auth routing report

| Scenario | Expected destination | Actual destination | Authorization checked | Status |
| --- | --- | --- | --- | --- |
| Unauthenticated visitor, `/` CTA | `/login` | `/login` | N/A | Pass (real E2E) |
| Successful login, no `next`, clinician membership | Authorized workspace (`/clinician`) | `/clinician` | Yes | Pass (real E2E — the reported defect is fixed) |
| Login with `next=<authorized safe path>` | That path | That path | Yes | Pass (unit test) |
| Login with `next=<unauthorized workspace path>` | Caller's own default workspace | Caller's own default workspace | Yes | Pass (unit test) |
| Login with `next=<external URL>` | Ignored, caller's own default workspace | Same | Yes | Pass (unit test, both `https://` and `//` forms) |
| No active membership | `/access-denied` | `/access-denied` | Yes | Pass (unit test) |
| Authenticated visitor visiting `/login` | Authorized workspace, form never shown | `/clinician`, form never shown | Yes | Pass (real E2E) |
| Authenticated visitor visiting `/` | "Open NOOR" → authorized workspace | "Open NOOR" → `/clinician` | Yes | Pass (real E2E, screenshot captured) |

Full narrative: `docs/landing/NOOR_CINEMATIC_AUTH_INTEGRATION.md`.

## 4. Scene 5 optimization

| Metric | Before (LX-1.1.1) | After (LX-1.2, 2 independent runs) |
| --- | --- | --- |
| FPS | 40 | 61, 56 |
| Draw calls (Scene 5) | not separately profiled in LX-1.1.1 | 27-29 |
| Triangles (Scene 5) | not separately profiled in LX-1.1.1 | 3,838-4,410 |
| Active particles (Scene 5) | 850 (full, unthrottled) | 209-467 (55% draw range) |

Root cause: simultaneity of subsystems (particles + 5 blocks/threads + beam + spine), not any one subsystem being disproportionately expensive on its own. 5 concrete changes made (2 eliminated per-frame allocations, shared materials, reduced tube segment counts, targeted particle draw-range throttling, skipped redundant writes). Full writeup: `docs/landing/NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`.

## 5. Performance report

See `docs/landing/NOOR_CINEMATIC_PERFORMANCE_BUDGET.md` for the full table. Headlines:

- Legacy `/` desktop: Performance 1.00, LCP 0.6s (regression-checked, unchanged from LX-1.1.1's own baseline).
- Cinematic `/` desktop: Performance 1.00, LCP 0.7s.
- Cinematic `/` mobile (simulated throttling): Performance 0.87 → **0.94** after a real fix (auth-check fast path via `getSession()` before `getUser()`).
- Real-GPU FPS: all 7 scenes ≥56fps, Scene 5 no longer an outlier.
- Canvas initialization does not block LCP (unchanged architecture from LX-1.1.1 — static poster → dynamic canvas import → crossfade).
- Route/bundle isolation reconfirmed: `three`'s chunk appears in zero other routes' served HTML, confirmed via live HTTP response inspection (not just build-manifest inspection).

## 6. Accessibility report

| Scan | Violations | Notes |
| --- | --- | --- |
| Legacy `/` desktop | 0 | |
| Legacy `/` mobile (390×844) | 0 | |
| Cinematic `/` desktop | 0 | |
| Cinematic `/` mobile (390×844) | 0 | |
| Cinematic `/` reduced motion | 0 | 0 canvas elements confirmed |
| Cinematic `/` WebGL disabled | 0 | 0 canvas elements, 0 page errors, CTA visible |
| `/login` | 0 (2 found and fixed: `landmark-one-main`, `region`) | Pre-existing, unrelated to cinematic content — see §8 |
| `/access-denied` | 0 (found and fixed alongside `/login`) | Same root cause |

## 7. SEO and metadata report

- `robots.ts`/`sitemap.ts` added — the app's first of either file.
- `generateMetadata()` added to `/` — truthful, experience-aware description.
- Design/prototype route noindex added as defense-in-depth for the Preview-reachable case.
- One real, investigated, honestly-documented framework limitation: `<meta name="description">` renders as a child of `<body>` instead of `<head>` on every dynamically-rendered route (confirmed pre-existing on `/login`, not introduced by this mission) — see `docs/landing/NOOR_CINEMATIC_SEO_METADATA.md` for the full root-cause investigation. SEO score is honestly `0.92`, not rounded to `1.00`.

## 8. Regression review

- Production `/`: confirmed live, 200, unchanged legacy hero text (`curl` against `https://noor-clinical-intelligence-os.vercel.app/`).
- `/login`, `/access-denied`, `/403`: all pass axe after the `AuthShell.tsx` landmark fix (a real, pre-existing gap this mission's broader scan coverage found — not a regression introduced by this mission's own feature work).
- All 25 `apps/web` test files pass (22 pre-existing + 3 new: `post-login-redirect.test.ts`, `public-landing-feature-flag.test.ts`, `public-root-integration.test.ts`; 2 pre-existing files updated: `public-pages-content.test.ts`, `cinematic-preview-gate.test.ts`, to match the `LegacyPublicLanding`/`CinematicPublicLanding` extraction).
- `apps/web` typecheck and lint both clean.
- Real local production build succeeds under both flag values.
- Backend (`apps/worker`, `supabase/migrations`) untouched — not re-run this mission since no file in either tree changed (confirmed via `git status`).

## 9. Preview deployment

- Preview URL (final, cinematic, restored after rollback rehearsal): `https://noor-pk1mu8e11-abdullah-wagihs-projects.vercel.app`
- Vercel project: `noor` (`abdullah-wagihs-projects/noor`)
- Deployment Protection: enabled, confirmed active via `302` on an unauthenticated request
- Commit at deploy time: uncommitted working tree (deployed via `vercel deploy`, which uploads the local file tree directly — this is the standard, intended workflow for reviewing local work before committing)
- Build: succeeded, `status: Ready`, `target: preview`
- Environment flags: `NOOR_PUBLIC_LANDING_EXPERIENCE=cinematic`, `NOOR_CINEMATIC_PREVIEW_ENABLED=true` (Preview scope only)
- Root status: confirmed via build logs (route table matches local build exactly)
- Login/prototype route status: present in build logs; direct HTTP content verification blocked by Deployment Protection (no bypass token available this session — see `NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md`)

## 10. Rollback rehearsal

| Step | Deployment | Result |
| --- | --- | --- |
| Initial cinematic Preview | `dpl_92fYPP9zUMxKT6fuMxBFGw6VzJa2` | Ready |
| Rollback to legacy | `dpl_FFYZMFZD8RiEtjU4oSenZv644rkz` | Ready, ~57s total, no code revert |
| Restoration to cinematic | `dpl_9f5QMxk6G4NfSnSKrXXqexyUQXnz` | Ready — final state for user review |

Full runbook: `docs/landing/NOOR_CINEMATIC_ROLLBACK_RUNBOOK.md`.

## 11. Motion and screenshot evidence

See `docs/verification/lx-1-2-media-index.md` for the complete, path-indexed table.

## 12. Git status

At the time of writing this report: working tree has the LX-1.2 changes as uncommitted modifications/new files (commits follow immediately after). No backend/database file appears in the diff. Pre-existing untracked files (`apps/web/public/brand.zip`, `docs/verification/screenshots/ux-1-1.zip`, `logo.jpeg`) remain untouched, per standing instruction.

## 13. Synthetic test data

One synthetic auth user, one profile row, one active `clinician` membership row were created against the real hosted "Noor Development" Supabase project for the real end-to-end auth-routing verification (§3), then deleted. Cleanup was itself verified: a follow-up query after deletion confirmed 0 residual `profiles`/`organization_memberships` rows for that user ID. Raw run log: `docs/verification/screenshots/lx-1-2/auth-e2e-results.json`.

## Final status

**LX-1.2 — Production Cinematic Landing Integration Complete, Pending LX-1.3 Hardening and User Preview Approval.**

## Recommended next task

**User review of the protected production-build Preview, followed by LX-1.3 performance and accessibility hardening.**
