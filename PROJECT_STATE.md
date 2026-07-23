# PROJECT_STATE.md

**Last updated:** Sprint 0 remediation session (Claude Code, this environment)
**Updated by:** Noor Delivery Council (Claude Code, running locally against
the actual repository — not a chat sandbox)

---

## 0. Why this document was rewritten

An independent review of the previous sandbox delivery found discrepancies
between its report and the actual archive: no `.git` directory (a commit
hash had been reported that could not exist), a tracked build artifact
(`apps/web/tsconfig.tsbuildinfo`), an inaccurate file-count claim, a
pass-through auth middleware despite Sprint 0 requiring real authentication,
a Supabase "client" that was only an env-var accessor, RLS verified only
against plain PostgreSQL, and an overstated audit-immutability claim (grants
alone, no trigger, no acknowledgment of service-role bypass).

This session reproduced every one of those findings independently before
changing anything, then fixed the real ones. Every claim below states the
exact command run and the exact result — nothing here is carried forward
from the prior document without being re-verified.

---

## 1. Git status (real, not reported secondhand)

* Repository was **not** a Git repository at the start of this session
  (`git status` → "fatal: not a git repository"). No commit hash from any
  prior session can be reproduced, because no `.git` ever existed here.
* `git init -b main` was run. Primary branch is `main` (never `master`).
* Intended remote `https://github.com/abdullawagih1/NOOR.git` exists but is
  empty — confirmed via `git ls-remote` (exit 0, zero refs returned) this
  session. No push has been attempted; no credentials exist in this
  environment for it.
* This document (an earlier version of it) was committed together with the
  rest of the remediation work as commit `559aa5d816dd99827962ed4a06dfeb5787a3ba2c`
  ("Sprint 0 remediation: real git repo, real Supabase Auth, verified RLS").
  This paragraph was added in a follow-up commit immediately after, purely
  to record that hash — run `git log --oneline` yourself to confirm it
  rather than trusting this sentence; that is exactly the discipline this
  session was created to enforce.
* Working tree: clean after both commits.

---

## 1a. Repository statistics (generated, not asserted)

Command: `git add -A -n` (dry-run add, respects `.gitignore`) after cleanup,
counted this session:

* **73** tracked files total (excludes `.git`, `node_modules`, `.next`,
  caches, and every other `.gitignore`d path)
* **3** SQL migrations (`supabase/migrations/`)
* **2** RLS test files (`supabase/tests/rls/`, 11 assertions total)
* **2** apps (`apps/web`, `apps/worker`), **1** shared package
  (`packages/clinical-schemas`)

File count is reported here because a prior, external report cited a number
that doesn't match this repository's actual contents — not because file
count is a quality signal. It isn't; it's just an honest count.

## 2. Repository audit (reproduced this session)

| Area | Finding | Evidence |
|------|---------|----------|
| Git | Missing entirely | `git status` failed before `git init` |
| File count | No "91 files" or `fc4e7d0` claim exists anywhere in this repository's own text | `grep -rn "fc4e7d0\|91 files"` → no matches |
| Build artifacts | `apps/web/tsconfig.tsbuildinfo` was tracked-in-waiting (working tree, no `.git` to have tracked it yet) | Removed; `.gitignore` extended |
| `.gitignore` | Missing `*.tsbuildinfo`, `coverage/`, `dist/`, `build/`, `.env.*`, `.vscode/`, `.idea/`, Supabase CLI state | Rewritten to the full baseline |
| `middleware.ts` | Pass-through stub, comment admitted it | Read directly; now real |
| `lib/supabase/server.ts` | Env-var accessor only, no SSR client | Read directly; now real `@supabase/ssr` client |
| `permissions` / `role_permissions` | Declared in 0001, zero rows | `select count(*) from permissions` → 0 before this session's migration 0002 |
| RLS verification | Only ever run against plain Postgres | `PROJECT_STATE.md` (prior version) itself said so |
| Audit immutability | `REVOKE` only, no trigger, no service-role caveat | Migration 0001 read directly |
| npm workspaces / CI lockfile | `npm ci` in `apps/web` silently resolves to the **root** `package-lock.json`; the per-app lockfile was never actually read by npm | Reproduced empirically: ran `npm install` inside `apps/web`, root lockfile changed, `apps/web/node_modules` was never created |

