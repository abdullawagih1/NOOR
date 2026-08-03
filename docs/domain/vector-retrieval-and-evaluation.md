# Vector Retrieval and Evaluation

Sprint 1-E2. See ADR 0016, `supabase/migrations/0017_vector_retrieval_evaluation.sql`,
and `apps/worker/app/retrieval/vector_pipeline.py`.

## Extends S1-E1's framework — never a parallel one

`noor-vector-baseline-v1` is the second implementation of the same
`Retriever` protocol S1-E1 established (`app/retrieval/retriever.py`).
Vector evaluation runs live in the exact same
`retrieval_evaluation_runs`/`_results`/`_metrics`/`_failures` tables as
lexical runs — distinguished only by `retriever_name`. Every
retrieval-quality metric (Precision@K, Recall@K, Hit Rate@K, MRR,
nDCG@K) is computed by the same, completely unmodified
`compute_all_metrics` function `retrieval-metrics.md` documents.
`finalize_retrieval_evaluation_run`, `fail_retrieval_evaluation_run`,
`cancel_evaluation_run`, and `get_retrieval_evaluation_job_context`
(all migration 0015) are reused byte-for-byte — this migration adds
zero new SQL for any of them.

## Two search paths, one correctness reference

Every vector-evaluation query runs through **both** paths
(`get_vector_search_candidates`, `p_search_mode` = `'exact'` or
`'indexed'`):

- **Exact** — `SET LOCAL enable_indexscan = off; SET LOCAL
  enable_bitmapscan = off;` for that one statement, forcing a true
  sequential scan. No HNSW approximation is possible here by
  construction — this is the permanent correctness reference every
  indexed result is validated against, never trusted un-verified.
- **Indexed** — `SET LOCAL hnsw.ef_search = 100;`, letting the planner
  use the HNSW index (`vector_index_configuration_v1`:
  `vector_cosine_ops`, built in migration 0016).

Both paths share identical tenant/dataset-boundary logic and
deterministic tie-break (cosine distance ascending → corpus display
order ascending → chunk checksum ascending) — only the scan strategy
differs.

## Exact-vs-indexed correctness is never "did it execute"

For every query, `app/retrieval/vector_pipeline.py` computes
exact-vs-indexed Recall@{1,3,5,10} (what fraction of the exact top-K
neighbors the indexed path also returned) and rank agreement (whether
common candidates preserve their relative exact-path order) — stored as
`retrieval_evaluation_metrics` rows with `scope_type = 'exact_vs_indexed'`
and dedicated metric names (`exact_vs_indexed_recall_at_1`, ...,
`exact_vs_indexed_rank_agreement`). A query whose exact and indexed
top-1 disagree is flagged as an `exact_index_disagreement` failure. This
is deliberately a **separate** scope from retrieval-quality metrics
(mission's own "do not merge retrieval-quality and system-performance
metrics into one score") — an index can be perfectly correct while the
model itself still retrieves poorly, and vice versa; conflating the two
would hide either problem.

## The indexed path is the "official" ranked result

`retrieval_evaluation_results` for a vector run always stores the
**indexed** path's ranking — the exact path exists only to validate the
index, never as a second, competing set of official results. This
matches how a real deployment would eventually query (via the index),
so the retrieval-quality metrics measure what production would actually
see.

## Lexical-vs-vector comparison

For the same frozen dataset, comparing the successful lexical run
against the successful vector run requires an identical dataset
checksum, metric-definition version, and top-K values before any
per-metric delta (`vector_metric - lexical_metric`) is meaningful. Deltas
are reported overall and broken out by language, category, and
difficulty — never declared "vector wins" from a single overall average.
A regression in any one category is reported, never hidden.

## Vector-specific failure taxonomy

In addition to S1-E1's 17 lexical-failure categories, this sprint adds:
`semantic_false_positive`, `semantic_false_negative`,
`lexical_exact_match_lost`, `arabic_embedding_failure`,
`mixed_language_embedding_failure`, `numeric_semantics_failure`,
`abbreviation_embedding_failure`, `short_query_failure`,
`long_chunk_dilution`, `similar_chunk_confusion`,
`query_passage_mode_mismatch`, `model_input_limit`,
`vector_dimension_error`, `vector_norm_anomaly`,
`exact_index_disagreement` (system-detected, see above),
`index_recall_failure`, `dataset_embedding_gap`, `stale_embedding`,
`configuration_mismatch`. Only `exact_index_disagreement` is detected
mechanically this sprint (a purely rank-comparison rule); the remaining
categories require human judgment to distinguish (e.g., telling a
genuine semantic miss apart from a judgment gap needs a reviewer reading
the actual chunk text) and exist for `create_failure_annotation`'s
human-review path, exactly as S1-E1's own harder-to-detect categories
already do.

## Model acceptance is evidence-based, not a leaderboard win

A vector baseline is technically accepted for further (future,
out-of-scope) hybrid experimentation once: every expected chunk and
query has a valid embedding, tenant/dataset isolation holds, exact and
indexed paths have been compared, retrieval-quality metrics have been
computed and compared against lexical per language/category/difficulty,
and every regression is documented — never because it "won" on an
unweighted overall average.

## What this sprint explicitly does not do

No hybrid retrieval, no reciprocal-rank fusion, no reranking, no
cross-encoders, no LLM calls, no query rewriting/expansion, no
production clinician-facing vector search, and no claim that
cosine-similarity scores are a "relevance probability."
