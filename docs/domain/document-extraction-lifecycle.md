# Document Extraction — Lifecycle and Provenance (Sprint 1.2B)

Source: `supabase/migrations/0008_deterministic_pdf_extraction.sql`,
`apps/worker/app/pdf_extraction/*`. Builds on
`docs/domain/document-processing-lifecycle.md` — read that first; this
document only covers what Sprint 1.2B adds on top of the already-proven
claim/lease/retry/complete control plane.

## What this sprint proves

That claiming a `document_parsing` job can produce **reproducible,
integrity-linked page-level text and a deterministic artifact** — not
clinical review, not chunking, not embeddings, not retrieval. See ADR
0010 for the extractor decision and §2 of the mission for the governing
principles this implementation follows.

## `document_parsing` job_type reused, not a new `document_extraction` type

Migration 0006 already defined `document_processing_jobs.job_type =
'document_parsing'` — that value has meant "this job's payload is a PDF
that needs its text extracted" since Sprint 1.1, even though nothing
implemented it for real until now. Sprint 1.2B's Worker config uses
`WORKER_ENABLED_JOB_TYPES=document_parsing` (not the mission's suggested
`document_extraction` string) to stay consistent with the schema that's
already hosted-verified, rather than introducing a second, overlapping
job-type name for the same concept.

## Deterministic extraction identity

```
organization_id + source_sha256 + pipeline_version + configuration_version
  + extractor_name + extractor_version
= one identifiable extraction result
```

At most one `succeeded` `document_extraction_runs` row may ever exist per
identity (`document_extraction_runs_one_succeeded_per_identity`, a partial
unique index) — a second attempt at the same identity reuses the existing
result (`create_document_extraction_run`'s `out_reused = true`) rather
than re-extracting or creating a conflicting artifact.

## Extraction run lifecycle

```
running ──succeeds──▶ succeeded
   │
   └──fails──▶ failed

succeeded ──(future, controlled administrative process only)──▶ invalidated
```

Unlike `document_intake_events`/`audit_events`/`guideline_lifecycle_events`,
`document_extraction_runs` is **not** append-only — it mutates in place
from `running` to its terminal status, exactly like
`document_processing_jobs` itself. Once `succeeded`, a trigger
(`prevent_succeeded_extraction_run_mutation`) blocks any change to its
provenance/artifact-identity columns forever — the conditional-immutability
pattern migration 0006 established for `guideline_source_documents`, not
the unconditional append-only pattern. `document_extraction_pages` rows
are simpler: fully immutable from the moment they're inserted (no
legitimate update path exists at all — a reprocessing attempt creates a
fresh extraction run with its own fresh page rows instead).

## The three new functions

| Function | Caller | Purpose |
|---|---|---|
| `create_document_extraction_run` | Worker only | Re-verifies the job's lease and the source document's registered checksum/status; creates a `running` row, or returns an existing `running`/`succeeded` row at the same identity |
| `finalize_document_extraction_run` | Worker only | Verifies the actual persisted page count matches what's expected before marking `succeeded`; idempotent on replay |
| `fail_document_extraction_run` | Worker only | Marks the run `failed` with its error classification; does not itself touch `document_processing_jobs` |

