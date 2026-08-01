# Deterministic Chunking Database Schema

Sprint 1-D3, migrations 0012 (schema + execution) and 0013 (chunk
technical review + embedding readiness) — the same execution/review
split as 0008/0009 (extraction) and 0011 (OCR), one layer deeper.

## Tables (migration 0012)

- **`document_chunking_runs`** — one execution attempt at one
  deterministic identity. Columns include the full identity tuple
  (`source_sha256`, `input_manifest_sha256`, `pipeline_version`,
  `configuration_version`, `normalization_version`, `tokenizer_name`,
  `tokenizer_version`), the Worker-computed `input_manifest` itself
  (stored for provenance/debugging, not just its hash), a full metrics
  column set, and artifact fields. `status` freezes on
  `succeeded`/`failed`/`invalidated`/`reused`, with `succeeded`/`reused`
  → `invalidated` as the one legal terminal transition. A partial unique
  index guarantees at most one `succeeded` row per identity tuple.
- **`document_chunks`** — one immutable chunk per `(chunking_run_id,
  chunk_index)`. `check (page_end = page_start)` enforces the V1
  hard-page-boundary policy as a real constraint. Fully immutable
  (UPDATE and DELETE both blocked unconditionally — no maintenance
  override exists for this table, unlike findings tables; a potential
  gap to revisit if a future sprint needs emergency deletion).
- **`document_chunk_source_spans`** — exact character provenance per
  chunk. Offsets are zero-based, start-inclusive, end-exclusive (see
  `docs/domain/chunk-provenance-and-source-spans.md`). Fully immutable.

## Tables (migration 0013)

- **`document_chunking_reviews`** — one review round per chunking run,
  mirroring `document_extraction_reviews`/`document_ocr_reviews`.
  Freezes on submission except for the one legal `accepted`/
  `accepted_with_warnings` → `invalidated` transition.
- **`document_chunk_reviews`** — one reviewer decision per `(round,
  chunk)`, mirroring `document_ocr_page_reviews`. Rows freeze once their
  parent round is terminal.
- **`document_chunk_findings`** — chunking-specific finding taxonomy (22
  types). `chunk_id` is nullable (a finding can be chunk-specific or
  run-level, mirroring extraction's own nullable
  `extraction_page_id`). Core content is immutable once created; only
  `status`/`resolution_note` may change. Deletion requires the same
  `noor.allow_audit_maintenance` GUC override every other finding table
  in this codebase uses.
- **`document_chunking_review_events`** — append-only audit trail,
  mirroring `document_extraction_review_events`.

## Key functions

**Client-facing** (granted to `authenticated`, permission-gated via
`assert_permission`):

- `create_document_chunking_job` — resolves eligibility, creates or
  reuses a `document_processing_jobs` row (`job_type =
  'document_chunking'`).
- `create_document_chunking_review`, `assign_chunking_reviewer`,
  `claim_chunking_review`, `start_document_chunking_review`,
  `mark_chunk_reviewed`, `create_chunk_finding`,
  `update_chunk_finding_status`, `submit_document_chunking_review`,
  `reopen_chunking_review`, `invalidate_document_chunking_run`.
- `get_document_embedding_readiness(p_source_document_id)` — the
  canonical derived truth table (never a stored flag), live-revalidating
  upstream extraction/OCR eligibility on every call, exactly like
  `get_document_extraction_review_eligibility`.

**Worker-only** (lease-token authenticated via `assert_lease_owner`,
never permission-gated, explicitly revoked from `authenticated`/`anon`):

- `get_document_chunking_job_context` — **not** a thin wrapper around
  `get_document_page_text_readiness()`. That function (and
  `get_document_extraction_review_eligibility`) calls
  `assert_permission()`, which checks `auth.uid()` — always `NULL` for
  this Worker's service_role RPC calls, so those two functions can never
  be called from Worker-only code (they would unconditionally raise
  "permission denied"). This function re-derives the identical readiness
  logic directly against the tables, extended to also return each
  page's actual text (which the permission-gated function does not
  return), authenticating purely via lease ownership like every other
  Worker-only function in this codebase. This exact class of bug — a
  Worker-only function accidentally calling a permission-gated one — was
  caught during this sprint's own local RLS verification (see
  `supabase/tests/rls/012_deterministic_chunking.sql`) before it ever
  reached a real deployment.
- `create_document_chunking_run` — identity-based idempotent creation;
  revalidates live extraction eligibility (via the same direct-table
  pattern, not the gated function) rather than trusting the Worker's
  claim-time snapshot.
- `finalize_document_chunking_run` — one atomic call that inserts every
  chunk and its source spans from Worker-computed JSON, **rejects
  finalization outright if `coverage_percentage <> 100` or
  `duplication_percentage <> 0`**, then marks the run succeeded and
  completes the job. A V1 simplification (documented in-line) versus
  batched inserts for very large documents — revisit if real document
  scale demands it.
- `fail_document_chunking_run`.

## Permissions

Seven `guideline_chunking.*` keys: `.read`, `.create`,
`.read_artifacts`, `.review`, `.submit_review`, `.reopen_review`,
`.invalidate`. Deliberately **no** `.cancel` — chunking-job cancellation
reuses the existing generic `guideline_processing_jobs.cancel`
permission and `cancel_processing_job()` function rather than inventing
a redundant parallel mechanism (a documented scope decision, not an
oversight).

## RLS

SELECT-only policies on all six tables, gated on
`has_permission_in_organization(organization_id, 'guideline_chunking.read')`.
All writes are `security definer` functions — no direct
INSERT/UPDATE/DELETE grants exist for `authenticated` on any of these
tables.

## Storage

Migration 0012 extends the existing `guideline-processed` bucket policy
(originally migration 0010, already extended once by migration 0011 for
OCR) to also accept `guideline_chunking.read_artifacts` — the chunking
artifact lives in the same bucket as extraction/OCR artifacts, one path
segment (`guideline-chunking/<document>/<pipeline_version>/<tokenizer>-<version>/<sha256>.json`)
distinguishing it.
