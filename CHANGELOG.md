# Changelog

## [Unreleased] — Environment Variables Audit, Standardization, and Security Hardening

### Added

* `apps/web/lib/env/{public,server,serverSchema}.ts` — centralized,
  zod-validated environment access. `public.ts`/`server.ts` are lazy
  functions (not pre-parsed constants) so the existing "static routes
  build without any Supabase config" property is preserved (re-verified —
  same route split as before). `server.ts` imports the `server-only` npm
  package; `serverSchema.ts` deliberately doesn't, so it stays unit-testable
  outside Next's bundler (`server-only` throws unconditionally in a plain
  Node/tsx process, discovered this session).
* `apps/worker/app/settings.py` — pydantic-settings `Settings` model.
  `WORKER_INTERNAL_TOKEN` has no default: the process now refuses to start
  at all if it's missing or under 32 characters (a real
  `pydantic.ValidationError` at import time, not a hypothetical — verified
  three ways: missing, too-short, and valid).
* `apps/worker/app/auth.py` — **`POST /jobs` now actually requires
  authentication.** The environment audit found `WORKER_INTERNAL_TOKEN`
  had been declared in every `.env.example` since Sprint 0 but never
  implemented anywhere — the endpoint accepted any request, unauthenticated,
  this whole time. Fixed: `Authorization: Bearer <token>`, constant-time
  comparison, 401 on missing/malformed header, 403 on wrong token, neither
  response leaks the expected value.
* CORS middleware wired into the Worker using the previously
  declared-but-unused `ALLOWED_ORIGINS` setting.
* `apps/worker/.env.example` — didn't exist before this session.
* `apps/web/tests/env.test.ts` (9 assertions) — valid/missing/malformed
  public and server env, optional-vs-required field behavior.
* Worker tests expanded from 5 to 9: missing token, malformed
  `Authorization` header, wrong token, and a check that error responses
  never leak the expected token value.
* `docs/operations/environment-variables.md` (full inventory,
  classification, rotation, incident-response guidance),
  `docs/operations/worker-deployment.md` (new).

### Fixed

* Real, once-thought-benign gap closed: the Worker's only real endpoint
  had no authentication at all. Found via a systematic audit
  (`grep -R "process\.env"` / `os.getenv` across the whole repo), not
  assumed — the audit table is in this session's conversation record.
* `.env.example` files (root, `apps/web`, new `apps/worker`) rewritten to
  an accurate, consistent, documented template — the root file previously
  listed `SUPABASE_ANON_KEY` without the `NEXT_PUBLIC_` prefix actually
  required by the code that reads it.

### Verified this session (not assumed)

* Boundary enforcement is real, not just documented: a throwaway `"use
  client"` component was made to import `lib/env/server.ts`; `next build`
  failed with an actual webpack error; the test file was then removed and
  a clean build reconfirmed.
* No secret leakage into the browser bundle: built `apps/web` with
  canary values for every server secret
  (`CANARY-SERVICE-ROLE-SECRET-...`, `CANARY-WORKER-TOKEN-...`), grepped
  the entire `.next/static` output — none appeared. Noted, not a defect:
  `lib/supabase/client.ts` (browser client) has no call sites yet, so
  `NEXT_PUBLIC_SUPABASE_ANON_KEY` doesn't currently reach the client
  bundle either — simply because nothing client-side reads it yet.
* `git grep` across tracked files for `sb_secret_`, real-looking
  `SUPABASE_SERVICE_ROLE_KEY=`/`WORKER_INTERNAL_TOKEN=`/
  `AI_GATEWAY_API_KEY=`/`SUPABASE_DB_PASSWORD=` values, and dangerous
  `NEXT_PUBLIC_`-prefixed secret names — all clean.
* Full local verification suite (lint/typecheck/test/build for Web;
  compile/pytest for Worker) re-run clean after every change in this
  session, not just once at the end.

