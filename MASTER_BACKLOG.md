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
| E-06 | Worker service scaffold | **Implemented and verified** (91/91 pytest passing — 9 `/jobs`-contract + 18 orchestration + 32 PDF-extraction assertions + others) |
| E-07 | Document parsing (PDF text extraction) | **Partially implemented** — deterministic, non-OCR page-level text extraction is real and hosted-verified (see S1-C2); OCR, table reconstruction, and image extraction remain out of scope |
| E-09 *(new)* | Guideline registry (domains, authorities, guidelines, versions) | **Implemented and verified** — see S1-01 below |
| E-15 | AI Gateway (registry, validators) | **Partially implemented** — structured-answer schema + safety invariants done (`packages/clinical-schemas`); no provider adapters, registry tables, or gateway service yet |
| E-21 *(new)* | Clinical review / approval workflow | **Implemented and verified** — see S1-01 below |
| E-23 | Audit logging (correlation ID) | **Implemented and verified for the guideline registry and processing orchestration** — `audit_events` writes real for every guideline-registry mutation and for processing-job cancellation; routine claim/start/heartbeat/complete/fail/recover events go to `document_intake_events` only (not `audit_events`) by design — see `docs/domain/document-processing-lifecycle.md` |
| E-27 | CI/CD pipelines & environments | **Implemented and verified** — CI green on GitHub Actions; Vercel Preview deployed and healthy; hosted Supabase fully verified with real JWTs (Sprint 0.5 + Sprint 1) |
| E-31 *(new)* | Noor Design System foundation | **Implemented and verified** — `packages/ui`: tokens, 32 components, `/design-system` showcase, ADR 0005, accessibility contrast audit. See `docs/design-system/` |
| E-32 *(new)* | Durable processing orchestration (claim/lease/retry/dead-letter) | **Implemented and verified** — see S1-C1 below |
| E-33 *(new)* | Deterministic extraction artifacts and provenance (checksums, canonical JSON, idempotent identity) | **Implemented and verified** — see S1-C2 below |
| E-04, E-05, E-08, E-10–E-14, E-16–E-20, E-22, E-24–E-26, E-28–E-30 | All other epics | **Not started** |

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

### S1-C1 — Durable Processing Orchestration (worker claim, lease, retry, dead-letter) — **DONE**
- **Description:** Worker claims a `queued`/due-`retry_scheduled` job atomically (`FOR UPDATE SKIP LOCKED`), hashed-lease-token ownership, heartbeat-based lease renewal, `document_processing_attempts` history, exponential-backoff retry (30s/60s/120s.../900s cap, `max_attempts=3`), lease-expiry crash recovery, queued/retry-scheduled cancellation, and a Worker polling loop running a **controlled no-op processor only** — no real PDF extraction. Split out of the old `S1-C` so orchestration correctness could be proven independently of extraction logic. Absorbs the processing-control half of the old `S1-03`.
- **Team:** Backend/Supabase + AI/RAG + DevOps
- **Dependencies:** S1-B (done — `document_processing_jobs` rows now exist to claim)
- **Status:** Closed this session. Migration `0007_durable_processing_orchestration.sql`.
- **Verification:** 27/27 real assertions against a fresh Postgres 16 Docker container (`supabase/tests/rls/006_processing_orchestration.sql`, includes wrong-worker/wrong-token denial, idempotent-replay, retry-exhaustion → dead-letter, lease-expiry recovery, and cancellation-state coverage) + a genuine dual-OS-process concurrency proof (`supabase/tests/concurrency/verify_concurrent_claim.sh` — 80 real jobs, two independent `psql` connections racing, zero double-claims, zero lost jobs) + 27/27 Worker pytest assertions (`apps/worker/tests/test_orchestration_client.py`, `test_worker_loop.py`) + hosted verification. Full record: `docs/verification/sprint-1.2a-processing-orchestration-verification.md`.
- **Real bug found and fixed by actually running the new test file** (not by reading the SQL): the first draft's fixture pool had too few jobs for the number of fresh claims the test sequence needed, and separately asserted the shared Docker test database's claim queue would become globally empty — both wrong once the file was actually run against cumulative state left by prior test suites (005/006 both leave some jobs queued by design). Fixed by scoping assertions to the file's own fixture ids/distinctness rather than global counts. See `docs/database/document-processing-orchestration-schema.md`.