All three follow the exact hardened pattern migration 0007 was corrected
to use after hosted verification found a real gap (ADR 0009's addendum):
narrow `search_path = public`, and an explicit, guarded `revoke ... from
authenticated`/`from anon` in addition to `revoke ... from public` — see
`supabase/tests/rls/007_security_hardening_review.sql` and
`docs/security/pdf-extraction-security.md`.

Page rows themselves are inserted via a **direct trusted table write**
(`OrchestrationClient.insert_extraction_pages`, a plain `service_role`
`POST /rest/v1/document_extraction_pages`), not a wrapper RPC — the
table's own CHECK/UNIQUE constraints and immutability trigger enforce
correctness regardless of the insert mechanism, and `service_role`
bypasses RLS by design (the same trust boundary every other Worker
write already relies on).

## Idempotent reuse and concurrent-race handling

Three scenarios, all correct, verified for real
(`supabase/tests/concurrency/verify_concurrent_extraction_identity.sh`):

1. **Clean reuse** — a worker's `create_document_extraction_run` call
   finds an already-`succeeded` row at its identity; returns it directly,
   `out_reused = true`. No page insert, no artifact upload, no finalize
   call needed at all.
2. **Genuinely simultaneous creation** — two workers both find nothing at
   the identity and both insert a fresh `running` row (the row-level lock
   inside `create_document_extraction_run` is per-*job*, not
   per-*identity*, so this is possible). Both proceed through extraction;
   whichever calls `finalize_document_extraction_run` first wins
   (`document_extraction_runs_one_succeeded_per_identity`); the second
   call's `UPDATE` hits a `unique_violation`, caught by an explicit
   exception handler that marks that run `invalidated` and returns the
   winner's result instead — never a raw constraint-violation error
   surfaced to the Worker.
3. **Stale attempt superseded** — a worker's `create_document_extraction_run`
   call finds an existing `running` row at the identity that belongs to a
   *different* processing attempt (the original attempt crashed before
   finalizing or failing it). That stale row is marked `failed`
   (`error_code = 'superseded_by_retry'`) and a fresh row is created for
   the current attempt — proven in
   `supabase/tests/rls/008_pdf_extraction.sql` TEST 17.
4. **Superseded mid-flight, before finalize** — the superseded job (from
   scenario 3) had *already* committed its own `create` call before being
   superseded, and only discovers this when it reaches
   `finalize_document_extraction_run`. If the superseding attempt has
   *already* succeeded by then, this worker adopts that winning result
   (same as scenario 2). If not yet, `finalize` raises a clear, named,
   retryable error rather than a raw exception — exactly what a real
   Worker's `OrchestrationError` handling classifies as a retryable job
   failure; a later retry cleanly reuses whichever attempt eventually
   succeeds. Found and fixed the same way as scenario 2 — by actually
   running the concurrency script repeatedly, not by reading the SQL —
   see `docs/database/deterministic-pdf-extraction-schema.md`.

## Failure taxonomy

17 named error codes (`apps/worker/app/pdf_extraction/errors.py`), each
with a retryable/terminal classification — see
`docs/operations/extraction-failure-recovery.md` for the full table and
the reasoning behind each choice. A `document_extraction_runs` failure is
always reported alongside a `fail_document_processing_job()` call with the
same classification, so job-level retry/dead-letter behavior (migration
0007, unchanged) and the extraction run's own recorded failure never
diverge.

## Domain events

Reuses `document_intake_events` (not a new table) for
`document_extraction.{started, source_verified, artifact_created,
succeeded, failed}` — consistent with Sprint 1.2A's reuse of the same
table for orchestration events. No event fires per page (mission §39: "do
not create a global audit event for every page"). No page text is ever
stored in an event's `metadata`.

## Permission matrix

| Permission | Grants ability to | Roles |
|---|---|---|
| `guideline_extractions.read` | Read extraction run status and technical metrics | `organization_admin`, `knowledge_manager`, `clinical_reviewer`, `quality_manager`, `safety_officer`, `auditor` |
| `guideline_extractions.read_pages` | Read individual extracted page text and per-page metrics | `organization_admin`, `knowledge_manager`, `clinical_reviewer`, `quality_manager`, `safety_officer` |
| `guideline_extractions.read_artifacts` | Read the artifact checksum (never the Storage path — that column is excluded from every application query regardless of permission) | `organization_admin`, `knowledge_manager`, `quality_manager`, `safety_officer` |
| `guideline_extractions.invalidate` | Reserved — no function checks this yet | `organization_admin`, `quality_manager` |
| `guideline_extractions.retry` | Reserved — no function checks this yet | `organization_admin`, `quality_manager` |

**Clinicians hold none of these permissions** (mission §28) — RLS
structurally returns zero extraction rows to a clinician session,
regardless of UI.