---

## 3. Module classification (this session)

| Module | Classification | Evidence |
|--------|----------------|----------|
| Monorepo structure | Implemented and verified | Matches documented layout; artifacts cleaned |
| Identity/tenancy schema (0001) | Implemented and verified | Applies cleanly to plain Postgres **and** real local Supabase |
| Permissions + auth hardening (0002, new this session) | Implemented and verified | Seeds permissions/role_permissions; org-immutability + audit-immutability triggers; 6 new test assertions, all passing in both environments |
| Storage foundation (0003, new this session) | Implemented and verified | 5 private buckets + RLS confirmed present in real local Supabase |
| RLS policies | Implemented and verified — **against two environments** | 11/11 assertions passing against plain Postgres 16 AND a real local Supabase stack (real `authenticated` role, real GoTrue `auth.uid()`) |
| Real Supabase Auth (SSR clients, session refresh, login/logout/callback, permission-gated routes) | Implemented and verified | New this session — see §4 |
| Audit-event append-only enforcement | Implemented and verified, **honestly scoped** | Trigger blocks every runtime role including `service_role`; documented, narrow override exists for direct privileged sessions only — see `docs/database/schema.md` |
| Worker scaffold (`/health`, `/ready`, `/jobs`) | Implemented and verified | 5/5 pytest passing, clean venv, this session |
| Web app (real auth + 4 permission-gated workspaces) | Implemented and verified | lint clean, typecheck clean, production build succeeds, 10 routes generated |
| `packages/clinical-schemas` | Implemented and verified | 6/6 tests passing, clean install, this session |
| CI workflow definition | Implemented, corrected, unverified on GitHub | Real defect fixed (npm workspaces lockfile resolution); every job's commands independently reproduced locally; **still never run on GitHub Actions** — no push access |
| Governance docs (Intended Use, Risk Register, ADRs, SECURITY, KNOWN_LIMITATIONS) | Implemented, corrected | Updated to remove overstated claims |
| Hosted Supabase project | **Blocked** | No credentials/infra access in this environment |
| Vercel deployment | **Blocked** | Depends on hosted Supabase project |
| Guideline/document/chunk/retrieval/generation schema | Not started | Deliberately deferred to Sprint 1 (MASTER_BACKLOG.md) |
| PDF parsing, chunking, embeddings | Not started | Worker validates job contracts only |
| AI Gateway / provider integration | Not started | No provider selected yet (Sprint 1 spike) |

---

## 4. Verification evidence (exact commands run, this session)

### Database / RLS — plain Postgres (matches CI's `database` job)

```
$ docker run -d --name noor_ci_pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=noor_test -p 55432:5432 postgres:16
$ for f in supabase/migrations/*.sql; do docker exec -i noor_ci_pg psql -U postgres -d noor_test -v ON_ERROR_STOP=1 < "$f"; done
→ 0001, 0002, 0003 all apply cleanly, exit 0

$ docker exec -i noor_ci_pg psql -U postgres -d noor_test -v ON_ERROR_STOP=1 < supabase/seed.sql
→ 5 users, 2 orgs, 5 memberships inserted, exit 0

$ docker exec -i noor_ci_pg psql -U postgres -d noor_test -v ON_ERROR_STOP=1 < supabase/tests/rls/001_tenant_isolation.sql
→ TEST 1–7 all PASSED, "ALL RLS TESTS PASSED", exit 0

$ docker exec -i noor_ci_pg psql -U postgres -d noor_test -v ON_ERROR_STOP=1 < supabase/tests/rls/002_auth_hardening.sql
→ TEST 1, 1b, 2, 3, 3b, 4 all PASSED, "ALL AUTH HARDENING TESTS PASSED", exit 0
```

### Database / RLS — real local Supabase (CLI v2.109.1, Docker)