## [Unreleased] — Sprint 0.5: Hosted Infrastructure & Design System Activation

### Added

* **`packages/ui`** (new workspace): canonical design tokens (colors,
  typography, spacing, radius, shadows — 16 clinical/system semantic states
  with icon + label + accessible description each), 22 generic primitives,
  10 Noor clinical components, `TokensStyleTag` (single-source CSS-variable
  injector). Tailwind CSS 3.4 added to `apps/web` as the utility layer,
  configured to import these tokens directly (`tailwind.config.ts`).
* `/design-system` showcase route (dev-only — 404s when
  `NODE_ENV=production`, verified via a real build).
* ADR 0005 (design-system composition) and ADR 0006 (Next.js
  security-version strategy).
* Password reset flow: `/forgot-password`, `/update-password`, wired
  through the existing `/auth/callback` route. Public signup stays
  disabled — documented as an intentional invite-only V1 Controlled Beta
  policy.
* `docs/design-system/{NOOR_DESIGN_SYSTEM,ACCESSIBILITY,SEMANTIC_STATES}.md`,
  `docs/operations/{hosted-supabase-setup,vercel-preview-deployment,github-ci}.md`.
* `scripts/smoke-test-web.mjs`: real HTTP smoke test (route protection,
  page availability, dev-only-route enforcement) — run against a local
  `next start` + real local Supabase this session, 10/10 passed.
* `apps/web/tests/{redirect,permissions}.test.ts`: open-redirect coverage
  for `sanitizeNextPath`, and a consistency check that every permission key
  referenced in code is actually seeded by migration 0002.
* CI: push-to-`main` trigger (previously PR-only) and a `gitleaks`
  secret-scan job.

### Changed

* **Next.js 14.2.35 → 15.5.21.** `npm audit` flagged ~19 advisories against
  14.2.35 with no non-breaking fix available; several were genuinely
  reachable through this app's actual Server Action / Middleware usage.
  Spiked the upgrade in an isolated git worktree first, hit and fixed Next
  15's "Async Request APIs" breaking change (`cookies()`/`searchParams` are
  now Promises — 7 files touched), fully re-verified, then applied to
  `main`. See ADR 0006 for the complete advisory list and exposure
  analysis.
* Every existing route (login, 403, access-denied, all 4 workspace shells)
  restyled onto `packages/ui` components; workspace navigation is now
  derived from the signed-in user's actual permissions, not hardcoded by
  route name.

### Fixed

* This is genuinely the first session the repository was pushed to GitHub
  (`git ls-remote` had confirmed the remote existed but was empty). CI now
  has two real, green GitHub Actions runs to point to, not just local
  YAML validation.
* Vercel project misconfiguration: the first `vercel link`/`deploy` (run
  from `apps/web`) scoped the upload to that directory alone, so the build
  failed trying to fetch the private `@noor/ui` workspace package from the
  public npm registry. Fixed by setting the project's Root Directory to
  `apps/web` via the Vercel API (no CLI subcommand exists for this) and
  re-linking from the repository root.

### Known, not fixed this session (see KNOWN_LIMITATIONS.md, PROJECT_STATE.md)

* No hosted Supabase project — blocked on credentials
  (`SUPABASE_ACCESS_TOKEN` or an interactive `supabase login`, neither
  available in this headless session).
* Vercel's default Deployment Protection ("Vercel Authentication") gates
  every route on the deployed Preview behind Vercel's own SSO — blocks
  automated HTTP verification of the live deployment. A caught, corrected
  false-positive: an early smoke-test pass against the Preview URL reported
  "200 OK" for several routes that were actually Vercel's SSO interstitial
  page, not Noor's app — `fetch()` had auto-followed the redirect. Fixed by
  inspecting response bodies, not just status codes; documented so it
  isn't repeated.
* No Playwright/browser-driven E2E of the login/password-reset forms —
  Next's Server Action wire protocol isn't a stable plain-`fetch` target;
  documented as a Sprint 1 gap rather than faked.

