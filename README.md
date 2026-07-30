# Noor — Clinical Intelligence OS

Noor V1 is a controlled, evidence-grounded **Clinical Evidence Assistant**.
Clinicians ask a question inside one approved clinical domain; Noor
retrieves and cites only approved, versioned guideline text, and refuses to
answer when evidence is insufficient. Noor is not an autonomous diagnostician
— the clinician always retains final clinical authority.

This repository is at **Sprint 1, workstream S1-D1 — Extraction Review
and Technical Quality Gate**. Sprint 0.5's
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
retrieval, generation) did not exist as of that sprint — see
`docs/architecture/adr/0007-separate-clinical-and-processing-lifecycles.md`,
ADR 0008, and `KNOWN_LIMITATIONS.md`.

**S1-C1 — durable processing orchestration:** the Worker now claims a
queued (or due-for-retry) job atomically (`FOR UPDATE SKIP LOCKED`,
proven safe under real dual-process concurrency — zero double-claims
across 80 raced jobs), holds it via a hashed lease token with
heartbeat-based renewal, retries with exponential backoff up to
`max_attempts`, dead-letters on exhaustion, recovers a crashed Worker's
job via lease expiry, and supports user cancellation of queued/
retry-scheduled jobs — all proven end-to-end with a **controlled no-op
processor**, deliberately not real PDF extraction (that's Sprint 1.2B).
27/27 real Postgres 16 orchestration assertions, a genuine dual-OS-process
concurrency proof, and 27/27 Worker pytest assertions. See
`docs/domain/document-processing-orchestration.md`, ADR 0009, and
`docs/verification/sprint-1.2a-processing-orchestration-verification.md`.

**S1-C2 — deterministic PDF page and text extraction:** the Worker's
controlled no-op processor is replaced with a real, deterministic
extractor (`pypdf`, ADR 0010 — chosen over the mission's suggested
`PyMuPDF` specifically because that library is AGPL-3.0, a real licensing
risk for a commercial SaaS). Source integrity is revalidated twice,
independently, before any extraction begins; text is normalized
deterministically; a canonical JSON artifact (proven byte-identical
across repeated runs) is uploaded privately and independently
re-verified; finalization is atomic with idempotent identity-based reuse
— one succeeded extraction per `(source checksum, pipeline version,
configuration version, extractor name, extractor version)`. Two real
concurrency bugs were found and fixed by actually racing two independent
processes at the same extraction identity (not by reading the SQL) — see
`docs/database/deterministic-pdf-extraction-schema.md`. Verified end to
end against the real hosted Development project — real GoTrue JWT, real
Storage upload, the actual unmodified Worker code claiming and extracting
a real PDF, idempotent reprocessing, and the trust boundary confirmed
denied for both an org_admin and a clinician JWT. No OCR, no chunking, no
embeddings, no retrieval at extraction time — deliberately out of scope
(that's S1-D1+). See `docs/domain/document-extraction-lifecycle.md`,
ADR 0010, and `docs/verification/sprint-1.2b-pdf-extraction-verification.md`.

**S1-D1 — extraction review and technical quality gate:** "extraction
execution succeeded" and "extraction quality is accepted" are two
independent, database-enforced facts (ADR 0011). A permission-gated
reviewer workspace compares the original PDF against extracted text
page-by-page, records page-level and document-level technical findings
against a controlled 23-value taxonomy, and reaches one of five
database-validated decisions (accepted, accepted with warnings, OCR
required, reprocessing required, rejected) through a single transactional
function that re-checks every rule under lock. Downstream eligibility for
OCR and chunking is server-derived, never a client-writable flag; a
submitted decision is immutable except the one legal
accepted-to-invalidated transition; self-review is blocked at the
database level. No mutation of the deterministic extraction artifact —
deliberately out of scope, permanently. See
`docs/domain/extraction-review-lifecycle.md`, ADR 0011, and
`docs/verification/sprint-1-d1-extraction-review-verification.md`.

**S1-D2 — controlled page-scoped OCR:** only the exact pages a reviewer
explicitly flagged `ocr_candidate` are ever rendered or sent to an OCR
engine — never a whole document, never triggered by a technical
heuristic alone (ADR 0012). Self-hosted Tesseract (no cloud API; no
guideline content ever leaves Noor's own infrastructure for OCR) reads a
deterministically rendered page image (`pypdfium2`); one durable
processing job per page, one fully pinned OCR identity per attempt with
idempotent reuse, OCR technical review structurally separate from
execution status (the same execution/acceptance separation ADR 0011
established, one layer deeper), and a single canonical-representation
function (`get_document_page_text_readiness()`) that a future chunking
pipeline can trust without ever needing to know whether a page's text
came from native extraction or OCR. Permission-scoped Storage hardening
(migration 0010) closed a residual risk S1-D1 had documented:
`storage.objects` for source PDFs and processed artifacts now requires
an explicit permission, not mere organization membership. An OCR review
queue and side-by-side review workspace (original page, native
extraction, and OCR result together) complete the application layer.
Verified locally (four genuinely fresh Postgres 16 containers, 79
Worker pytest assertions including real, non-mocked Tesseract
recognition of English and mixed Arabic/English text, a real
Docker-image build-and-run smoke test, and a clean Web lint/typecheck/
build/test pass) **and on real hosted Development infrastructure** —
real GoTrue JWTs, a real upload, real extraction, a real page-scoped OCR
request, real Tesseract/pypdfium2 execution against real Storage, real
downstream chunking-eligibility flip, and a real permission-scoped
Storage RLS proof (denied for a clinician, permitted for the roles that
should have access) — all synthetic hosted data verified deleted back to
zero afterward. See
`docs/architecture/adr/0012-controlled-page-scoped-ocr.md` and
`docs/verification/sprint-1-d2-controlled-ocr-verification.md` for the
full record.

The repository is pushed to GitHub with CI passing on real GitHub Actions
runs (Sprint 1-D2's changes, including the `worker` CI job's new
tesseract-ocr install step, are pending their first real run). See
`PROJECT_STATE.md` for
the authoritative current status and open gaps (Playwright browser-driven
E2E remains a pre-Controlled-Beta requirement, not a blocker).

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
* `docs/domain/{guideline-registry,guideline-lifecycle,guideline-source-documents,document-intake-lifecycle,document-processing-orchestration,document-processing-lifecycle,document-extraction-lifecycle,document-extraction-artifacts,extraction-review-lifecycle,extraction-quality-findings}.md`
* `docs/database/{guideline-registry-schema,secure-document-intake-schema,document-processing-orchestration-schema,deterministic-pdf-extraction-schema,extraction-review-schema}.md`
* `docs/security/{guideline-registry-authorization,document-intake-authorization,worker-orchestration-authorization,pdf-extraction-security,extraction-review-authorization}.md`
* `docs/operations/{hosted-supabase-setup,vercel-preview-deployment,github-ci,environment-variables,worker-deployment,worker-processing-runbook,job-recovery-and-dead-letter,guideline-document-upload,pdf-extraction-worker-runbook,extraction-failure-recovery,extraction-review-runbook,extraction-review-reopening-and-invalidation}.md`
* `docs/design-system/NOOR_DESIGN_SYSTEM.md`
* `docs/verification/{sprint-0.5-hosted-verification,sprint-1-guideline-registry-verification,sprint-1.1-document-intake-verification,sprint-1.2a-processing-orchestration-verification,sprint-1.2b-pdf-extraction-verification,sprint-1-d1-extraction-review-verification}.md`
* `SECURITY.md`
* `KNOWN_LIMITATIONS.md`

## Status

See `PROJECT_STATE.md` for current phase, verified modules, open gaps, and
the recommended next task.
