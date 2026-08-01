# Chunking Eligibility and Lifecycle

Sprint 1-D3. See ADR 0014 for the full architectural rationale.

## What "chunking" means here

Chunking turns the canonical, accepted per-page text of one document
(native extraction or accepted OCR — never both, and never client-chosen)
into ordered, provenance-preserving, immutable text chunks. It does
**not** produce embeddings, does not touch pgvector, does not perform
retrieval, and does not classify clinical document structure. A chunk
is a deterministic function of its input; nothing here is generative.

## Eligibility: one job per document

Unlike OCR (page-scoped — ADR 0012), chunking is **document-scoped**:
`document_processing_jobs.job_type = 'document_chunking'`, at most one
active job per document at a time (a partial unique index on
`(source_document_id, job_type)` for non-terminal statuses).

A document becomes chunking-eligible when:

1. `guideline_source_documents.status = 'registered'`.
2. The latest `document_extraction_runs` row for it is `succeeded`.
3. The latest `document_extraction_reviews` round for that run is
   `accepted`, `accepted_with_warnings`, or `ocr_required` **with every
   page ready** (native or an accepted OCR run — see
   `get_document_page_text_readiness()`, migration 0011).

`create_document_chunking_job` (client-facing, migration 0012) checks
all three at request time. The Worker re-checks live state again at run
creation (`create_document_chunking_run`), since eligibility can change
between a job being queued and a Worker claiming it (e.g. the extraction
review was reopened in the meantime).

## Execution vs. review — the same boundary, one layer deeper

Exactly like ADR 0011 (extraction) and ADR 0012 (OCR):

- A **succeeded `document_chunking_runs` row** only proves the
  deterministic pipeline ran, coverage was proven 100%, and duplication
  was proven 0%. It says nothing about whether the resulting chunk
  boundaries are actually good.
- A **`document_chunking_reviews` round** (migration 0013) is where a
  human technical reviewer checks every chunk and renders a decision:
  `accepted`, `accepted_with_warnings`, `rechunk_required`, or
  `rejected`.
- `eligible_for_embedding` (from `get_document_embedding_readiness()`)
  is `true` only once a review round lands on `accepted` or
  `accepted_with_warnings` — never merely because the run succeeded.
- `eligible_for_retrieval` is hard-coded `false` everywhere, exactly as
  it has been since ADR 0011. No retrieval pipeline exists yet.

## Lifecycle states

**`document_chunking_runs.status`**: `running` → `succeeded` | `failed`,
with `succeeded`/`reused` → `invalidated` as the one legal terminal
transition (cascaded automatically if the upstream extraction review is
reopened or invalidated — see below — or triggered directly via
`invalidate_document_chunking_run`).

**`document_chunking_reviews.review_status`**: `pending_review` →
`in_review` → one of `accepted` / `accepted_with_warnings` /
`rechunk_required` / `rejected`, with `reopen_chunking_review` opening a
new round (`review_round + 1`) from any submitted, non-invalidated
decision. The prior round's row is never mutated or deleted — reopening
is additive, matching every review lifecycle in this codebase.

## Cascades

Reopening or invalidating the **extraction review** a chunking run
depends on invalidates that chunking run if it is still `succeeded` or
`reused` (migration 0013, extending migration 0011's own
`reopen_extraction_review`, which already cascades to OCR requests —
this is the same cascade one layer further downstream, in the same
function). No historical row is ever deleted; only non-terminal state
transitions to `invalidated`.

## Idempotent identity-based reuse

A chunking run's identity is the full tuple: `organization_id +
source_document_id + source_sha256 + input_manifest_sha256 +
pipeline_version + configuration_version + normalization_version +
tokenizer_name + tokenizer_version`. A partial unique index guarantees
at most one `succeeded` run per identity — a retry or a second chunking
job for the same already-succeeded identity reuses the existing run
rather than duplicating it (`out_reused = true`).

## What this sprint explicitly does not do

No embedding computation, no embedding-provider selection, no vector
storage, no full-text search, no retrieval, no reranking, no clinical
Q&A, no LLM calls, no semantic/generative chunking, no table
reconstruction, no clinical section classification, no chunk text
editing, no cross-document or cross-guideline chunks. See ADR 0014 for
the reasoning behind each boundary.
