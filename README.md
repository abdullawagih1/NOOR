# Noor — Clinical Intelligence OS

Noor V1 is a controlled, evidence-grounded **Clinical Evidence Assistant**.
Clinicians ask a question inside one approved clinical domain; Noor
retrieves and cites only approved, versioned guideline text, and refuses to
answer when evidence is insufficient. Noor is not an autonomous diagnostician
— the clinician always retains final clinical authority.

This repository is at **Sprint 1, workstream S1-B — Secure Guideline
Source Document Intake** (**Complete and Hosted-Verified**). Sprint 0.5's
hosted infrastructure foundation (identity/tenancy/RLS, real Supabase
Auth, the Noor Design System, the worker scaffold, the shared clinical
schema contract) is unchanged and remains verified — against plain
Postgres, a real local Supabase stack, a real hosted Supabase Development
project, and a protected Vercel Preview deployment (see
`docs/verification/sprint-0.5-hosted-verification.md`). See
`MASTER_BACKLOG.md` for how Sprint 1 is now organized into workstreams
(S1-A through S1-E) rather than a flat task list.

**S1-A — the controlled guideline registry:** clinical domains, guideline
authorities, guidelines, and guideline versions moving through a
database-enforced clinical publication lifecycle (draft →
ready_for_review → approved → active → superseded → withdrawn), with
review/approval separation, self-review/self-approval blocking (**G-12
closed** — this exact scenario is now live-tested against plain Postgres
and hosted, with a real GoTrue JWT), transactional supersession,
released-version immutability, and full audit logging. See
`docs/verification/sprint-1-guideline-registry-verification.md` and
`docs/domain/guideline-lifecycle.md`.

**S1-B — secure source-document intake:** upload sessions authorizing a
direct, private, tenant-scoped upload to Supabase Storage; server-side
object verification (existence, size, PDF signature, SHA-256 — computed
by the Next.js server after independently re-downloading the object,
never trusted from the browser); duplicate detection; idempotent
registration and `queued` processing-job creation. Verified against plain
Postgres (60/60 cumulative real assertions) and hosted Development
**including an actual Supabase Storage upload/download round trip**
(16/16 real assertions), not simulated. See
`docs/verification/sprint-1.1-document-intake-verification.md`,
`docs/domain/document-intake-lifecycle.md`, and ADR 0008. Document
*processing* (claiming a queued job, parsing, chunking, embeddings,
retrieval, generation) do not exist yet — see
`docs/architecture/adr/0007-separate-clinical-and-processing-lifecycles.md`,
ADR 0008, and `KNOWN_LIMITATIONS.md`.

The repository is pushed to GitHub with CI passing on real GitHub Actions
runs. See `PROJECT_STATE.md` for the authoritative current status and open
gaps (Playwright browser-driven E2E remains a pre-Controlled-Beta
requirement, not a blocker).

## Architecture

```
Vercel (Next.js)  →  short requests, user experience, permission-aware UI
Supabase           →  identity, Postgres, RLS, storage, pgvector, queues
External Worker    →  PDF parsing, chunking, embeddings, evaluation (Python)
```

Full rationale: `docs/architecture/DECISIONS.md` and the three source
architecture documents referenced there.

## Repository layout

```
apps/web/             Next.js application (real Supabase Auth, role-based workspaces)
apps/worker/           FastAPI worker (long-running AI/document processing)
packages/clinical-schemas/   Shared structured-answer contract (zod)
packages/ui/           Noor Design System — tokens + 32 components (packages/ui)
supabase/config.toml   Supabase CLI project config (local dev stack)
supabase/migrations/   Versioned SQL migrations
supabase/tests/rls/    RLS test suite (tenant isolation / auth-hardening / guideline registry)
supabase/seed.sql      Synthetic seed data — no real patient data, ever
scripts/               Reproducible verification scripts (HTTP smoke test)
clinical/              Intended Use, risk register, evaluation sets
docs/                  Architecture, domain, database, design-system, security, operations documentation
```

This is an **npm workspaces** monorepo (root `package.json`:
`"workspaces": ["apps/web", "packages/*"]`). Install and run scripts from
the repository root — `npm ci` (or `npm install`) at the root resolves and
hoists dependencies for every workspace member; there is no per-app
`package-lock.json` (an earlier, unused one was removed — npm ignores a
nested lockfile once a parent `workspaces` field exists, so committing one
there is misleading rather than harmless).

