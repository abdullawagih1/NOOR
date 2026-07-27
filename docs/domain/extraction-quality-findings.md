# Extraction Quality Findings and Decision Rules (Sprint 1-D1)

Companion docs: ADR 0011, `docs/domain/extraction-review-lifecycle.md`,
`docs/database/extraction-review-schema.md`.

## One generalized findings table

`document_extraction_review_findings` holds both page-level
(`extraction_page_id` set) and document-level (`extraction_page_id` and
`page_number` both null) findings. A `check` constraint enforces the two
never mix (`(extraction_page_id is null) = (page_number is null)`), so
the taxonomy itself keeps the two kinds unambiguous without needing two
tables (mission §10.3 explicitly preferred this if it stayed clear —
this is the constraint that keeps it clear).

## Finding taxonomy

Exactly 23 controlled `finding_type` values (database `check` constraint,
never an arbitrary string):

| Type | Typical scope |
|---|---|
| `missing_text` | page or document |
| `partial_text` | page |
| `incorrect_reading_order` | page or document |
| `multi_column_order_issue` | page |
| `garbled_characters` | page |
| `unicode_normalization_issue` | page |
| `arabic_shaping_issue` | page |
| `arabic_direction_issue` | page |
| `mixed_language_direction_issue` | page |
| `rotation_issue` | page |
| `unexpected_blank_page` | page |
| `image_only_page` | page |
| `suspected_scanned_page` | page |
| `table_structure_loss` | page |
| `figure_caption_loss` | page |
| `footnote_loss` | page |
| `header_footer_noise` | page or document |
| `duplicate_text` | page or document |
| `missing_page` | document |
| `page_number_mismatch` | document |
| `metadata_mismatch` | document |
| `source_integrity_concern` | document |
| `other` | either — **requires a description** (enforced by a `check` constraint, not just UI validation) |

## Severity and status

Severity: `informational` / `minor` / `major` / `critical` (database
`check` constraint). Status: `open` / `acknowledged` / `resolved` /
`accepted_risk` / `dismissed`. Dismissing or accepting the risk of a
**major or critical** finding requires a non-empty `resolution_note` —
enforced twice: once by a `check` constraint on the table itself (so no
write path, present or future, can bypass it), and again with a friendlier
error inside `update_extraction_finding_status()`.

## Immutability

A finding's core content (`finding_type`, `severity`, `title`,
`description`, `suggested_action`, `extraction_page_id`, `page_number`,
`created_by`, `created_at`) is immutable from the moment it is inserted —
a trigger blocks any change to those columns. Only `status`,
`resolved_by`, `resolved_at`, and `resolution_note` may ever change, and
only through `update_extraction_finding_status()`. A correction to a
finding's substance is a **new** finding (optionally linking
`supersedes_finding_id`), never an edit of the old one. Findings cannot be
deleted through any normal path (a trigger blocks `DELETE`) — resolve,
dismiss, or accept the risk instead. The one exception is the same
documented `noor.allow_audit_maintenance` override GUC used for
`audit_events`/`guideline_reviews`/`document_extraction_review_events` —
without it, this was found to make synthetic hosted test data completely
unremovable even for cleanup purposes, a real gap fixed the same session
it was found (see
`docs/verification/sprint-1-d1-extraction-review-verification.md`).

## Decision rules (enforced inside `submit_document_extraction_review()`, under lock)

All five decisions additionally require `all_pages_reviewed = true` (every
page explicitly marked, not merely opened) before any of them can be
submitted.

**`accepted`** — zero open `critical` findings, zero open `major`
findings. (Open `minor`/`informational` findings are fine; that's exactly
what distinguishes it from `accepted_with_warnings`.)

**`accepted_with_warnings`** — zero open `critical` findings; a
non-empty `warning_summary` is required. Open `major`/`minor`/
`informational` findings are allowed — the warning summary is where the
reviewer records what remains outstanding and why it's still usable.

**`ocr_required`** — at least one finding exists with
`finding_type in (missing_text, partial_text, image_only_page,
suspected_scanned_page, unexpected_blank_page)`; a non-empty
`decision_reason` is required. Sets `requires_ocr = true` on the review
row. Does **not** start OCR — that's Sprint 1-D2.

**`reprocessing_required`** — at least one finding exists (any type); a
non-empty `decision_reason` is required. Sets
`requires_reprocessing = true`. Does **not** trigger a new extraction
attempt automatically — a future task creates the new pipeline
configuration and extraction run.

**`rejected`** — a non-empty `decision_reason` is required; at least one
`major` or `critical` finding must exist (in any status — even resolved,
since the point is that a serious problem was identified at all, not that
it remains unresolved). Used when the document itself is wrong for this
guideline version, not merely technically imperfect.

## What reviewers can never do

Reviewers record findings and decisions. They cannot, through any
function in this migration, mutate `normalized_text`, `raw_text`, page
checksums, the artifact JSON, its checksum, extractor metadata, source
checksums, or any technical extraction metric. The deterministic
extraction artifact from Sprint 1.2B remains exactly as immutable as it
was before this sprint. A future "human-corrected text" workflow
(explicitly out of scope) would need its own, separately-provenanced
artifact table — never a mutation of this one.
