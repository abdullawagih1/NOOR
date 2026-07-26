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

## Sprint 1 workstreams

**Reconciliation note (Sprint 1.1 session):** the prior report described only
"S1-01" as complete, but the delivered vertical slice also included the
full application layer, minimal Admin/Reviewer/Clinician UI, and hosted
verification — none of that was "not started." The flat `S1-NN` numbering
from the original Sprint 0 mission guess (§18.E) no longer reflects how
Sprint 1 actually decomposed once work began, so it's reorganized here into
coherent workstreams. Old `S1-02`–`S1-07` descriptions are preserved below
under the workstream that superseded or absorbed them, rather than silently
deleted — some (e.g. `S1-02`'s upload-session sketch) were superseded by a
more complete design once actually implemented (`S1-B`).

### S1-A — Guideline Registry (domains, authorities, versions, lifecycle) — **DONE**
- **Description:** `clinical_domains`, `guideline_authorities`, `guidelines`, `guideline_versions`, `guideline_reviews`, `guideline_lifecycle_events` tables with the draft → ready_for_review → approved → active → superseded → withdrawn lifecycle, database-enforced via a single `transition_guideline_version()` SECURITY DEFINER function, RLS on every table, full application layer (`apps/web/lib/guidelines/*`), and minimal UI (Admin Registry, Reviewer Queue, read-only Clinician view). Formerly "S1-01."
- **Team:** Backend/Supabase + Frontend
- **Status:** Closed. Migration `0005_guideline_registry_and_lifecycle.sql`.
- **Verification:** 41/41 real Postgres-16 assertions + 18/18 real hosted GoTrue-JWT assertions (Sprint 1 session). **G-12 (self-approval by a creator who also holds `guidelines.approve`) closed this session** with a live regression test — `supabase/tests/rls/004_g12_self_approval_regression.sql` — passing against both plain Postgres 16 and hosted, with evidence that lifecycle status, lifecycle events, and audit events all remained unchanged after the denied attempt. Full record: `docs/verification/sprint-1-guideline-registry-verification.md`.

### S1-B — Secure Guideline Source Document Intake — **DONE**
- **Description:** Guideline-version-scoped source document records, secure upload sessions with server-generated Storage paths, post-upload object verification (existence, size, PDF signature, SHA-256), duplicate detection, idempotent registration, and idempotent `document_processing_jobs` creation (queued only — no claim/execution). Supersedes the earlier `S1-02`/`S1-03` sketches (upload-session + queue-publish) with a fuller, verified design: server-side signature/checksum verification, released-version immutability, and an explicit upload-session state machine distinct from the document's own verification state machine and the clinical publication lifecycle (ADR 0008).
- **Team:** Backend/Supabase + Storage/Supabase + Frontend
- **Dependencies:** S1-A (done)
- **Status:** Closed this session. Migration `0006_secure_guideline_document_intake.sql`.
- **Verification:** 19/19 real assertions against a fresh Postgres 16 Docker container (`supabase/tests/rls/005_document_intake.sql`) + 16/16 real hosted assertions including actual Supabase Storage upload/download I/O (not just PostgREST RPCs) against the "Noor Development" project. **G-12 also closed this session** (see below) — verified on both environments. Full record: `docs/verification/sprint-1.1-document-intake-verification.md`.
- **Real bugs found and fixed by actually running migration 0006** (not by reading the SQL): two `RETURNS TABLE` functions had output-column names (`status`, `source_document_id`) that shadowed real table columns referenced later in the same function body, producing `column reference "..." is ambiguous` only at execution time. Fixed by table-qualifying the ambiguous references. See `docs/database/secure-document-intake-schema.md`.

### G-12 — Self-approval-by-a-permission-holding-creator — **CLOSED**
- **Description:** A live regression test proving that a guideline-version creator who ALSO holds `guidelines.approve` still cannot approve their own version — the one gap the Sprint 1 report left open (no seeded fixture combined "authored this version" with "holds guidelines.approve").
- **Team:** QA/Database
- **Status:** Closed this session. `supabase/tests/rls/004_g12_self_approval_regression.sql` (a synthetic role combining `guidelines.create`/`submit_for_review`/`approve`) passes against plain Postgres 16 and hosted Development with real JWTs — self-approval denied, `lifecycle_status` unchanged, no approval lifecycle event, no falsely-claiming audit event. The synthetic role and its mappings were cleaned up on hosted after verification.

### S1-C — Processing Orchestration (worker claim, retry, dead-letter) — Next
- **Description:** Worker claims a `queued` job (`claimed → processing → succeeded/failed`), heartbeat/lease semantics, retry with `attempt_count`/`max_attempts`, and `dead_lettered` handling. Publishes to Supabase Queues using the existing `apps/worker/app/main.py::JobMessage` contract (job_type aligned to the worker's existing `document_parsing` operation — see ADR 0008). Absorbs the processing half of the old `S1-03`.
- **Team:** Backend/Supabase + AI/RAG + DevOps
- **Dependencies:** S1-B (done — `document_processing_jobs` rows now exist to claim)
- **Priority:** P0
- **Risk:** Medium — idempotency and lease/heartbeat correctness under worker crash/restart
- **Tests required:** Claim-race test, heartbeat-timeout requeue test, max-attempts → dead_lettered test

### S1-D — Extraction and Verification (PDF parsing, chunking, reviewer extraction queue) — Future
- **Description:** Real PyMuPDF-based parsing (replacing the Worker's contract-validation-only stub), page extraction, structure-aware chunking, and a real Reviewer extraction-review queue (approve/reject `document_chunks`). Absorbs the old `S1-04`/`S1-05`/`S1-06`.
- **Team:** AI/RAG + Frontend + Backend
- **Dependencies:** S1-C
- **Risk:** Medium — malformed/malicious PDFs must fail safely, not crash (Red-Team Agent test required before this is called done)

### S1-E — Retrieval Preparation (embeddings, pgvector, AI provider) — Future
- **Description:** AI provider spike/selection (embedding/reranker/LLM, data-residency constraints in scope) and adapter interfaces, pgvector indexing, hybrid retrieval foundation. Absorbs the old `S1-07`.
- **Team:** AI/RAG + DevOps
- **Dependencies:** None to start the provider spike; S1-D for real embeddings content
- **Risk:** Medium — blocking for all downstream generation work

---

Sprint 0.5 items (`S1-09` CI execution, `S1-10` hosted Supabase, `S1-11`
Vercel Deployment Protection) were already closed before Sprint 1 began and
are recorded in `docs/verification/sprint-0.5-hosted-verification.md` and
git history rather than repeated here.