## Local development

### Web app

```bash
npm install                                   # from repo root
npm run lint --workspace=apps/web
npm run typecheck --workspace=apps/web
npm run build --workspace=apps/web
npm run dev --workspace=apps/web
```

Copy `apps/web/.env.example` to `apps/web/.env.local` and fill in
`NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` (from `supabase
start` output, or a hosted project) before running `dev` — validated at
request time by `lib/env/public.ts`, which throws a clear error rather
than silently running unauthenticated if these are unset. Full variable
reference: `docs/operations/environment-variables.md`.

### Worker

```bash
cd apps/worker
pip install -r requirements.txt
cp .env.example .env   # set WORKER_INTERNAL_TOKEN — openssl rand -hex 32
python -m pytest tests/ -v
uvicorn app.main:app --reload --port 8080
```

The process refuses to start without `WORKER_INTERNAL_TOKEN` (≥32
characters) — see `docs/operations/worker-deployment.md`.

### Database / RLS tests

Two verification paths exist. Both are real, reproducible commands — run
either (or both) locally to reproduce the results in `PROJECT_STATE.md`.

**Plain Postgres** (matches the CI `database` job, no Docker required beyond
a Postgres 16 instance):

```bash
createdb noor_test
for f in supabase/migrations/*.sql; do psql -d noor_test -v ON_ERROR_STOP=1 -f "$f"; done
psql -d noor_test -v ON_ERROR_STOP=1 -f supabase/seed.sql
for f in supabase/tests/rls/*.sql; do psql -d noor_test -v ON_ERROR_STOP=1 -f "$f"; done
```

**Real local Supabase** (Docker required — this is what actually proves
behavior against GoTrue's real `auth.uid()`, the real `authenticated` role,
and PostgREST):

```bash
npx supabase start        # applies migrations + seed automatically
npx supabase status        # prints API_URL / ANON_KEY / SERVICE_ROLE_KEY / DB_URL

# Run the same RLS test files against the real Supabase Postgres container
# (find its name with `docker ps`, typically supabase_db_<project_id>):
docker exec -i supabase_db_noor psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/rls/001_tenant_isolation.sql
docker exec -i supabase_db_noor psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/rls/002_auth_hardening.sql

npx supabase stop
```

### Clinical schema contract

```bash
npm run typecheck --workspace=packages/clinical-schemas
npm test --workspace=packages/clinical-schemas
```

### Design system

```bash
npm run typecheck --workspace=packages/ui
npm run dev --workspace=apps/web    # then visit /design-system (dev only — 404s in production)
```

See `docs/design-system/NOOR_DESIGN_SYSTEM.md`.

### HTTP smoke test (real running server)

```bash
BASE_URL=http://localhost:3000 node scripts/smoke-test-web.mjs
```

Requires `apps/web` built with real `NEXT_PUBLIC_SUPABASE_*` env vars and
running (`next start` or `next dev`). To point `BASE_URL` at a protected
Vercel Preview, also set `BYPASS_TOKEN` (Vercel dashboard → Deployment
Protection → Protection Bypass for Automation) — see
`docs/operations/vercel-preview-deployment.md`. Without a valid token the
script correctly detects and reports the protection wall rather than
false-passing.

## Governing documents

* `clinical/intended-use/INTENDED_USE.md`
* `clinical/risk-management/RISK_REGISTER.md`
* `docs/architecture/DECISIONS.md`
* `docs/domain/{guideline-registry,guideline-lifecycle,guideline-source-documents,document-intake-lifecycle}.md`
* `docs/database/{guideline-registry-schema,secure-document-intake-schema}.md`
* `docs/security/{guideline-registry-authorization,document-intake-authorization}.md`
* `docs/operations/{hosted-supabase-setup,vercel-preview-deployment,github-ci,environment-variables,worker-deployment,guideline-document-upload}.md`
* `docs/design-system/NOOR_DESIGN_SYSTEM.md`
* `docs/verification/{sprint-0.5-hosted-verification,sprint-1-guideline-registry-verification,sprint-1.1-document-intake-verification}.md`
* `SECURITY.md`
* `KNOWN_LIMITATIONS.md`

## Status

See `PROJECT_STATE.md` for current phase, verified modules, open gaps, and
the recommended next task.
