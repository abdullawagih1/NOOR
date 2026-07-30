# OCR Eligibility and Lifecycle (Sprint 1-D2)

See ADR 0012 for the architectural rationale. This document covers the
domain lifecycle: how a page becomes OCR-eligible, the request/run/review
state machines, and invalidation semantics.

## Eligibility is derived, never client-supplied

A page is OCR-eligible only when all of the following hold, checked
server-side inside `create_document_ocr_request()`:

1. The extraction review round is `ocr_required`.
2. That round has not been superseded by a later round (no reopening in
   between).
3. The underlying extraction run is still `succeeded`.
4. At least one `document_extraction_page_reviews` row for that round has
   `review_status = 'ocr_candidate'`.

A browser can never submit an arbitrary page number. The set of eligible
pages is entirely determined by which pages a reviewer explicitly marked
`ocr_candidate` while reviewing the extraction (Sprint 1-D1). A
`suspected_scanned` technical metric can *suggest* a page needs review,
but it never authorizes OCR by itself — a human decision always sits
between the metric and the request.

## Request lifecycle (`document_ocr_requests`)

```text
created (implicit) -> queued -> processing -> awaiting_review
  -> accepted | accepted_with_warnings | reprocessing_required | rejected
  -> cancelled (administrative)
  -> invalidated (administrative, or cascaded from the extraction review)
```

One request groups every eligible page from one extraction-review round.
`create_document_ocr_request()` is idempotent per
`(organization_id, extraction_review_id)` — replaying it while an active
(non-cancelled/non-invalidated) request already exists returns that same
request rather than creating a duplicate.

## Page lifecycle (`document_ocr_request_pages`)

```text
pending -> queued -> processing -> succeeded | failed
  -> awaiting_review -> accepted | accepted_with_warnings
  -> reprocessing_required | rejected
  -> cancelled | invalidated
```

Each request page maps to exactly one `document_processing_jobs` row
(`job_type = 'document_ocr'`) — one durable job per page, never one job
per document (ADR 0012). The partial unique index
`document_processing_jobs_one_active_ocr_per_page` allows two different
pages of the same document to have simultaneously-active jobs, but never
two active jobs for the same page.

## Execution run lifecycle (`document_ocr_runs`)

```text
running -> succeeded | failed | invalidated
```

One row per *attempt* at one OCR identity (organization + source checksum
+ extraction run + page + native page checksum + renderer identity +
rendered-image checksum + provider identity + model identity + OCR
configuration + language hints). `create_document_ocr_run()` is called
only after the Worker has actually rendered the page and knows the real
image checksum — this is a deliberate two-phase design (see
`docs/database/controlled-ocr-schema.md`), not an oversight. If an
identical identity already has a `succeeded` row, the call returns that
row (`out_reused = true`) instead of creating a new one, and the request
page is immediately marked `succeeded` — no second render, no second
provider call, no duplicate artifact.

A failed attempt does not block a later, distinct attempt at the same
identity: `document_ocr_runs.status = 'failed'` rows are preserved
alongside a later `succeeded` row for the same identity (the partial
unique index only constrains rows where `status = 'succeeded'`).

## Review lifecycle (`document_ocr_reviews` / `document_ocr_page_reviews`)

```text
pending_review -> in_review -> accepted | accepted_with_warnings
  | reprocessing_required | rejected
  -> invalidated (accepted/accepted_with_warnings only)
```

`ocr_required` is deliberately not a valid `document_ocr_reviews` status
— an OCR review only ever judges the *result* of OCR, never re-requests
more OCR (that is `reprocessing_required`, or a fresh extraction-review
round). A review can only be opened once every request page has reached
a terminal execution state (`succeeded` or `failed`), and can only be
submitted once every page has an explicit `document_ocr_page_reviews`
decision — opening a page in the review UI is never itself counted as
review.

Self-review is blocked at `start_document_ocr_review()` time: whoever
uploaded or registered the underlying source document cannot also be the
one who technically reviews OCR output derived from it — the identical
V1 policy Sprint 1-D1 established for extraction review, applied one
layer deeper.

## Invalidation and reopening

Reopening the *extraction* review (creating a new round) cascades: any
`document_ocr_requests` row still active for that extraction run
(`status not in ('cancelled', 'invalidated')`) is immediately invalidated
— its queued/claimed/processing jobs are cancelled, its non-terminal
pages are marked `invalidated`, and any open `document_ocr_reviews` round
is marked `invalidated` too. Already-`succeeded`/`failed` pages and their
runs are left untouched (mission: "no historical rows are deleted") —
only the *governance* rows (request/review) that would otherwise
authorize downstream use are closed out. `create_document_ocr_run()`
independently re-verifies, under lock, that no later extraction-review
round exists before creating or reusing a run — so even a Worker that
raced ahead of the cascade cannot finalize against a superseded round.

Reopening or invalidating the *OCR* review itself
(`reopen_ocr_review()` / `invalidate_ocr_review()`) is a narrower,
administrative action scoped to that one OCR request — it does not touch
the extraction review at all.
