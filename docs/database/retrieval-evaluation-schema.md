# Retrieval Evaluation Database Schema

Sprint 1-E1, migrations 0014 (dataset lifecycle + lexical corpus/query
foundation) and 0015 (lexical baseline execution + runs). See ADR 0015.

## Tables (migration 0014)

- **`retrieval_evaluation_datasets`** — one versioned dataset
  (`unique(organization_id, logical_name, version)`). `status` freezes
  through `draft` → `ready_for_review` → `frozen` → `archived`; 4
  manifest-checksum columns (`corpus_manifest_sha256`,
  `query_manifest_sha256`, `judgment_manifest_sha256`,
  `dataset_sha256`) are `null` until freeze time.
  `prevent_terminal_dataset_mutation` allows only `frozen` → `archived`
  (no other field changed) plus no-op frozen updates that don't touch
  the checksum columns.
- **`retrieval_evaluation_corpus_items`** — one row per chunk included
  in a dataset's corpus, full provenance preserved (`chunk_id`,
  `chunking_run_id`, `chunking_review_id`, `guideline_id`,
  `guideline_version_id`, `source_document_id`, `chunk_index`,
  `chunk_checksum`, `page_number`, `representation_type`,
  `contains_native_text`/`contains_ocr_text`/`warning_state`,
  `embedding_ready_at_snapshot`, `display_order`). `corpus_item_sha256`
  is only computed at freeze time. Mutation blocked once the parent
  dataset is no longer `draft` (`prevent_corpus_item_mutation_after_freeze`,
  checked against the *live* parent status, not a cached value).
- **`retrieval_evaluation_queries`** — one query per
  `(dataset_id, query_key)`. `category` CHECK-constrained to the 17-value
  taxonomy; `language` to `en`/`ar`/`mixed`; `difficulty` to
  `basic`/`moderate`/`challenging`; a paired CHECK ties
  `is_negative_control` to `category = 'negative_control'`.
  `normalized_query_text` is computed once, at creation/update time, by
  `normalize_retrieval_text()` — never recomputed by the Worker.
- **`retrieval_relevance_judgments`** — `unique(dataset_id, query_id,
  corpus_item_id)`, `relevance_grade` CHECK in `(0,1,2,3)`,
  `review_status` `pending_review`/`confirmed`.
