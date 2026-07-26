# Sprint Current: Sprint 1.1 — Secure Guideline Source Document Intake

**Status:** Complete and Hosted-Verified. See `PROJECT_STATE.md` and
`docs/verification/sprint-1.1-document-intake-verification.md`.

Workstream `S1-A` (Guideline Registry Schema and Lifecycle) closed in the
prior session. This sprint is workstream `S1-B` — see `MASTER_BACKLOG.md`
for the reconciled Sprint 1 workstream breakdown (S1-A through S1-E).

## Mandatory corrections completed first

- [x] **G-12 closed** — a guideline-version creator who also holds
      `guidelines.approve` still cannot approve their own version. Live
      regression test `supabase/tests/rls/004_g12_self_approval_regression.sql`
      passes against plain Postgres 16 **and** hosted Development with real
      JWTs: request denied, `lifecycle_status` unchanged, no approval
      lifecycle event, no falsely-claiming audit event.
- [x] **Backlog reconciled** — `MASTER_BACKLOG.md` restructured from the
      flat `S1-NN` numbering into coherent workstreams (`S1-A` done,
      `S1-B` this sprint — now also done, `S1-C`/`S1-D`/`S1-E` future).

## Objectives

- [x] Domain model: `guideline_source_documents`, `document_upload_sessions`,
      `document_processing_jobs`, `document_processing_attempts`,
      `document_intake_events`
      (`supabase/migrations/0006_secure_guideline_document_intake.sql`)
- [x] Three separate state machines preserved: clinical publication
      (existing), upload session (created → authorized → completed /
      expired / rejected / cancelled), processing job (queued only in this
      sprint — claim/execution is S1-C) — ADR 0008
- [x] Server-generated, tenant-scoped Storage paths; direct private upload
      via signed upload authorization; no service-role key or arbitrary
      path/bucket selection reaches the browser
- [x] Server-side object verification: existence, size, PDF signature
      (`%PDF-`), SHA-256 — never trusting a browser-supplied checksum.
      Verified end-to-end against **real Supabase Storage**, not simulated.
- [x] Duplicate detection (same version rejected; same org other version
      allowed + explicitly recorded; cross-org structurally non-leaking)
- [x] Idempotent upload-session creation, upload completion, and processing
      job creation — verified via real replay against both environments
- [x] Released-guideline-version source immutability (no replacing the
      primary source of an active/superseded/withdrawn version)
- [x] Permissions + RLS (8 new permission keys; every write mediated by a
      SECURITY DEFINER function; clinicians see none of it)
- [x] Application layer + minimal upload/status UI
      (`apps/web/lib/documents/*`, upload panel on the guideline detail page)
- [x] Local Postgres 16 verification — 19/19 real assertions
- [x] Hosted Development verification — migration applied, 16/16 real
      assertions including actual Storage upload/download I/O, synthetic
      data and Storage objects cleaned up and confirmed deleted
- [x] Vercel Preview redeployed and confirmed healthy, Deployment
      Protection still correctly enforced

## Explicitly out of scope this task (per the mission)

PDF text extraction, OCR, chunking, embeddings, pgvector, retrieval,
reranking, LLM calls, answer generation, citation extraction, malware
scanning beyond signature validation, real clinical documents. Job claiming
and execution stop at `queued` — see ADR 0008.

## Next sprint

```text
Begin Sprint 1.2 — Processing Worker Claim, Retry, and Extraction Foundation
```

See `MASTER_BACKLOG.md` (S1-C).
