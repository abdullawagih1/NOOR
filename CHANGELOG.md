# Changelog

## [Unreleased] — Sprint 0 remediation (Claude Code, this session)

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