## [Unreleased] — Sprint 0 remediation (Claude Code, prior session)

An independent review of the prior sandbox delivery found the repository
had no `.git`, a stubbed auth middleware, an unseeded permissions table, a
tracked build artifact, and RLS claims verified only against plain
Postgres. This session reproduced every existing claim independently before
changing anything, then closed the real gaps.

### Added

* `git init -b main` — this is now an actual, real Git repository (it was
  not one before this session; see "Git status" in `PROJECT_STATE.md` for
  the current commit).
* Real Supabase SSR integration: `apps/web/lib/supabase/{client,server,
  middleware,service-role}.ts` using `@supabase/ssr` + `@supabase/supabase-js`
  (previously `server.ts` only read env vars — no SSR client, no cookies,
  no session at all).
* Real authentication flow: `/login` (email+password, safe-redirect only),
  `/auth/callback` (code exchange for magic-link/reset flows), a `signOut`
  server action, and `middleware.ts` now actually refreshes the session and
  redirects unauthenticated requests away from `/admin`, `/clinician`,
  `/reviewer`, `/quality` (previously a documented pass-through stub).
* `apps/web/lib/auth/context.ts`: `getAuthenticatedContext` /
  `requireActiveMembership` / `requirePermission` / `requireRole`, resolving
  identity, profile, active organization membership, and permissions from
  the database under RLS — never from client-supplied IDs. Each workspace
  now has a layout that calls `requirePermission(...)` before rendering.
  Controlled `/403` and `/access-denied` pages replace unhandled errors for
  permission-denied and no-active-membership cases.
* Migration `0002_sprint0_auth_hardening.sql`: seeds `permissions` and
  `role_permissions` (declared in 0001, never populated — no route could
  actually be authorized against a permission key before this), adds
  `has_permission_in_organization()`, a trigger preventing
  `organization_memberships.organization_id` reassignment, and a trigger
  making `audit_events` append-only for every runtime role (not just
  `public`) with a documented, narrow maintenance override.
* Migration `0003_storage_foundation.sql`: 5 private buckets
  (`guideline-originals`, `guideline-processed`, `evaluation-assets`,
  `generated-reports`, `temporary-uploads`) with organization-scoped RLS on
  `storage.objects`. Guarded to no-op against the plain-Postgres CI
  container (no `storage` schema there); verified for real against a local
  Supabase stack.
