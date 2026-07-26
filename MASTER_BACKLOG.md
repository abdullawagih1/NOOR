# Master Backlog

Epics E-01 through E-30 and the 10-week plan are defined in
`Noor_Onboarding_Architecture_Response.docx` (Sections G/H). This file
tracks execution status against that backlog and holds the Sprint 1
executable breakdown requested in the Sprint 0 mission (§18.E).

## Epic status after Sprint 1 (Guideline Registry Schema and Lifecycle)

| ID | Epic | Status |
|----|------|------------------------|
| E-01 | Identity, Orgs & RBAC foundation | **Implemented and verified** (migrations 0001+0002; permissions/role_permissions seeded) |
| E-02 | RLS & multi-tenant authorization framework | **Implemented and verified** (11/11 Sprint 0 RLS assertions + 26 Sprint 1 guideline-registry assertions, plain Postgres, real local Supabase, **and hosted with real JWTs**) |
| E-03 | App shell + role-based workspace routing | **Implemented and verified** — real Supabase SSR auth, session refresh, permission-gated layouts on all 4 workspaces + Noor Design System styling, controlled 403/access-denied pages, password reset flow |
| E-06 | Worker service scaffold | **Implemented and verified** (5/5 pytest passing) |
| E-09 *(new)* | Guideline registry (domains, authorities, guidelines, versions) | **Implemented and verified** — see S1-01 below |
| E-15 | AI Gateway (registry, validators) | **Partially implemented** — structured-answer schema + safety invariants done (`packages/clinical-schemas`); no provider adapters, registry tables, or gateway service yet |
| E-21 *(new)* | Clinical review / approval workflow | **Implemented and verified** — see S1-01 below |
| E-23 | Audit logging (correlation ID) | **Implemented and verified for the guideline registry** — `audit_events` writes now real (every guideline-registry mutation writes one, atomically, via SECURITY DEFINER functions); no other subsystem writes to it yet |
| E-27 | CI/CD pipelines & environments | **Implemented and verified** — CI green on GitHub Actions; Vercel Preview deployed and healthy; hosted Supabase fully verified with real JWTs (Sprint 0.5 + Sprint 1) |
| E-31 *(new)* | Noor Design System foundation | **Implemented and verified** — `packages/ui`: tokens, 32 components, `/design-system` showcase, ADR 0005, accessibility contrast audit. See `docs/design-system/` |
| E-04, E-05, E-07, E-08, E-10–E-14, E-16–E-20, E-22, E-24–E-26, E-28–E-30 | All other epics | **Not started** |

## Sprint 1 executable backlog

### S1-01 — Guideline registry schema and lifecycle — **DONE**
- **Description:** `clinical_domains`, `guideline_authorities`, `guidelines`, `guideline_versions`, `guideline_reviews`, `guideline_lifecycle_events` tables with the draft → ready_for_review → approved → active → superseded → withdrawn lifecycle, database-enforced via a single `transition_guideline_version()` SECURITY DEFINER function, plus RLS on every table. No file/document reference on `guideline_versions` by design — ADR 0007 keeps the clinical-publication and (not-yet-built) document-processing lifecycles as two separate state machines. `guideline_files` (the originally-sketched table name) does not exist — deliberately deferred to S1-02.
- **Team:** Backend/Supabase
- **Status:** Closed this session. Migration `0005_guideline_registry_and_lifecycle.sql`.
- **Verification:** 41/41 real assertions against a fresh Postgres 16 Docker container (`supabase/tests/rls/003_guideline_registry.sql`, 26 of them) + 18/18 real GoTrue-JWT assertions against the hosted "Noor Development" project. Full record: `docs/verification/sprint-1-guideline-registry-verification.md`. One real bug found and fixed by actually running the test file (psql `:'var'` substitution silently fails inside `DO $$...$$` blocks) — see PROJECT_STATE.md §-4.
- **Application layer + UI also delivered this session** (not originally scoped to S1-01 alone, but a natural extension): `apps/web/lib/guidelines/*`, Admin Registry (`/knowledge/guidelines/*`), Reviewer Queue (`/reviewer/guidelines`), read-only Clinician view (`/clinician/knowledge`).

### S1-02 — Upload session + private storage wiring
- **Description:** Vercel Route Handler creates an upload-session record and issues a scoped signed URL into a private `guideline-originals` bucket path `/{organization_id}/{clinical_domain}/{document_id}/{version}/original.pdf`.
- **Team:** Backend/Supabase + Frontend
- **Dependencies:** S1-01 (done), live Supabase project (done — hosted Development connected and verified since Sprint 0.5)
- **Priority:** P0
- **Risk:** High — first real file-upload path in the pipeline
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

### S1-10 — Hosted Supabase project — **DONE**
- **Description:** Connected to the pre-existing "Noor Development" project (`quohfsaqeqzbbvmrhmbr`, `eu-west-3`, Postgres 17). All 4 migrations applied (0004 new — fixes a real `anon`-grant finding, see below). 26 Auth/RLS/Authorization/Feature-flag/Audit assertions + 8 Storage assertions, all with real GoTrue JWTs — every one passed. Full record: `docs/verification/sprint-0.5-hosted-verification.md`.
- **Team:** DevOps
- **Status:** Closed this session.
- **Real finding fixed along the way:** `anon` held full CRUD grants on every public table (legacy Supabase project-creation default). RLS already blocked practical access; migration `0004_revoke_anon_table_grants.sql` closes the grant-layer gap too, guarded to no-op on the plain-Postgres CI container.

### S1-11 — Vercel Deployment Protection decision — **DONE**
- **Description:** Vercel's default "Vercel Authentication" gates every route on the deployed Preview. Decision made and applied: **keep it enabled** (not disabled) per explicit policy — Preview URLs may carry pre-release/real data later. Preview env vars configured with hosted Development values and redeployed; Supabase Auth URLs configured against a stable alias. "Protection Bypass for Automation" (dashboard-only — no CLI/API path exists) was subsequently configured by the user directly in the Vercel dashboard.
- **Team:** DevOps
- **Status:** Closed. `BASE_URL=https://noor-preview-dev.vercel.app BYPASS_TOKEN=<secret> node scripts/smoke-test-web.mjs` was run by the user against the protected Preview: 10/10 checks passed, including all 6 body-content checks confirming real Noor content (not the Vercel SSO page). See `docs/verification/sprint-0.5-hosted-verification.md`.
