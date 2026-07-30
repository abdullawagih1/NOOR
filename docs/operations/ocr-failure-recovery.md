# OCR Failure Recovery (Sprint 1-D2)

Companion to `docs/operations/job-recovery-and-dead-letter.md` (the base
lease-expiry/retry/dead-letter mechanics, unchanged) and
`docs/operations/extraction-review-reopening-and-invalidation.md` (the
identical pattern one layer up). This document covers OCR-specific
failure codes and their classification.

## Error codes (`app/ocr/errors.py`)

| Code | Retryable | Notes |
|---|---|---|
| `ocr_request_page_not_found` | No | Structural — the claimed job's `ocr_request_page_id` link is missing or broken; should not happen in normal operation. |
| `extraction_run_not_succeeded` | No | The underlying extraction run is no longer `succeeded` (e.g. a race with invalidation). |
| `ocr_request_not_eligible` | No | The OCR request is `cancelled`/`invalidated`, or its extraction-review round has been superseded by a reopening. |
| `source_object_missing` | Yes | Storage eventual-consistency lag is plausible, same as extraction. |
| `source_size_mismatch` / `source_checksum_mismatch` | No | Deterministic property of the current object — retrying won't change it. |
| `invalid_pdf_signature` / `corrupt_pdf` | No | Deterministic property of the source content. |
| `page_render_failed` | No | Deterministic property of the specific page (e.g. malformed page tree, out-of-range page number). |
| `ocr_provider_error` | Yes | A Tesseract subprocess failure may be transient (resource pressure). |
| `ocr_timeout` | Yes | Render or recognition exceeded `OCR_MAX_SECONDS`. |
| `artifact_serialization_failed` / `artifact_upload_failed` / `artifact_checksum_mismatch` | Yes | Same transient-infrastructure assumption as extraction. |
| `database_finalization_failed` | Yes | Covers `create_document_ocr_run`/`finalize_document_ocr_page` failures not otherwise classified. |
| `lease_lost` | No | Not reported via `fail_document_ocr_run` at all — a lost lease means another Worker already owns the job; reporting failure would be rejected by `assert_lease_owner` anyway. |
| `ocr_internal_error` | Yes | Conservative default, matching `pdf_extraction`'s `extractor_internal_error`. |

## Recovery paths

- **Retryable failure** (e.g. `ocr_provider_error`, `ocr_timeout`): the
  existing Sprint 1.2A retry/backoff machinery applies unchanged — the
  job moves to `retry_scheduled` with exponential backoff, and a
  subsequent claim re-attempts the *same* request page. If the prior
  attempt's `document_ocr_runs` row is `failed` (not `succeeded`), the
  retry's `create_document_ocr_run` call correctly creates a **fresh**
  run rather than reusing the failed one — the partial unique index only
  constrains `succeeded` rows, so both the failed attempt and the
  eventual successful one are preserved. Proven by
  `supabase/tests/rls/011_controlled_ocr.sql` TEST 19/20.
- **Terminal failure** (e.g. `page_render_failed`, `corrupt_pdf`): the job
  is `dead_lettered` once `max_attempts` is exhausted, same as extraction.
  The request page's status reflects `failed` (via `fail_document_ocr_run`,
  if a run row exists) or the job's own terminal state (if the failure
  happened before any run row was created, e.g. a render failure).
- **Crash recovery**: unchanged from Sprint 1.2A — a Worker that
  disappears mid-job (crash, forced restart) simply lets its lease
  expire; the existing lease-expiry recovery sweep reclaims the job for a
  fresh attempt. No OCR-specific recovery logic was added or is needed.

## Extraction-review reopening cascades into OCR failure/cancellation

Reopening the underlying extraction review does not merely block *new*
OCR request creation — it actively cascades into any OCR request still
active for that extraction run:

- Non-terminal `document_processing_jobs` (queued/claimed/processing) are
  set `cancelled`.
- Non-terminal `document_ocr_request_pages` are set `invalidated`.
- Any open `document_ocr_reviews` round is set `invalidated`.
- The `document_ocr_requests` row itself is set `invalidated`, with a
  reason referencing the reopening.

A Worker that had already claimed a page job before the reopening, and
only reaches `create_document_ocr_run` afterward, is independently
rejected there too (`create_document_ocr_run` re-verifies under lock that
no later extraction-review round exists) — the cascade and the
in-database re-check are two independent lines of defense against the
same race. See `docs/domain/ocr-eligibility-and-lifecycle.md` and
`docs/database/controlled-ocr-schema.md` for the full mechanism, and
TEST 21 for the proof.

## What is never deleted

Per mission §10 ("no historical rows are deleted"): a `document_ocr_runs`
row, once `succeeded` or `failed`, is never removed by any of the above
paths — invalidation only ever transitions *governance* rows
(`document_ocr_requests`/`document_ocr_request_pages`/`document_ocr_reviews`)
to a terminal, downstream-ineligible state. The underlying execution
history remains queryable for audit purposes indefinitely.