```
$ npx supabase init && npx supabase start
→ applies 0001, 0002, 0003 automatically; auth.uid() shim in 0001 correctly
  no-ops (real Supabase already defines it); seed.sql loads; stack healthy

$ docker exec -i supabase_db_noor psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/rls/001_tenant_isolation.sql
→ TEST 1–7 all PASSED against the REAL `authenticated` role and REAL
  GoTrue-backed auth.uid() (via request.jwt.claims), exit 0

$ docker exec -i supabase_db_noor psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/rls/002_auth_hardening.sql
→ TEST 1, 1b, 2, 3, 3b, 4 all PASSED, exit 0

$ docker exec -i supabase_db_noor psql -U postgres -d postgres -c "select id, name, public from storage.buckets;"
→ all 5 buckets present, public=false

$ docker exec -i supabase_db_noor psql -U postgres -d postgres -c "select policyname, cmd from pg_policies where tablename='objects';"
→ noor_buckets_select_own_org (SELECT), noor_buckets_insert_own_org (INSERT)
```

**Real end-to-end proof (GoTrue → JWT → PostgREST → RLS), this session:**

```
$ curl .../auth/v1/admin/users  (service-role key)  → created a real auth user
$ (inserted profile + active clinician membership in org-alpha for that user)
$ curl .../auth/v1/token?grant_type=password        → real JWT issued
$ curl .../rest/v1/organizations?select=slug  -H "Authorization: Bearer <real JWT>"
→ [{"slug":"org-alpha"}]   — HTTP 200, correctly scoped to ONLY the caller's org

$ curl .../rest/v1/organizations?select=slug  -H "Authorization: Bearer <ANON_KEY>"
→ {"code":"42501", "message":"permission denied for table organizations"}
→ HTTP 401 — anonymous access correctly denied over real HTTP, not just SQL
```

(Test user deleted afterward via the admin API; `docker rm -f noor_ci_pg` and
`npx supabase stop` were run to leave no stray containers running.)

### Worker

```
$ py -3.13 -m venv .venv && .venv/Scripts/python -m pip install -r requirements.txt
$ .venv/Scripts/python -m compileall app          → OK
$ .venv/Scripts/python -m pytest tests/ -v
→ test_health, test_ready, test_accept_job_valid_contract,
  test_accept_job_rejects_unknown_operation,
  test_accept_job_rejects_missing_idempotency_key — 5 passed in 0.70s
```

### Web (from repository root — this is an npm workspaces monorepo)

```
$ npm ci
$ npm run lint --workspace=apps/web        → "No ESLint warnings or errors"
$ npm run typecheck --workspace=apps/web   → exit 0, no errors
$ npm run build --workspace=apps/web
→ Compiled successfully
→ 10 routes generated: / , /403, /access-denied (static);
  /admin, /clinician, /quality, /reviewer, /login, /auth/callback (dynamic,
  force-dynamic — session-dependent, correctly opted out of static
  prerendering after a real build failure surfaced this requirement)
→ Middleware bundled (84 kB)
```

A real defect was found and fixed during this step: the first build attempt
failed because the new permission-gated layouts read cookies via the
Supabase server client, but Next.js still tried to statically prerender
those routes and hit the (correct) missing-env-var throw before it could
opt into dynamic rendering. Fixed with `export const dynamic =
"force-dynamic"` on each workspace layout — the standard pattern for
session-dependent App Router routes.

`npm audit`: 5 vulnerabilities (1 moderate, 4 high) in `next@14.2.35` and its
`glob`/`postcss` dependents. The only fix is `next@16`, a breaking major
version — **not applied** this session; flagged in SECURITY.md as a
decision requiring explicit sign-off, not silently forced.

### Clinical schemas

```
$ npm run typecheck --workspace=packages/clinical-schemas   → exit 0
$ npm test --workspace=packages/clinical-schemas
→ 6/6 PASS: valid answer parses; insufficient-evidence-with-recommendations
  fails closed; out-of-scope-with-recommendations fails closed; citation of
  non-existent evidence_id fails closed; missing required field fails
  schema validation; requires_clinician_review must be literal true
```

### CI workflow

