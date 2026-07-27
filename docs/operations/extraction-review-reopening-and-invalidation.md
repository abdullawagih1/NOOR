# Extraction Review Reopening and Invalidation (Sprint 1-D1)

Companion docs: `docs/domain/extraction-review-lifecycle.md`, ADR 0011.

## Reopening — when a submitted decision needs a second pass

`reopen_extraction_review(review_id, reason)` requires
`guideline_extraction_reviews.reopen` (organization_admin,
quality_manager) and a non-empty reason. It only accepts a **submitted,
non-invalidated** round as its source (`accepted`,
`accepted_with_warnings`, `ocr_required`, `reprocessing_required`, or
`rejected` — not `pending_review`/`in_review`, and not `invalidated`).

What happens:

1. The prior round is **never mutated** — its `review_status`,
   `submitted_by`, `submitted_at`, `decision_reason`, and
   `warning_summary` remain exactly as they were, forever.
2. A brand-new row is inserted: `review_round = previous + 1`,
   `review_status = 'pending_review'`, `reopened_from_review_id`
   pointing at the prior round, `total_pages` carried over, but
   `pages_reviewed = 0` and `all_pages_reviewed = false` — **every page
   must be reviewed again from scratch**. Findings are **not** copied
   forward; the new round starts with none.
3. Downstream eligibility (`get_document_extraction_review_eligibility`)
   flips to ineligible for both OCR and chunking the instant the new
   round is created, since it always evaluates the **latest** round —
   there is no separate "was this reopened" flag to keep in sync.
4. A `document_extraction_review_events` row and a global `audit_events`
   row are written with `event_type = 'document_extraction_review.reopened'`,
   the reason, and the prior round's final status.

**Why findings aren't copied forward**: mission §30 explicitly leaves
this a policy decision ("copy unresolved findings only if policy
explicitly supports it"). Starting clean keeps the "100% pages reviewed
before a decision" invariant unambiguous — a reviewer re-establishes
every finding they still believe is real, rather than inheriting
potentially-stale ones from a different reviewer's prior pass.

## Invalidation — correcting an accepted decision without a new round

`invalidate_extraction_review(review_id, reason)` requires
`guideline_extraction_reviews.reopen` and a non-empty reason. It only
accepts `accepted` or `accepted_with_warnings` as the source status — not
`ocr_required`, `reprocessing_required`, `rejected`, or an already
`invalidated` round.

This is the **one** legal terminal-to-terminal transition in the whole
review state machine (`prevent_terminal_extraction_review_mutation()`
allows exactly this and nothing else). It exists for the case where a
pipeline defect or provenance problem is discovered **after** a review
already accepted the extraction — rather than requiring a whole new
review round, the existing accepted decision is marked invalidated in
place, with its original text preserved for the historical record.

Eligibility immediately reflects the invalidation (an `invalidated`
review status maps to `eligible_for_chunking = false` /
`eligible_for_ocr = false`, same as every other non-accepted status).

## Relationship to extraction-run invalidation

Migration 0008 reserved `document_extraction_runs.status = 'invalidated'`
for a future controlled process but no function sets it yet. When that
process exists, `get_document_extraction_review_eligibility()` already
handles it correctly today: it checks the extraction run's own `status`
first, and reports every eligibility flag `false` the instant the run
itself is anything other than `succeeded` — regardless of what the
latest review round says. No change to this sprint's eligibility function
will be needed when that future process ships.
