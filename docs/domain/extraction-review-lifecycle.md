# Extraction Review Lifecycle (Sprint 1-D1)

Companion docs: ADR 0011, `docs/domain/extraction-quality-findings.md`,
`docs/database/extraction-review-schema.md`,
`docs/security/extraction-review-authorization.md`.

## The governing principle

"Extraction execution succeeded" and "extraction quality is accepted" are
two independent facts. Sprint 1.2B's `document_extraction_runs.status`
answers the first question only — whether `pypdf` ran to completion
without a technical failure. It says nothing about whether the resulting
text is fit for downstream chunking, OCR decisions, or eventual retrieval.
This sprint adds the second, human, auditable answer.

## Two state machines, never one

```
Execution (migration 0008, unchanged):
  running -> succeeded -> [reviewed separately]
  running -> failed
  succeeded -> invalidated (reserved, no function sets it yet)

Review (migration 0009, this sprint):
  pending_review -> in_review -> accepted
                               -> accepted_with_warnings
                               -> ocr_required
                               -> reprocessing_required
                               -> rejected
  accepted | accepted_with_warnings -> invalidated (administrative only)
  accepted | accepted_with_warnings | ocr_required | reprocessing_required | rejected
    -> (reopen) -> a NEW pending_review round, never a mutation of the old one
```

A review round can only be opened against a `succeeded` extraction run —
`create_document_extraction_review()` rejects `running`, `failed`, and
`invalidated` runs outright.

## Review rounds, not edits

Every `document_extraction_reviews` row is one **round**. Reopening never
turns a submitted round back into a draft — it inserts a brand-new row
(`review_round = previous + 1`, `reopened_from_review_id` pointing back)
and leaves the old row exactly as submitted, forever. This is the same
append-only-round philosophy `guideline_reviews` already uses for
clinical review, generalized to the review lifecycle itself rather than
just the underlying event log.

At most one round may be **active** (`pending_review` or `in_review`) per
extraction run at a time — a partial unique index makes "duplicate active
review" structurally impossible, not just discouraged by the UI.
`create_document_extraction_review()` is itself idempotent: calling it
again while a round is already active returns that round rather than
erroring or creating a second one.

## Assignment and self-review

- `assign_extraction_reviewer()` (organization_admin/quality_manager):
  assigns or reassigns an active round, but only to a user who actually
  holds `guideline_extraction_reviews.review` in the same organization.
- `claim_extraction_review()`: any permitted, unassigned reviewer can
  self-claim an active round.
- `start_document_extraction_review()`: the assigned reviewer (or, if
  unassigned, whoever calls it — auto-claims on start) moves the round
  from `pending_review` to `in_review`. **Self-review is blocked here**:
  if the caller uploaded or registered the extraction's underlying
  source document, the function raises rather than starting. This is a
  deliberate V1 policy choice, not a full quorum system — see ADR 0011
  §3.6 for the reasoning and `KNOWN_LIMITATIONS.md` for what is
  explicitly not yet enforced (there is no "unless no other reviewer
  exists in the organization" escape hatch).

## Page-level coverage is explicit, never inferred

`mark_extraction_page_reviewed()` is the only thing that advances
`pages_reviewed`. Opening a page in the UI, viewing its normalized text,
or scrolling past it in the PDF panel does **not** count as review — a
reviewer must explicitly record a page-level outcome
(`reviewed_clear` / `reviewed_with_findings` / `ocr_candidate` /
`reprocessing_candidate`). `all_pages_reviewed` is recomputed from a live
count on every call, not trusted as a cached flag, and
`submit_document_extraction_review()` re-verifies it again under lock
before accepting any final decision — **100% of pages must be reviewed
before any of the five terminal decisions**, including `rejected` (a
reviewer who spots the wrong document on page 1 still marks every page,
even trivially, before rejecting — see ADR 0011's "Consequences" section
for why this uniform rule was chosen over a decision-dependent
exception).

## The five terminal decisions

See `docs/domain/extraction-quality-findings.md` for the exact,
database-enforced rule set behind each of `accepted`,
`accepted_with_warnings`, `ocr_required`, `reprocessing_required`, and
`rejected`. All five are recorded exclusively through
`submit_document_extraction_review()` — a single, narrow, transactional
function that re-validates every rule under lock, regardless of what the
client believes the state to be.

## Downstream eligibility is derived, never stored as an editable flag

`get_document_extraction_review_eligibility(extraction_run_id)` computes
`eligible_for_ocr` / `eligible_for_chunking` / `eligible_for_retrieval`
fresh, every call, from the **latest** review round's status plus the
extraction run's own execution status:

| Latest review status | OCR eligible | Chunking eligible | Retrieval eligible |
|---|---|---|---|
| (no review yet) | false | false | false |
| `pending_review` / `in_review` | false | false | false |
| `accepted` | false | **true** | false |
| `accepted_with_warnings` | false | **true** | false |
| `ocr_required` | **true** | false | false |
| `reprocessing_required` | false | false | false |
| `rejected` | false | false | false |
| `invalidated` | false | false | false |
| (extraction run not `succeeded`) | false | false | false |

Retrieval eligibility is hard-coded `false` in this sprint — no chunking,
embedding, or retrieval work exists yet (S1-D3/S1-E).

Reopening an accepted round immediately flips chunking eligibility back
to `false` (the latest round is now the fresh `pending_review` one) with
no separate bookkeeping required — there is no `eligible_for_chunking`
column anywhere a client could write to directly.

## Invalidation

`invalidate_extraction_review()` is the one legal terminal-to-terminal
transition: an `accepted` or `accepted_with_warnings` round can be
administratively invalidated (e.g. a pipeline defect is discovered after
the fact) without needing a whole new review round. The original decision
text (`submitted_by`, `submitted_at`, `overall_comments`,
`warning_summary`) is preserved untouched — only `review_status` and
`decision_reason` change, and only once. See
`docs/operations/extraction-review-reopening-and-invalidation.md` for the
operational account.

## What this sprint deliberately does not do

OCR execution, chunk generation, embeddings, retrieval, manual correction
of extracted text, or any mutation of `document_extraction_runs` /
`document_extraction_pages` (both remain exactly as immutable as Sprint
1.2B left them — this migration only ever reads them). See
`KNOWN_LIMITATIONS.md`.
