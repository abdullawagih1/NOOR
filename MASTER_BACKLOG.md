# Master Backlog

Epics E-01 through E-30 and the 10-week plan are defined in
`Noor_Onboarding_Architecture_Response.docx` (Sections G/H). This file
tracks execution status against that backlog and holds the Sprint 1
executable breakdown requested in the Sprint 0 mission (§18.E).

## Epic status after Sprint 0

| ID | Epic | Status after Sprint 0 remediation |
|----|------|------------------------|
| E-01 | Identity, Orgs & RBAC foundation | **Implemented and verified** (migrations 0001+0002; permissions/role_permissions now seeded — previously declared but empty) |
| E-02 | RLS & multi-tenant authorization framework | **Implemented and verified** (11/11 RLS assertions passing against plain Postgres **and** a real local Supabase stack) |
| E-03 | App shell + role-based workspace routing | **Implemented and verified** — real Supabase SSR auth, session refresh, permission-gated layouts on all 4 workspaces, controlled 403/access-denied pages. Login/logout/callback exist and build/typecheck/lint clean |
| E-06 | Worker service scaffold | **Implemented and verified** (5/5 pytest passing) |
| E-15 | AI Gateway (registry, validators) | **Partially implemented** — structured-answer schema + safety invariants done (`packages/clinical-schemas`); no provider adapters, registry tables, or gateway service yet |
| E-23 | Audit logging (correlation ID) | **Partially implemented** — `audit_events` table + RLS + trigger-based append-only enforcement done; nothing writes to it yet, no correlation-ID propagation through a real request path |
| E-27 | CI/CD pipelines & environments | **Partially implemented** — `.github/workflows/pr.yml` corrected (was resolving the wrong lockfile due to npm workspaces; fixed and every job's commands independently reproduced locally); still never executed on GitHub Actions (no remote push access) |
| E-04, E-05, E-07–E-14, E-16–E-22, E-24–E-26, E-28–E-30 | All other epics | **Not started** |

## Sprint 1 executable backlog

### S1-01 — Guideline registry schema
- **Description:** Create `clinical_domains`, `authorities`, `guidelines`, `guideline_versions`, `guideline_files` tables with the draft→...→active/superseded/withdrawn lifecycle (Execution Plan §9) and RLS.
- **Team:** Backend/Supabase
- **Dependencies:** E-01, E-02 (done)
- **Priority:** P0
- **Risk:** Medium — lifecycle state machine must reject invalid transitions (e.g., activating a `draft` document directly)
- **Acceptance criteria:** Migration applies cleanly; RLS test proves a `draft`/`withdrawn` guideline is excluded from a "retrievable" view even for org members; state-transition constraint rejects an illegal jump (e.g., `draft → active`).
- **Tests required:** DB migration test, RLS test, state-transition constraint test
- **Estimated complexity:** M

### S1-02 — Upload session + private storage wiring
- **Description:** Vercel Route Handler creates an upload-session record and issues a scoped signed URL into a private `guideline-originals` bucket path `/{organization_id}/{clinical_domain}/{document_id}/{version}/original.pdf`.
- **Team:** Backend/Supabase + Frontend
- **Dependencies:** S1-01, live Supabase project (blocking — see Gap G-01 in PROJECT_STATE.md)
- **Priority:** P0
- **Risk:** High — first real Supabase project + credentials in the pipeline
- **Acceptance criteria:** Non-member cannot create an upload session for another org (403); uploaded file hash recorded; signed URL expires.
- **Tests required:** API test, storage-policy test, cross-tenant denial test
- **Estimated complexity:** M

### S1-03 — `document_processing_jobs` + queue publish
- **Description:** On upload completion, create a `document_processing_jobs` row and publish a `document_parsing` message to Supabase Queues using the exact contract in `apps/worker/app/main.py::JobMessage`.
- **Team:** Backend/Supabase + AI/RAG
- **Dependencies:** S1-02
- **Priority:** P0
- **Risk:** Medium — idempotency key collisions must be handled
- **Acceptance criteria:** Duplicate publish with the same idempotency key does not create a second job; job row transitions `uploaded → validating`.
- **Tests required:** Queue contract test, idempotency test

### S1-04 — Worker: real PDF parsing (replace stub)
- **Description:** Implement PyMuPDF-based parsing in `apps/worker`, replacing the current contract-validation-only `/jobs` stub with an actual `document_parsing` handler that extracts pages and writes `document_pages` rows.
- **Team:** AI/RAG
- **Dependencies:** S1-01, S1-03
- **Priority:** P0
- **Risk:** Medium — malformed/malicious PDFs (Red-Team Agent must test before this is called done)
- **Acceptance criteria:** A known-good sample guideline PDF parses into pages preserving page numbers; a corrupted PDF fails into `parsing_failed`, not a crash.
- **Tests required:** Unit tests on sample PDFs (good + malformed), page-count assertion

### S1-05 — Structure-aware chunking
- **Description:** Chunk extracted pages into `document_chunks` preserving section/page provenance.
- **Team:** AI/RAG
- **Dependencies:** S1-04
- **Priority:** P0
- **Risk:** Low
- **Acceptance criteria:** Every chunk resolves to exactly one page and one document version; no chunk spans a page boundary silently.
- **Tests required:** Chunk-boundary unit tests

### S1-06 — Reviewer Workspace v1 (extraction review/approve)
- **Description:** Real `/reviewer` page (replacing the current static stub) listing pending `document_chunks` for review, with approve/reject actions writing `knowledge_reviews`.
- **Team:** Frontend + Backend
- **Dependencies:** S1-04, S1-05
- **Priority:** P0
- **Risk:** Low
- **Acceptance criteria:** Only `clinical_reviewer` role can approve; approval is audited with correlation ID.
- **Tests required:** RLS test (role gate), E2E happy-path test

### S1-07 — AI Gateway provider spike + adapter interface
- **Description:** Evaluate and select embedding/reranker/LLM providers (data-residency constraints for MENA deployment in scope); implement adapter interfaces in the gateway package without wiring a live key yet.
- **Team:** AI/RAG + DevOps
- **Dependencies:** None (can start immediately)
- **Priority:** P0
- **Risk:** Medium — blocking for all downstream generation work
- **Acceptance criteria:** Decision doc recorded as ADR; adapter interface compiles and is provider-agnostic (swapping providers requires no call-site changes).
- **Tests required:** Adapter interface unit tests with a mock provider

### S1-08 — Hosted Supabase project + environment wiring
- **Description:** Local Supabase CLI verification is now done (this session: `supabase start`, all migrations + both RLS test files re-run against the real `authenticated` role and real GoTrue `auth.uid()`, plus a real GoTrue-user → JWT → PostgREST round trip — see PROJECT_STATE.md). What remains is standing up an actual **hosted** Supabase project for Local/Preview/Staging and wiring real environment variables end to end (Vercel ↔ hosted Supabase).
- **Team:** DevOps
- **Dependencies:** None (can start immediately) — **this is the top remaining blocking gap**
- **Priority:** P0
- **Risk:** Medium (downgraded from High — the schema/RLS/auth design is now proven against real Supabase behavior locally, not just plain Postgres; remaining risk is hosted-environment-specific, e.g. connection pooling, email delivery, network path)
- **Acceptance criteria:** All 3 migrations and both RLS test files run unmodified against the hosted project; CI job `database` in `.github/workflows/pr.yml` goes green on GitHub Actions; `apps/web/.env.example` values are replaced with real hosted project values in Vercel's environment configuration (never committed).
- **Tests required:** Full Sprint 0 RLS suite re-run against the hosted project

### S1-09 — CI execution on GitHub Actions
- **Description:** Push this repository to `github.com/abdullawagih1/NOOR` and confirm all four `pr.yml` jobs (web, worker, clinical-schemas, database) actually run and pass on a real pull request.
- **Team:** DevOps
- **Dependencies:** Git push access (not available in this delivery environment — see PROJECT_STATE.md)
- **Priority:** P0
- **Risk:** Low, but currently blocked on access, not effort
- **Acceptance criteria:** A PR shows 4/4 green checks.