- **`retrieval_evaluation_search_documents`** — the denormalized
  full-text-search representation, created **only** by
  `freeze_retrieval_evaluation_dataset`, never by any other path. Stores
  `normalized_search_text` (from `normalize_retrieval_text()` over the
  chunk's canonical text), a GIN-indexed `search_vector`
  (`to_tsvector('simple', ...)`), `token_count`, and
  `normalization_version`. Fully immutable — every column change raises
  unconditionally.

## `normalize_retrieval_text(p_text text) returns text`

The single implementation of `retrieval_text_normalization_v1` (ADR
0015): NFC normalize → lowercase (Latin case-fold) → strip Arabic
diacritics/tatweel (`[ًٌٍَُِّْٰـ]`) → map Arabic-Indic digits to ASCII
→ replace punctuation with whitespace → collapse/trim whitespace.
Called by `create_evaluation_query`/`update_evaluation_query` (query
side) and by the freeze function (document side) — never duplicated in
Python. Example (verified live):
`normalize_retrieval_text('اَلسَّلَامُ عَلَيْكُمْ ١٢٣')` →
`'السلام عليكم 123'`.

## Tables (migration 0015)

- **`document_processing_jobs`** extended: `source_document_id` is now
  nullable, a new nullable `dataset_id` column added, a CHECK constraint
  enforces exactly one of the two is set per `job_type`
  (`document_parsing`/`document_ocr`/`document_chunking` require
  `source_document_id`; `retrieval_evaluation` requires `dataset_id`). A
  new partial unique index guarantees at most one active
  `retrieval_evaluation` job per dataset.
  `claim_next_document_processing_job` is re-declared (same signature,
  same behavior for every prior job type) with one added eligibility
  branch: a dataset-scoped job is claimable when its dataset is
  `frozen`, exactly parallel to a document-scoped job's existing
  `guideline_source_documents.status = 'registered'` check. This was a
  real gap caught by the local RLS suite (`013_retrieval_evaluation.sql`
  TEST 7) before any hosted verification — without it, every
  `retrieval_evaluation` job would sit `queued` forever, unclaimable.
- **`retrieval_evaluation_runs`** — one durable execution attempt at one
  deterministic identity: `organization_id + dataset_sha256 +
  retriever_name/version + retrieval_configuration_version +
  query_normalization_version + metric_definition_version +
  top_k_values + evaluation_runner_version`, hashed into
  `run_identity_sha256`. A partial unique index guarantees at most one
  `succeeded` row per identity. `status`:
  `running`/`succeeded`/`failed`/`invalidated`/`cancelled`/`reused`,
  with only `succeeded`/`cancelled` → `invalidated` as a legal terminal
  transition.
- **`retrieval_evaluation_results`** — one immutable ranked result per
  `(evaluation_run_id, query_id, rank)` (and per
  `(evaluation_run_id, query_id, corpus_item_id)`), with
  `final_score`/`score_components`/`matched_terms`/`relevance_grade`/
  `reciprocal_rank_contribution`/`dcg_contribution`/`is_hit`/
  `result_checksum`.
- **`retrieval_evaluation_metrics`** — one row per
  `(evaluation_run_id, scope_type, scope_value, metric_name)`,
  null-safe unique index via `coalesce(scope_value, '')`. Fully
  immutable.
- **`retrieval_evaluation_failures`** — `failure_category` (17-value
  CHECK), `source` (`system`/`human`), `status`
  (`open`/`acknowledged`/`resolved`). Core content immutable; only
  `status`/`reviewer_note`/`recommended_experiment` may change
  (`prevent_failure_content_mutation`).

## Storage: reuses `guideline-processed`, not `evaluation-assets`

The existing "processed artifact" Storage-policy extension (originally
migration 0010, extended by 0011/0012) is extended once more to accept
`retrieval_evaluation.read_artifacts` — no new bucket. `evaluation-assets`
(provisioned in migration 0003) remains unclaimed by any feature to
date; ADR 0015 documents this as a deliberate reuse decision, not a
missed opportunity.

## Key functions

**Client-facing** (granted to `authenticated`, permission-gated via
`assert_permission`):

- `create_retrieval_evaluation_dataset`, `update_retrieval_evaluation_dataset`,
  `submit_evaluation_dataset_for_review`, `return_evaluation_dataset_to_draft`,
  `mark_evaluation_dataset_reviewed`, `freeze_retrieval_evaluation_dataset`,
  `archive_retrieval_evaluation_dataset`.
- `add_evaluation_corpus_item`, `remove_evaluation_corpus_item`.
- `create_evaluation_query`, `update_evaluation_query`.
- `create_relevance_judgment`, `update_relevance_judgment`.
- `create_retrieval_evaluation_run` — computes the full run identity
  itself (every component is already known server-side — unlike
  chunking's identity, no Worker-computed manifest is involved), checks
  for a reusable `succeeded` run or an already-active job, and otherwise
  creates both the `document_processing_jobs` row and the
  `retrieval_evaluation_runs` row directly (`status = 'running'`
  immediately) — a deliberate simplification from the chunking
  precedent (which needs a separate Worker-only "create run" step
  because its identity depends on Worker-computed values).
- `cancel_evaluation_run`.
- `create_failure_annotation`, `update_failure_annotation`.

**Worker-only** (lease-token authenticated via `assert_lease_owner`,
never permission-gated, explicitly revoked from `authenticated`/`anon`):

- `get_retrieval_evaluation_job_context` — returns the run's pinned
  identity/config fields joined with every active query for the
  dataset.
- `get_retrieval_candidates` — the actual PostgreSQL full-text-search
  query (`ts_rank_cd`/`websearch_to_tsquery('simple', ...)` against
  `retrieval_evaluation_search_documents`), returning raw candidate rows
  only — no scoring, no ranking, no tie-breaking (all pure Python, see
  `retrieval-evaluation-worker-runbook.md`).
- `finalize_retrieval_evaluation_run` — atomic: inserts every ranked
  result, every metric row, and every system-derived failure from
  Worker-computed JSON, then marks the run succeeded and completes the
  underlying job.
- `fail_retrieval_evaluation_run`.

## What this sprint explicitly does not do

No embedding columns, no `pgvector` extension, no vector index, no
hybrid-retrieval scoring in SQL, no reranking tables, and no schema
support for automated/LLM-generated relevance judgments.