* `supabase/tests/rls/002_auth_hardening.sql`: 6 new assertions for the
  above. Both RLS test files were extended to set `request.jwt.claims`
  (real Supabase's actual `auth.uid()` source) alongside the existing
  `request.jwt.claim.sub` shim, so the same files now verify against both
  plain Postgres and real Supabase without duplication.
* `supabase/config.toml` (via `supabase init`) for local Supabase CLI
  development.

### Fixed

* Removed tracked build artifact `apps/web/tsconfig.tsbuildinfo`; expanded
  `.gitignore` to the full baseline (`coverage/`, `dist/`, `build/`,
  `*.tsbuildinfo`, `.env.*`, `.vscode/`, `.idea/`, Supabase CLI local state).
* Removed `apps/web/package-lock.json` and
  `packages/clinical-schemas/package-lock.json` — this is an npm workspaces
  monorepo (root `package.json`), and `npm ci`/`npm install` run from a
  workspace member directory silently resolves to the **root**
  `package-lock.json` regardless; the nested lockfiles were never actually
  read by npm and were misleading to keep. `.github/workflows/pr.yml`
  updated to `npm ci` once at the root per job and target each workspace
  with `--workspace=`, and `cache-dependency-path` corrected to point at the
  root lockfile that npm actually uses.
* Fixed a real production-build failure: the new permission-gated layouts
  read cookies via the Supabase server client, but Next.js still attempted
  to statically prerender `/admin`, `/clinician`, `/reviewer`, `/quality` at
  build time and failed on the (correct) missing-env-var error before it
  could opt into dynamic rendering. Added `export const dynamic =
  "force-dynamic"` to each workspace layout — the standard fix for
  session-dependent App Router routes.

### Verified this session (see PROJECT_STATE.md for full evidence)

* Worker: `compileall` + 5/5 pytest, from a clean venv.
* Web: `npm ci`, lint, typecheck, and production build all pass from the
  repository root using the corrected workspace-scoped commands; 10 routes
  generated (up from the previously reported 6 — 4 new: `/login`,
  `/auth/callback`, `/403`, `/access-denied`).
* clinical-schemas: typecheck + 6/6 tests, from a clean install.
* RLS: 11/11 assertions pass against plain Postgres 16 (matches CI), **and**
  11/11 pass again against a real local Supabase stack (`supabase start`,
  CLI v2.109.1) with the real `authenticated` role and real GoTrue
  `auth.uid()`. A real end-to-end request (GoTrue user → password sign-in →
  JWT → PostgREST `/rest/v1/organizations`) confirmed RLS-filtered results
  over actual HTTP; an anonymous request to the same endpoint was correctly
  rejected (401).
* Storage buckets and their RLS policies confirmed present in the real
  Supabase stack.

### Known, not fixed this session (see KNOWN_LIMITATIONS.md)

* `next@14.2.35` carries several disclosed advisories whose only fix is
  `next@16` — a breaking major-version upgrade, treated as an architecture
  decision requiring sign-off rather than a silent forced upgrade.
* No hosted Supabase project, no GitHub push, no Vercel deployment, no CI
  execution on GitHub Actions — all require credentials/access this session
  does not have.

## [Unreleased] — Sprint 0 initial delivery (prior sandbox session)

### Added

* Monorepo scaffold: `apps/web`, `apps/worker`, `packages/clinical-schemas`,
  `supabase/`, `clinical/`, `docs/`, `infrastructure/`, `.github/workflows/`.
* Migration `0001_identity_and_rls.sql`: organizations, organization_settings,
  profiles, roles/permissions/role_permissions, organization_memberships,
  access_reviews, audit_events, feature_flags, RLS policies and helper
  functions (`current_active_organization_ids`, `has_role_in_organization`).
* Synthetic seed data (`supabase/seed.sql`) covering active, suspended, and
  removed membership states across two organizations.
* RLS test suite (`supabase/tests/rls/001_tenant_isolation.sql`) — 7 tests,
  all passing: same-tenant access, cross-tenant denial, suspended-membership
  denial, removed-membership denial, non-admin privileged-write denial,
  unauthorized audit-read denial, audit-log append-only enforcement.
* Worker service scaffold (FastAPI): `/health`, `/ready`, `POST /jobs` with
  a typed, validated job contract. 5 tests passing.
* Web app scaffold (Next.js 14 App Router): landing page + 4 role-based
  workspace stubs (`/clinician`, `/admin`, `/reviewer`, `/quality`), server-
  only Supabase config accessor, auth middleware stub. Lint, typecheck, and
  production build all pass.
* `packages/clinical-schemas`: zod schema + safety invariants for the
  structured clinical answer contract. 6 tests passing.
* CI pipeline definition (`.github/workflows/pr.yml`) covering web, worker,
  clinical-schemas, and database/RLS jobs. YAML-validated; not yet executed
  on GitHub Actions (no remote push access in this environment).
* Governance docs: `INTENDED_USE.md` (draft), `RISK_REGISTER.md` (10 initial
  risks), 4 ADRs, database/API/operations documentation.

### Changed

* `next` pinned to `14.2.35` (not the originally scaffolded `14.2.15`) after
  `npm install` flagged a known security advisory in `14.2.15` — see
  SECURITY.md.

### Known limitations

See `KNOWN_LIMITATIONS.md`.
