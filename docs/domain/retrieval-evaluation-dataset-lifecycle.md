# Retrieval Evaluation Dataset Lifecycle

Sprint 1-E1. See ADR 0015 for the full architectural rationale.

## What a "dataset" is here

A `retrieval_evaluation_datasets` row is a versioned, named bundle of
three things, always evaluated together:

1. A frozen **corpus** — a curated set of `retrieval_evaluation_corpus_items`,
   each pointing at one already-accepted, `eligible_for_embedding=true`
   `document_chunks` row (Sprint 1-D3), with exact provenance preserved
   (chunking run, chunking review, guideline/version, chunk checksum,
   page number, representation type).
2. A versioned **query set** — `retrieval_evaluation_queries`, each tagged
   with a language, a controlled 17-category taxonomy value, and a
   difficulty (see `relevance-judgments-and-query-taxonomy.md`).
3. Graded **relevance judgments** — `retrieval_relevance_judgments`,
   0-3, linking queries to corpus items.

This is a synthetic, internal evaluation artifact. It is never real
patient data, never a production search index, and never claims to
represent guideline content quality — only whether Noor's retrieval
layer can find the right chunk for a known query against a known
corpus.

## Lifecycle states

`retrieval_evaluation_datasets.status`: `draft` → `ready_for_review` →
`frozen` → `archived`, with one controlled return path:
`ready_for_review` → `draft` (`return_evaluation_dataset_to_draft`,
requires a reason). **A frozen dataset never returns to draft** — a
correction after freezing requires a new dataset version
(`logical_name` + incremented `version`, see
`evaluation-dataset-versioning.md`), never a mutation of frozen content.
`frozen` → `archived` is the only legal transition out of `frozen`
(`archive_retrieval_evaluation_dataset`).

- **`draft`**: corpus items, queries, and judgments can be added, edited,
  or removed (`add_evaluation_corpus_item`, `create_evaluation_query`,
  `update_evaluation_query`, `create_relevance_judgment`,
  `update_relevance_judgment`, `remove_evaluation_corpus_item`).
- **`ready_for_review`**: content is frozen from further editing intent
  but not yet checksummed — this state exists purely to gate the
  two-person review step below. `submit_evaluation_dataset_for_review`
  requires at least one corpus item and at least one active query.
- **`frozen`**: the corpus, query, and judgment manifests are
  checksummed (`corpus_manifest_sha256`, `query_manifest_sha256`,
  `judgment_manifest_sha256`, and a combined `dataset_sha256`), and a
  denormalized `retrieval_evaluation_search_documents` row is created
  for every corpus item (see `retrieval-evaluation-schema.md`). No
  further mutation of corpus items, queries, or judgments is possible —
  enforced by triggers, not just application logic.
- **`archived`**: retained for history; no further evaluation runs may
  target it as their identity's dataset (a run's identity is checked
  against `dataset_sha256` at `frozen` time, so archiving does not
  invalidate past results — see below).

## Freeze before measuring

**No official evaluation run may execute against a dataset that is not
`frozen`.** `create_retrieval_evaluation_run` (migration 0015) checks
`v_dataset.status <> 'frozen'` and raises before any job is created.
This is the sprint's central invariant: numbers are only ever reported
against an immutable, checksum-verified input.

## Two-person review, mirroring existing technical-review gates

`freeze_retrieval_evaluation_dataset` requires `reviewed_by is not null
and reviewed_by <> created_by` — a dataset's own creator cannot review
it for freezing. `mark_evaluation_dataset_reviewed` (a distinct
function from freeze itself) records that confirmation. This mirrors
the self-review blocks already established for extraction, OCR, and
chunking technical review (a reviewer cannot be the same person who
introduced the content being reviewed) — applied here to dataset
authorship vs. freeze-readiness review.

## Freeze validation (all enforced inside `freeze_retrieval_evaluation_dataset`)

1. Every corpus item's source chunk is **re-checked live** against
   `get_document_embedding_readiness()` — a chunk that was
   embedding-ready when added may have since been invalidated (e.g. its
   chunking review was reopened). Freezing fails loudly rather than
   silently freezing a corpus item whose provenance chunk is no longer
   trustworthy.
2. **Judgment coverage**: every active, non-negative-control query must
   have at least one judgment with `relevance_grade >= 2` — freezing
   fails with a combined error listing every violating `query_key` if
   not.
3. **Negative-control consistency**: no query with
   `category = 'negative_control'` may have any judgment with
   `relevance_grade >= 2` — a negative control is defined by having no
   truly relevant item in the corpus.
4. Manifests are computed as
   `jsonb_agg(jsonb_build_object(...) order by display_order, id)` over
   corpus items, queries, and judgments, then hashed with
   `pgcrypto`'s `digest()`. This is genuinely deterministic: PostgreSQL's
   `jsonb` type canonicalizes object key order on storage, and
   `jsonb_agg(... order by ...)` fixes array order explicitly — so
   identical content always produces an identical checksum, regardless
   of insertion order.

## Idempotent freeze

Calling `freeze_retrieval_evaluation_dataset` again on an already-frozen
dataset (the same `p_idempotency_key`, or simply a repeat call) returns
the same row without re-computing anything — freezing is a replay-safe
operation, not a one-shot action that fails on retry.

## What this sprint explicitly does not do

No embeddings, no vector columns, no pgvector, no external AI calls, no
production search exposure, no automated or LLM-generated relevance
judgments, no real guideline ingestion into a dataset (only synthetic,
clearly-labeled fixture content), and no regulatory or clinical
validation claim of any kind. See ADR 0015 for the full boundary list.
