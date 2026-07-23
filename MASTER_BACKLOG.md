# Master Backlog

Epics E-01 through E-30 and the 10-week plan are defined in
`Noor_Onboarding_Architecture_Response.docx` (Sections G/H). This file
tracks execution status against that backlog and holds the Sprint 1
executable breakdown requested in the Sprint 0 mission (§18.E).

## Epic status after Sprint 0.5

| ID | Epic | Status |
|----|------|------------------------|
| E-01 | Identity, Orgs & RBAC foundation | **Implemented and verified** (migrations 0001+0002; permissions/role_permissions seeded) |
| E-02 | RLS & multi-tenant authorization framework | **Implemented and verified** (11/11 RLS assertions, plain Postgres **and** real local Supabase) |
| E-03 | App shell + role-based workspace routing | **Implemented and verified** — real Supabase SSR auth, session refresh, permission-gated layouts on all 4 workspaces + Noor Design System styling, controlled 403/access-denied pages, password reset flow |
| E-06 | Worker service scaffold | **Implemented and verified** (5/5 pytest passing) |
| E-15 | AI Gateway (registry, validators) | **Partially implemented** — structured-answer schema + safety invariants done (`packages/clinical-schemas`); no provider adapters, registry tables, or gateway service yet |
| E-23 | Audit logging (correlation ID) | **Partially implemented** — `audit_events` table + RLS + trigger-based append-only enforcement done; nothing writes to it yet |
| E-27 | CI/CD pipelines & environments | **Implemented and verified** — CI corrected and has run green on GitHub Actions twice (real runs, not just local reproduction); Vercel project linked and building successfully; hosted Supabase and Vercel HTTP verification remain blocked (see PROJECT_STATE.md) |
| E-31 *(new)* | Noor Design System foundation | **Implemented and verified** — `packages/ui`: tokens, 32 components, `/design-system` showcase, ADR 0005, accessibility contrast audit. See `docs/design-system/` |
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

### S1-09 — CI execution on GitHub Actions — **DONE (Sprint 0.5)**
- **Description:** Pushed to `github.com/abdullawagih1/NOOR`; `pr.yml` now runs on push-to-main too (not just PRs), plus a `secret-scan` job. Confirmed 5/5 green twice on real GitHub Actions runs (see PROJECT_STATE.md for run URLs).
- **Team:** DevOps
- **Status:** Closed this session.

### S1-10 — Hosted Supabase project — **BLOCKED, credentials required**
- **Description:** Local Supabase CLI verification is done (Sprint 0 remediation + Sprint 0.5 re-verification). Creating the actual hosted Development project requires `supabase login` (interactive browser OAuth) or a `SUPABASE_ACCESS_TOKEN` — neither is available in this headless session. See `docs/operations/hosted-supabase-setup.md` for the exact, ready-to-run commands once either exists.
- **Team:** DevOps
- **Priority:** P0 — top blocking gap
- **Acceptance criteria:** All 3 migrations + both RLS test files pass unmodified against the hosted project (same 11/11 as local).

### S1-11 — Vercel Deployment Protection decision — **BLOCKED, owner decision required**
- **Description:** Vercel's default "Vercel Authentication" gates every route on the deployed Preview (including `/login`) behind Vercel's own SSO, blocking automated HTTP verification. Requires the project owner to either disable it or generate a "Protection Bypass for Automation" secret. See `docs/operations/vercel-preview-deployment.md`.
- **Team:** DevOps
- **Priority:** P1
- **Acceptance criteria:** `scripts/smoke-test-web.mjs` run against the live Preview URL produces genuine (not SSO-page) results.
