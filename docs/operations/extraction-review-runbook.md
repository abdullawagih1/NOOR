# Extraction Review Runbook (Sprint 1-D1)

Companion docs: `docs/domain/extraction-review-lifecycle.md`,
`docs/domain/extraction-quality-findings.md`.

## For a reviewer

1. Open `/reviewer/extractions`. Filter by "Unassigned" or "Assigned to
   me". Each row shows the guideline/version, source filename, page
   count, and current review status.
2. Open a review. If unassigned, claim it or start it directly (starting
   auto-claims). If assigned to someone else, you cannot start it.
3. For each page: compare the original PDF panel (left) against the
   extracted, normalized text (right). Record findings as you find them
   (page-level, or document-level via the "Add a document-level finding"
   disclosure). Then mark the page reviewed — `reviewed_clear`,
   `reviewed_with_findings`, `ocr_candidate`, or `reprocessing_candidate`.
   Opening a page is never enough by itself; you must explicitly mark it.
4. Once every page is marked, the technical review checklist and decision
   form appear. Choose one of the five decisions:
   - **Accepted** — no open critical/major findings remain.
   - **Accepted with warnings** — no open critical findings; write a
     warning summary.
   - **OCR required** — at least one supporting finding
     (missing/partial text, image-only, suspected scanned, unexpected
     blank); write why.
   - **Reprocessing required** — at least one supporting finding; write
     why (e.g. wrong reading-order configuration).
   - **Rejected** — write why; requires at least one major/critical
     finding to exist.
5. Submit. The decision is immutable from this point (except the single
   `invalidated` transition, which only quality/admin can trigger).

## For an admin or quality manager

- **Assign/reassign**: `assign_extraction_reviewer()` — verifies the
  target actually holds review permission in your organization first.
- **Reopen**: only a submitted, non-invalidated round can be reopened;
  always requires a reason; always creates a fresh round starting at
  `pending_review` with zero pages re-marked (see
  `docs/operations/extraction-review-reopening-and-invalidation.md`).
- **Invalidate**: only an `accepted`/`accepted_with_warnings` round;
  requires a reason; the original decision text is preserved, only the
  status and reason change.

## Troubleshooting

**"A review can only be opened once extraction has succeeded"** — the
extraction run is still `running`, `failed`, or `invalidated`. Check the
Extraction Summary Card on the guideline detail page first.

**"You do not have permission to perform this action"** — either you
lack the specific permission (`guideline_extraction_reviews.review` to
start/submit, `.assign` to assign/reopen, `guideline_extraction_findings.*`
to create/resolve findings), or — for start/submit — you are not the
assigned reviewer and don't hold an override permission, or you are
blocked by the self-review rule.

**"Every page must be marked reviewed before a decision can be
submitted"** — check the page navigation strip for pages without a ✓
mark.

**The PDF panel shows "Could not load the source document"** — the
signed URL (5-minute lifetime) expired and re-minting failed, most often
because the underlying extraction run or source document was removed or
your session expired. Refresh the page.

## What this runbook does not cover

OCR execution and chunking are not implemented yet (Sprint 1-D2/1-D3) —
"OCR required" and "reprocessing required" are recorded decisions only;
no automated pipeline consumes them yet. See `MASTER_BACKLOG.md`.
