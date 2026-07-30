# Canonical Page-Text Representations (Sprint 1-D2)

Noor never merges text representations. For any given page, up to three
independent representations can exist:

```text
native_pdf_extraction   (document_extraction_pages.normalized_text)
ocr_extraction          (document_ocr_runs.normalized_text)
future_human_corrected_text   (not implemented this sprint)
```

`document_extraction_pages` and its checksums remain exactly as immutable
as Sprint 1.2B (S1-C2) left them — this sprint never executes anything
resembling `update document_extraction_pages set normalized_text = ...`.
OCR output is a new row in a wholly separate table, with its own
provenance chain (render identity, provider identity, model identity).

## `get_document_page_text_readiness(extraction_run_id)`

This function is the *only* place that decides, per page, which
representation is canonical for downstream use. It never mutates
anything — it is a read-only derivation, recomputed on every call from
current state, so a reopened review or an invalidated run is reflected
immediately with no separate bookkeeping to keep in sync.

For each page it returns:

```text
out_page_number
out_representation_type   ('native' | 'ocr' | 'none')
out_representation_id
out_text_checksum
out_ready_for_chunking
out_reason
```

Selection rules:

- **Native**: the latest extraction review is `accepted` or
  `accepted_with_warnings`, and this page was never flagged
  `ocr_candidate` in that round, and the extraction run remains
  `succeeded`.
- **OCR**: the latest extraction review is `ocr_required`, this page *was*
  flagged `ocr_candidate`, its `document_ocr_runs` row is `succeeded`, and
  the latest `document_ocr_page_reviews` decision for that run is
  `accepted` or `accepted_with_warnings`.
- **Not ready** (`out_representation_type = 'none'`): anything else —
  OCR still pending, OCR failed, OCR review not yet done,
  `reprocessing_required`, `rejected`, the extraction review was
  reopened, or the extraction run was invalidated. `out_reason` names the
  specific blocking condition (e.g. `ocr_pending`, `ocr_rejected`,
  `ocr_not_yet_reviewed`) rather than a generic "not ready" — a future
  operations dashboard or reviewer queue can surface the precise cause
  without re-deriving it.

There is no manually-editable "canonical representation" column anywhere
in the schema — this function is recomputed, not cached, so it can never
drift from the underlying request/review state.

## Downstream eligibility

`get_document_extraction_review_eligibility()` (originally Sprint 1-D1,
extended this sprint) derives `out_eligible_for_chunking` as follows:

```text
review = accepted | accepted_with_warnings
  -> eligible using native representations for every page

review = ocr_required
  -> eligible only if get_document_page_text_readiness() reports
     out_ready_for_chunking = true for every page in the run
  -> any single not-ready page makes the whole run ineligible

review = reprocessing_required | rejected | pending_review | in_review
  -> ineligible

extraction run invalidated, or review reopened
  -> ineligible immediately (no separate invalidation step needed —
     eligibility is always derived from current state)
```

`out_eligible_for_retrieval` remains hard-coded `false` throughout this
sprint, exactly as Sprint 1-D1 left it — retrieval eligibility is S1-E
scope, not something this sprint's OCR work unlocks.

## What downstream (S1-D3 chunking) can assume

A future chunking pipeline can call `get_document_page_text_readiness()`
for a run whose `out_eligible_for_chunking` is `true` and trust that
*every* page has exactly one accepted representation with a stable text
checksum — it never needs to know whether a given page's text came from
native extraction or OCR, and it must never itself pick between the two
representations.