`.github/workflows/pr.yml` targets `pull_request: branches: [main, develop]`
(already correct before this session). A real defect was found and fixed:
because this is an npm workspaces monorepo, `npm ci` run with
`working-directory: apps/web` silently resolves to the **root**
`package-lock.json` (npm walks up to the workspace root regardless of which
member directory you're in) — the per-app lockfiles were dead weight that
npm never actually read, and `cache-dependency-path` pointed at the wrong
file. Fixed: removed the two per-app lockfiles, changed both Node jobs to
run `npm ci` once at the root and target their workspace with
`--workspace=`. Every command in `web`, `clinical-schemas`, and `worker`
jobs was independently reproduced locally this session (see above) with
matching results. **Still not run on GitHub Actions** — this environment
has no push access to the remote.

### Not run (and why)

| Check | Reason not run |
|-------|-----------------|
| CI on GitHub Actions | No push access to the remote from this environment (remote confirmed to exist and be empty) |
| RLS suite against a **hosted** Supabase project | No hosted project provisioned — only local CLI verification was possible |
| Vercel deployment | No hosted Supabase project to point at yet |
| E2E / browser tests | No live database with real users to click through against; unit/build-level verification only |
| Load / penetration tests | No deployed target |

---

## 5. Sprint 0 gap report

| Gap | Impact | Dependency | Risk | Owner | Acceptance criteria | Next task |
|-----|--------|-----------|------|-------|----------------------|-----------|
| G-01: No hosted Supabase project | Blocks Sprint 1's data-layer work going live; local verification is done and passing | None — can start immediately | Medium (downgraded — schema/RLS/auth is proven against real Supabase locally) | DevOps | Migrations + RLS suite pass unmodified against the hosted project | S1-08 |
| G-02: No git push access from this environment | Repo work is not yet in the actual GitHub remote | You, locally | Medium | You / DevOps | `git push` succeeds; CI runs on a real PR | S1-09 |
| G-03: Clinical domain not confirmed | Blocks guideline sourcing (S1-01 depends on it) | Clinical partner decision | Medium | Product/Clinical | Domain signed off in `INTENDED_USE.md` | Confirm or accept hypertension default |
| G-04: No AI provider selected | Blocks all generation-side work | Provider spike | Medium | AI/RAG | ADR recording provider decision + adapter interface | S1-07 |
| G-05: `next@14.2.35` has unresolved high-severity advisories | Fix requires a breaking major-version upgrade | Explicit decision to accept the risk or schedule the upgrade | Medium | DevOps/Frontend | ADR recording the decision; upgrade scheduled or risk formally accepted | Sprint 1 decision |
| G-06: No CI execution evidence on GitHub | Can't yet prove the pipeline catches regressions on a real PR | G-02 | Low | DevOps | 4/4 green checks on a real PR | S1-09 |
| G-07: Auth covers session/permission layer, not account lifecycle | No signup, no password-reset UI, no member-management screen | None — can start incrementally | Low | Frontend/Backend | Signup + admin member-management UI shipped | Sprint 1 |

---

## 6. Decisions recorded this session

* Repository initialized as a real Git repository (`git init -b main`) —
  it was not one before.
* `@supabase/ssr` (0.12.3) and `@supabase/supabase-js` (2.110.8) added —
  compatible with `next@14.2.35` / `react@18.3.1`, verified by a clean
  build.
* Per-app `package-lock.json` files removed; root lockfile is the single
  source of truth for this npm workspaces monorepo (see §4, CI workflow).
* `next@16` upgrade **not** applied despite `npm audit` findings — treated
  as an architecture decision requiring explicit sign-off, not a
  Sprint-0-hardening-pass action. Recorded as gap G-05.
* Audit-event immutability re-scoped from "REVOKE only" to "REVOKE + trigger
  for every runtime role, with a documented, narrow, direct-session-only
  override" — and the documentation now says exactly that, not "immutable"
  unqualified.

## 7. Open risks

See `clinical/risk-management/RISK_REGISTER.md`. Highest-priority open items
remain R-03 (cross-tenant access — now verified against real Supabase, not
just plain Postgres, strengthening this) and R-10 (provider/data-residency
constraint — not yet mitigated, spike not yet run).

## 8. Recommended next task

**S1-08 — stand up a hosted Supabase project.** Local verification against
a real Supabase stack is now done and passing (§4) — this closes the
biggest *logical* gap from the original Sprint 0 delivery. What remains is
purely an infrastructure-provisioning step: create the hosted project,
point Vercel's environment variables at it, and re-run the exact same
migrations and RLS test files against it unmodified. Do not begin Sprint 1
feature work (guideline registry, ingestion, embeddings, retrieval,
generation) until this is done — per the mission's explicit instruction not
to start Sprint 1 while Sprint 0 infrastructure verification remains open.
