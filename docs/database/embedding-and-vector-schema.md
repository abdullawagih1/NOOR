# Embedding and Vector Database Schema

Sprint 1-E2, migrations 0016 (pgvector foundation, chunk/query embeddings)
and 0017 (exact/indexed vector search, vector evaluation runs). See ADR 0016.

## Extension: `vector` (migration 0016)

`create schema if not exists extensions; create extension if not exists
vector with schema extensions;` — explicit schema placement, not a bare
`create extension if not exists vector`. A fresh local Postgres has no
`extensions` schema by default (would install into `public`), while
hosted Supabase pre-creates one for exactly this purpose — a real,
confirmed divergence (this migration failed on a fresh
`pgvector/pgvector:pg16` container with `schema "extensions" does not
exist` before this fix). Forcing both environments into the same schema
eliminates the divergence rather than papering over it with
`search_path` guessing. Local test/CI containers use
`pgvector/pgvector:pg16` (a drop-in `postgres:16` build with the
extension pre-compiled) — plain `postgres:16` has no `vector` type at
all.

## Tables (migration 0016)

- **`embedding_configurations`** — NOT organization-scoped (one shared,
  server-managed record). `approval_status` CHECK
  `draft`/`approved`/`retired`/`blocked`; a partial unique index on a
  constant expression (`embedding_configurations_one_approved_idx`)
  guarantees at most one `approved` row platform-wide. Seeded with
  exactly one row: `noor-multilingual-e5-base-v1`. No client-facing
  create/update function exists.
- **`document_embedding_runs`** — one execution attempt at identity
  `(organization, source_document, chunking_run, embedding
  configuration, chunk_manifest_sha256)`. Partial unique index
  (`document_embedding_runs_one_succeeded_per_identity`) enforces at
  most one `succeeded`/`succeeded_with_reuse` row per identity.
  `prevent_terminal_embedding_run_mutation` allows only `succeeded`/
  `succeeded_with_reuse`/`reused` → `invalidated` (no other field
  changed) plus idempotent no-op replays.
- **`document_chunk_embeddings`** — `vector_value vector(768)`, a
  **fixed-dimension column**, not a generic vector column with runtime
  checks — this strongly enforces the single approved configuration at
  the schema level (a row simply cannot exist with the wrong
  dimension). `unique(embedding_run_id, chunk_id)`; a partial unique
  index (`document_chunk_embeddings_one_succeeded_per_identity`) on
  `embedding_identity_sha256` enforces one succeeded vector per
  identity ever. An HNSW index
  (`document_chunk_embeddings_vector_hnsw_idx`, `vector_cosine_ops`,
  `where status = 'succeeded'`) is created unconditionally — HNSW needs
  no corpus-size-dependent tuning, unlike IVFFlat's list count.
  `prevent_document_chunk_embedding_mutation` blocks any change to a
  `succeeded` row except a transition to `invalidated` (vector/checksum/
  configuration must stay identical).
- **`retrieval_evaluation_query_embeddings`** — same shape one layer
  over, scoped to `(evaluation_dataset_id, query_id,
  embedding_configuration_id)` (`unique` constraint) rather than a
  chunk. Foreign keys require the dataset and query to already exist
  (migration 0014 tables) — a query embedding can never reference a
  query outside its own dataset.

## `document_processing_jobs` extension

`job_type` widened to include `document_embedding` (document-scoped,
like `document_chunking` — `source_document_id` set, `dataset_id` null)
and, in migration 0017, `query_embedding_generation` (dataset-scoped —
`dataset_id` set, `source_document_id` null, reusing the same nullable
column migration 0015 added for `retrieval_evaluation`).
`document_processing_jobs_subject_check` is re-declared (not edited in
place — the same pattern migration 0015 used over 0007) to route each
job_type to the correct branch. Partial unique indexes enforce at most
one active job per document (`document_embedding`) and per dataset
(`query_embedding_generation`).

### A real bug this surfaced: `claim_next_document_processing_job` needed no changes here — but its own migration-0015 extension did

Migration 0015 already re-declared `claim_next_document_processing_job`
to add a dataset-scoped eligibility branch (frozen dataset check)
alongside the original document-scoped branch (registered document
check). `document_embedding` jobs are document-scoped, so they already
satisfy the existing document-scoped branch unchanged — no further
claim-function change was needed this sprint. What *was* missing until
caught by the local RLS suite: migration 0016's own first draft forgot
to extend `document_processing_jobs_subject_check` for
`document_embedding` at all (it would have rejected every embedding job
insert with a CHECK violation) — fixed before merge, and is exactly the
kind of gap the "verify against a fresh container immediately" habit
this project follows is meant to catch early.

## Vector search functions (migration 0017)

`get_vector_search_candidates(p_search_mode)` — one function, not two,
toggled by `'exact'` (forces `enable_indexscan`/`enable_bitmapscan` off
for that statement) or `'indexed'` (sets `hnsw.ef_search = 100`, lets
the planner use the index) — both share identical
tenant/dataset-boundary logic and tie-break, so there is only one place
that logic can drift.

## `retrieval_evaluation_runs`/`_metrics`/`_failures` extensions

`retrieval_evaluation_runs` gains two nullable columns:
`embedding_configuration_id`, `vector_index_configuration_version` (both
null for a lexical run). `retrieval_evaluation_metrics.scope_type` CHECK
widened to add `exact_vs_indexed`; `metric_name` CHECK widened with 12
new vector/coverage/latency metric names. `retrieval_evaluation_failures.failure_category`
CHECK widened with 19 new vector-specific categories. None of
`retrieval_evaluation_results`, `finalize_retrieval_evaluation_run`,
`fail_retrieval_evaluation_run`, `cancel_evaluation_run`, or
`get_retrieval_evaluation_job_context` needed any change — all were
already fully retriever-agnostic.

## `query_sha256` was never actually populated — a real gap found, not edited around

`retrieval_evaluation_queries.query_sha256` (migration 0014) has no
consumer until this sprint, and `freeze_retrieval_evaluation_dataset`
never actually computes it — discovered when
`record_query_embedding`'s first draft tried to read it and hit a
NOT NULL violation on a genuinely null column. Rather than editing the
already-shipped 0014 migration, `get_query_embedding_job_context` and
`record_query_embedding` (migration 0017) both compute the query
checksum fresh from canonical `query_text` at read time
(`encode(digest(convert_to(query_text, 'utf8'), 'sha256'), 'hex')`) —
consistent with this codebase's "checksums come from canonical content,
never a possibly-stale stored value" discipline anyway.

## Storage bucket: `guideline-processed`, again

No new bucket — embedding and evaluation artifacts reuse the same
private "processed artifact" bucket (extraction/OCR/chunking/lexical
evaluation), gated by the existing `document_embeddings.read_artifacts`
permission added to the same Storage policy migration 0010 originally
created and 0011/0012/0015 already extended.
