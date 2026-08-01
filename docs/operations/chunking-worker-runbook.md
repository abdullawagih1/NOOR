# Chunking Worker Runbook

Sprint 1-D3. Mirrors `docs/operations/ocr-worker-runbook.md`'s
structure one layer deeper.

## Enabling the chunking processor

Set `WORKER_PROCESSING_MODE=chunking` and include `document_chunking` in
`WORKER_ENABLED_JOB_TYPES` (the same opt-in-by-job-type mechanism
`extraction`/`ocr` modes already use — a mode alone does not start
polling for a job type unless it is also listed). No Supabase table
migration or extra credential is required beyond what extraction/OCR
already need (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) — chunking
reads already-accepted text directly from the database, never
re-downloads or re-parses the original file.

Optional overrides (all default to the pinned constants in
`apps/worker/app/chunking/config.py` when unset — only override for a
deliberate, reviewed identity bump):

- `CHUNKING_PIPELINE_VERSION`
- `CHUNKING_CONFIGURATION_VERSION`
- `CHUNKING_NORMALIZATION_VERSION`

There is no tokenizer-version override — `noor-simple-tokenizer`'s
version is a fixed, in-repo constant, not an external dependency that
could drift between environments.

## What one chunking job does

1. Claim a `document_chunking` job (`claim_next_document_processing_job`).
2. Read chunking context — every accepted page's text, checksum, and
   representation type — via the Worker-only
   `get_document_chunking_job_context` RPC.
3. Build the input manifest (ordered, canonically-serialized JSON of
   per-page representation identity) and its SHA-256, entirely in
   Python — never in SQL.
4. Call `create_document_chunking_run`. If an identical identity already
   succeeded, the Worker reports success immediately (`reused: true`)
   without re-running the pipeline.
5. Otherwise: segment each page into blocks, bin-pack into chunks,
   compute coverage/duplication, build the canonical artifact, upload it
   to the `guideline-processed` bucket, and call
   `finalize_document_chunking_run` with every chunk and its source
   spans.
6. On any failure, call `fail_document_chunking_run` with a safe error
   code/message before letting the job fail — the same pattern
   extraction/OCR processors use.

## Failure modes and retry behavior

See `apps/worker/app/chunking/errors.py` for the authoritative
retryable/non-retryable classification. In summary:

- **Non-retryable** (a structural property of the document, retrying
  will not help): `chunking_job_context_not_found` (only for the "job
  not found"/lease-related sub-case; the eligibility sub-case is
  classified terminal by the processor before this code is even used),
  `document_not_chunking_eligible`, `coverage_validation_failed`,
  `unexpected_duplication_detected`.
- **Retryable** (plausibly transient — network blip, storage
  eventual-consistency lag): `artifact_serialization_failed`,
  `artifact_upload_failed`, `artifact_checksum_mismatch`,
  `database_finalization_failed`, `chunking_internal_error`.

A `coverage_validation_failed`/`unexpected_duplication_detected` failure
means a real segmentation bug, not a transient condition — do not simply
retry; investigate the specific document's text (Arabic/mixed-language
edge cases are the most likely source, per this sprint's own testing)
and consider whether `CHUNKING_CONFIGURATION_VERSION` needs a fix
forward.

## Observability

Every RPC call carries a `correlation_id`. `document_chunking_runs`
records full metrics (`chunk_count`, `coverage_percentage`,
`duplication_percentage`, `hard_split_count`, `warning_chunk_count`,
etc.) queryable directly from the database — no separate metrics
pipeline exists yet for this sprint. `record_audit_event` is called on
every state transition (`document_chunking.input_manifest_created`,
`.succeeded`, `.failed`, `.invalidated`), visible in the existing audit
log alongside every other pipeline stage's events.

## Scaling note (documented limitation, not yet hit)

`finalize_document_chunking_run` inserts every chunk and span in one
atomic call, sized for this sprint's synthetic fixtures (a handful of
pages). A future revision may need batched inserts for very large real
documents — see the in-line comment on that function in migration 0012.
