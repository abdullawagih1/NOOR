# Retrieval Metrics

Sprint 1-E1. See ADR 0015 and `apps/worker/app/retrieval/metrics.py` (the
single source of truth — this document explains it, it does not replace
reading the code for exact behavior).

## `metric_definition_version = "1"`

Every metric below is versioned as a unit — `metric_definition_version`
on `retrieval_evaluation_runs` pins the exact formulas in force for that
run. Changing any formula (even a rounding convention) is a version
bump, never a silent redefinition of an existing version's meaning.

Computed at K ∈ {1, 3, 5, 10} (`retrieval_evaluation_metrics.metric_name`
CHECK-constrains the full set: `precision_at_1/3/5/10`,
`recall_at_1/3/5/10`, `hit_rate_at_1/3/5/10`, `mrr`, `ndcg_at_1/3/5/10`
— 17 values total):

- **Precision@K** — of the top-K ranked results, the fraction that are a
  "hit" (`relevance_grade >= relevance_threshold`, default 2). Divides
  by `min(K, number of results actually returned)`, not a fixed `K` —
  a documented convention difference from a strict "always divide by K"
  definition, chosen so a query result set smaller than K is not
  unfairly penalized.
- **Recall@K** — of every judged-relevant item for that query anywhere
  in the frozen dataset (not just what was retrieved), the fraction
  found within the top K.
- **Hit Rate@K** — 1.0 if any hit appears in the top K, else 0.0.
- **MRR** (Mean Reciprocal Rank) — `1 / rank` of the first hit in the
  full ranked list (not capped at any K), averaged across queries; 0 if
  a query has no hit at all.
- **nDCG@K** — graded relevance discounted by rank:
  `DCG@K = Σ (2^grade - 1) / log2(rank + 1)` for the top K, divided by
  the same formula computed over the *ideal* ordering (every judged
  grade for that query, sorted descending) — so a perfect ranking
  always scores exactly 1.0, and an empty judgment set scores 0.0
  rather than dividing by zero.

## Scoping: overall, by-language, by-category, by-difficulty

Every metric is computed at four `scope_type` values:
`overall`, `language` (`scope_value` = `en`/`ar`/`mixed`), `category`
(one of the 17 query categories), and `difficulty`
(`basic`/`moderate`/`challenging`). This lets a reviewer see, for
example, whether Arabic exact-phrase queries perform worse than English
ones without that difference being averaged away in a single overall
number.

## Negative controls are never included in any metric row

See `relevance-judgments-and-query-taxonomy.md` — negative-control
queries are excluded from every `overall`/`language`/`category`/
`difficulty` metric computation (`compute_all_metrics` filters them out
before any aggregate is built). Their own behavior is measured
separately, as a failure-detection concern, not a metrics concern —
see `retrieval-failure-analysis.md`.

## No model claims

This sprint's ranking formula
(`final_score = w_full_text * full_text_rank + w_coverage *
token_coverage + exact_phrase_bonus`, `apps/worker/app/retrieval/config.py`)
is a deterministic PostgreSQL full-text-search baseline
(`noor-lexical-baseline-v1`), never described as a "relevance
probability," never claimed to predict how a future embedding, hybrid,
or reranking approach will perform. Its entire purpose is to give every
future retrieval strategy a fixed, reproducible yardstick — the same
frozen datasets, the same metric formulas — to be measured against.

## Determinism, end to end

Every input to every metric is either an immutable frozen-dataset row
(corpus item, query, judgment) or an immutable
`retrieval_evaluation_results` row (rank, score, grade — computed once
per run and never mutated). Re-running the exact same frozen dataset
against the exact same retriever/configuration/metric-definition/
top-K/runner-version identity reuses the existing succeeded run rather
than recomputing (`create_retrieval_evaluation_run`'s identity-based
reuse) — and if it did recompute, it would produce byte-identical
results, proven by `apps/worker/tests/test_retrieval_pipeline.py`'s
determinism test.

## What this sprint explicitly does not do

No embedding-based metrics (no cosine-similarity thresholds, no vector
recall), no reranking-stage metrics, no claim that these numbers
predict real clinical-query performance, and no automated model
selection based on these numbers — that decision remains a deliberate,
documented, human sprint-planning choice for a future sprint.