### S1-C2 — Deterministic PDF Page and Text Extraction — **DONE**
- **Description:** Real `pypdf`-based parsing (replacing S1-C1's controlled no-op processor) — page-level text extraction, normalization, page/artifact checksums, technical quality metrics, conservative suspected-scanned detection, a deterministic canonical JSON artifact uploaded to private Storage, and atomic finalization with idempotent identity-based reuse. Deliberately no OCR, no chunking, no embeddings, no retrieval (S1-D/S1-E scope). ADR 0010 records the extractor decision — `pypdf` (BSD-3-Clause) over `PyMuPDF` (AGPL-3.0, a real licensing risk for a commercial SaaS the mission's own suggested default would have introduced silently).
- **Team:** AI/RAG + Backend + Database
- **Dependencies:** S1-C1 (done — the claim/lease/retry/complete lifecycle a real processor plugs into now exists and is proven)
- **Status:** Closed this session. Complete and Hosted-Verified. Migration `0008_deterministic_pdf_extraction.sql`.
- **Verification:** Postgres 16 assertions across the full cumulative suite (001–008, all green, 117/117) including a new 19-assertion extraction schema/lifecycle suite (`supabase/tests/rls/008_pdf_extraction.sql`) and a permanent security-hardening regression (`007_security_hardening_review.sql`); two genuine dual-OS-process concurrency proofs (`verify_concurrent_claim.sh`, unchanged, and the new `verify_concurrent_extraction_identity.sh` — 5 consecutive runs, all 4 possible race outcomes observed, zero unexpected errors); 91 Worker pytest assertions (59 pre-existing + 32 new: fixture behavior against 11 synthetic PDFs, determinism, source-integrity revalidation, end-to-end processor orchestration). **Hosted Development**: migration applied, the corrected 007+008 suite green against real Postgres 17, and a real end-to-end flow — real GoTrue JWT, real RLS-authorized Storage upload, the actual unmodified Worker code claiming/extracting/uploading/finalizing a real PDF (5/5 pages), independent artifact re-download/re-hash, idempotent reprocessing, trust boundary and RLS confirmed for both an org_admin and a clinician JWT — all synthetic data cleaned up and confirmed zero-residual. Vercel Preview redeployed and healthy. Full record: `docs/verification/sprint-1.2b-pdf-extraction-verification.md`.
- **Real bugs found and fixed by actually running the concurrency tests** (not by reading the SQL): (1) `finalize_document_extraction_run()` raised a raw `unique_violation` when two genuinely simultaneous extraction attempts at the same identity both tried to mark themselves `succeeded` — fixed with an exception handler that gracefully adopts the winning run instead. (2) A second, related race then surfaced immediately: a job superseded mid-flight (after its own `create` call committed but before it reached `finalize`) raised a raw "not running" error instead of a classifiable one — fixed by explicitly detecting the supersession case and either adopting an already-succeeded winner or raising a clear, named, retryable error. See `docs/database/deterministic-pdf-extraction-schema.md`.

### S1-D — Extraction Review (structure-aware chunking, reviewer extraction queue) — Next
- **Description:** Structure-aware chunking of S1-C2's extracted text, and a real Reviewer extraction-review queue (approve/reject `document_chunks`). An OCR decision (whether/how to handle `suspected_scanned`/`no_text_layer` pages) is also in this workstream's scope. Absorbs the remainder of the old `S1-04`/`S1-05`/`S1-06`.
- **Team:** AI/RAG + Frontend + Backend
- **Dependencies:** S1-C2 (done — deterministic page-level text and artifacts now exist to chunk/review)
- **Priority:** P0
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
