# Relevance Judgments and Query Taxonomy

Sprint 1-E1. See ADR 0015 and `retrieval-evaluation-dataset-lifecycle.md`.

## Query taxonomy (17 categories, CHECK-constrained)

`retrieval_evaluation_queries.category` is one of exactly:

| Category | What it probes |
|---|---|
| `exact_phrase` | An exact substring match against chunk text |
| `keyword_lookup` | A handful of keywords, no exact phrase |
| `fact_location` | Finding a specific stated fact |
| `definition` | A definitional query ("what is X") |
| `procedure_step` | A specific step within a procedure |
| `numeric_lookup` | A query centered on a number/measurement |
| `abbreviation` | An abbreviation or acronym lookup |
| `heading_lookup` | A query matching a section heading |
| `cross_paragraph` | Relevance spans more than one paragraph |
| `arabic_exact` | Exact-phrase, Arabic-language content |
| `arabic_keyword` | Keyword lookup, Arabic-language content |
| `english_exact` | Exact-phrase, English-language content |
| `english_keyword` | Keyword lookup, English-language content |
| `mixed_language` | Query or target content mixes Arabic/English |
| `negative_control` | Deliberately has no relevant corpus item |
| `ambiguous` | Deliberately underspecified |
| `hard_lexical` | Relevant but shares little surface vocabulary |

`language` is one of `en` / `ar` / `mixed`; `difficulty` is one of
`basic` / `moderate` / `challenging`. A query with
`category = 'negative_control'` must have `is_negative_control = true`,
and vice versa — enforced by a paired CHECK constraint, not just
convention.

## Graded relevance judgments (0-3)

`retrieval_relevance_judgments.relevance_grade`:

| Grade | Meaning |
|---|---|
| 0 | Not relevant |
| 1 | Marginally relevant |
| 2 | Relevant |
| 3 | Highly relevant |

`relevance_threshold` (an evaluation run's own pinned config, default
`2`) is the grade at or above which an item counts as a "hit" for
Precision/Recall/Hit Rate/MRR — see `retrieval-metrics.md`. A grade
below the threshold is not "wrong," it simply does not count toward
those binary-hit metrics; nDCG still uses the full graded scale.

Judgments are authored by a human reviewer
(`retrieval_evaluation.edit_dataset`), never generated automatically or
by an LLM — this sprint's mission explicitly excludes automated
relevance judgments. `create_relevance_judgment` validates that the
query and corpus item belong to the same dataset before insertion.
`review_status` (`pending_review` / `confirmed`) lets a second person
confirm a judgment without re-grading it, if a project later wants that
extra step — not currently required by freeze validation, which only
checks the grade itself.

## Negative controls never distort a positive metric

A negative-control query is defined by having **no** relevant item in
its own dataset (freeze validation rejects any judgment with
`relevance_grade >= 2` on a negative-control query). Because standard
Precision/Recall/Hit-Rate/MRR/nDCG formulas assume at least one truly
relevant item exists, negative controls are excluded from every
`retrieval_evaluation_metrics` row (`compute_all_metrics`,
`apps/worker/app/retrieval/metrics.py`) — folding them in would
silently and meaninglessly drag every average toward zero. They are
evaluated by a dedicated system-sourced failure detector instead:
`negative_control_false_positive` fires if the lexical baseline
retrieves **any** candidate at all for a negative-control query — see
`retrieval-failure-analysis.md`.

## What this sprint explicitly does not do

No automated or LLM-generated relevance judgments, no real clinical
guideline content in judged queries (synthetic fixtures only, always
labeled), and no claim that this taxonomy is exhaustive of every real
clinical query pattern Noor will eventually need to support — it is a
deliberately controlled, reproducible test surface for comparing
retrieval strategies against each other, not a market-research query
log.
