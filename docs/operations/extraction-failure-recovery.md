# Extraction Failure Recovery (Sprint 1.2B)

Operational reference for what happens when extraction fails, and how to
recognize which failure class occurred. Companion to
`docs/operations/job-recovery-and-dead-letter.md` (Sprint 1.2A) — job-level
retry/dead-letter behavior is completely unchanged; this document is only
about the extraction-specific error taxonomy layered on top.

## The 17 error codes

`apps/worker/app/pdf_extraction/errors.py::RETRYABLE_BY_ERROR_CODE`:

| Error code | Retryable | Why |
|---|---|---|
| `source_document_not_verified` | No | The registered document isn't `verified`/`registered` — retrying won't change that without an unrelated action (e.g. re-registration) |
| `source_object_missing` | **Yes** | Possibly a Storage eventual-consistency lag ("Possibly" per the mission's own baseline table) |
| `source_size_mismatch` | No | The registered checksum/size don't match what's in Storage — a data-integrity problem, not transient |
| `source_checksum_mismatch` | No | Same as above |
| `invalid_pdf_signature` | No | The object isn't a PDF at all |
| `corrupt_pdf` | No | Deterministic property of the file's bytes |
| `encrypted_pdf` | No | Deterministic property of the file |
| `password_protected_pdf` | No | Same — this pipeline never attempts password recovery |
| `unsupported_pdf_feature` | No | Conservative default; a specific unsupported feature won't resolve itself |
| `pdf_open_failed` | No | Generic `pypdf` open failure not otherwise classified |
| `page_extraction_failed` | No | Deterministic property of that page's content |
| `artifact_serialization_failed` | **Yes** | Likely transient/environmental (e.g. resource pressure), not a PDF-content problem |
| `artifact_upload_failed` | **Yes** | "Transient artifact upload failure" per the mission's baseline table |
| `artifact_checksum_mismatch` | **Yes** | Likely a transport issue; a clean re-upload might succeed |
| `database_finalization_failed` | **Yes** | "Database timeout" per the mission's baseline table |
| `lease_lost` | No (for the current attempt) | Not reported via `fail_document_processing_job` at all — see below |
| `extraction_timeout` | **Yes** | Might succeed with a different resource situation or more time |
| `extractor_internal_error` | **Yes** | Conservative default, matching the existing unexpected-exception classification in `app/worker_loop.py` |

Where the mission says "Depends on classification" (`extractor_internal_error`,
`unsupported_pdf_feature`), the choice actually made is recorded above —
this table is the single source of truth, not a guess to re-derive later.

## `lease_lost` is structural, not a reported error code

Unlike the other 16 codes, `lease_lost` is never passed to
`fail_document_extraction_run`/`fail_document_processing_job` by the
extraction pipeline's own code. If a Worker's lease is reclaimed mid-extraction
(crash-recovery, Sprint 1.2A), its subsequent
`finalize_document_extraction_run`/`fail_document_extraction_run` calls
are rejected by `assert_lease_owner` before they can do anything — the
job simply becomes `retry_scheduled` via the existing orchestration
recovery path (`recover_expired_document_processing_jobs`), and a later
attempt picks it up. There is no code path where the Worker itself
detects "I lost my lease" and reports it as a distinct error — the
database's own lease-hash check is the enforcement mechanism, not
client-side detection.

## Reading a failed extraction from the UI

The guideline detail page's Extraction Summary Card shows, for a `failed`
run: the status badge, `error_code`, and `error_message_safe` — never a
raw stack trace, never the local temp file path, never the Storage
bucket/path. The attempt number and job-level retry/dead-letter state are
shown via the existing Job Status Card (Sprint 1.2A) directly above it —
the two cards are deliberately separate (job-level retry state vs.
extraction-run-level failure detail), matching the same
composition-not-duplication principle the database layer uses (extraction
failure reporting calls `fail_document_extraction_run` and
`fail_document_processing_job` as two separate calls, not one merged
concept).

## Reprocessing after a fix

If a genuinely retryable failure (`artifact_upload_failed`,
`database_finalization_failed`, etc.) exhausts `max_attempts` and the job
dead-letters, or if a **non**-retryable failure needs to be retried after
an external fix (e.g. a `source_object_missing` case where the object
turns out to have been a genuine Storage inconsistency, now resolved):

* **No manual-retry UI or function exists this sprint** — `guideline_extractions.retry`
  is seeded as a permission but nothing checks it yet (matching the
  identical, deliberate deferral for dead-lettered *processing jobs* in
  Sprint 1.2A — see `docs/operations/job-recovery-and-dead-letter.md`).
* A new processing job for the same source document (e.g. via
  re-registration, if the application ever exposes that) would naturally
  create a fresh attempt at the same extraction identity —
  `create_document_extraction_run`'s reuse/supersede logic handles
  whatever state the previous attempt's `document_extraction_runs` row is
  in automatically (reuse if it somehow already succeeded, supersede if
  it's stuck `running` from a crash, or simply proceed if it's already
  `failed`).
* Direct database reactivation (mirroring the dead-letter runbook's
  pattern) remains the only path to force a specific extraction run back
  into a claimable state this sprint — intentionally not built into the
  application to avoid shipping an undertested reactivation UI.
