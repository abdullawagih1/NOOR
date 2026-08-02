"""
Retrieval metrics (mission §38-§41, ADR 0015, metric_definition_version =
"1"): Precision@K, Recall@K, Hit Rate@K, MRR, and nDCG@K at K in
{1, 3, 5, 10}, computed in pure Python from already-ranked results and
relevance judgments — no network or database access.

Negative-control queries are never included in these aggregates (they have
no relevant judgments by construction — freeze validation forbids a
negative-control query from having any judgment with grade >= threshold —
so folding them into Precision/Recall/MRR would silently and meaninglessly
drag every average toward zero). They are evaluated separately by
`app/retrieval/failure_analysis.py` instead (a `negative_control_false_positive`
failure is raised if any candidate is retrieved for one at all). See
`docs/domain/retrieval-metrics.md` for the full rationale.

Precision@K here divides by `min(k, len(ranked_results))`, not a fixed `k`
— dividing by a fixed `k` would unfairly penalize a query result set
smaller than the corpus is expected to return (a known, documented
convention difference from a strict "always divide by k" definition).
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

K_VALUES: tuple[int, ...] = (1, 3, 5, 10)


@dataclass(frozen=True)
class QueryEvaluation:
    query_id: str
    query_key: str
    language: str
    category: str
    difficulty: str
    is_negative_control: bool
    ranked_corpus_item_ids: tuple[str, ...]
    relevance_by_corpus_item: dict = field(default_factory=dict)  # corpus_item_id -> int grade
    total_relevant_count: int = 0

    def grade_of(self, corpus_item_id: str) -> int:
        return self.relevance_by_corpus_item.get(corpus_item_id, 0)


def precision_at_k(qr: QueryEvaluation, k: int, threshold: int) -> float:
    top_k = qr.ranked_corpus_item_ids[:k]
    if not top_k:
        return 0.0
    hits = sum(1 for cid in top_k if qr.grade_of(cid) >= threshold)
    return hits / len(top_k)


def recall_at_k(qr: QueryEvaluation, k: int, threshold: int) -> float:
    if qr.total_relevant_count <= 0:
        return 0.0
    top_k = qr.ranked_corpus_item_ids[:k]
    hits = sum(1 for cid in top_k if qr.grade_of(cid) >= threshold)
    return hits / qr.total_relevant_count


def hit_rate_at_k(qr: QueryEvaluation, k: int, threshold: int) -> float:
    top_k = qr.ranked_corpus_item_ids[:k]
    return 1.0 if any(qr.grade_of(cid) >= threshold for cid in top_k) else 0.0


def reciprocal_rank(qr: QueryEvaluation, threshold: int) -> float:
    for i, cid in enumerate(qr.ranked_corpus_item_ids, start=1):
        if qr.grade_of(cid) >= threshold:
            return 1.0 / i
    return 0.0


def _dcg(grades: list[int], k: int) -> float:
    return sum((2**grade - 1) / math.log2(i + 1) for i, grade in enumerate(grades[:k], start=1))


def ndcg_at_k(qr: QueryEvaluation, k: int) -> float:
    actual_grades = [qr.grade_of(cid) for cid in qr.ranked_corpus_item_ids]
    ideal_grades = sorted(qr.relevance_by_corpus_item.values(), reverse=True)
    idcg = _dcg(ideal_grades, k)
    if idcg <= 0:
        return 0.0
    return _dcg(actual_grades, k) / idcg


@dataclass(frozen=True)
class MetricRow:
    scope_type: str  # 'overall' | 'language' | 'category' | 'difficulty'
    scope_value: str | None
    metric_name: str
    metric_value: float
    sample_size: int


def _compute_scope_metrics(scope_type: str, scope_value: str | None, queries: list[QueryEvaluation], threshold: int) -> list[MetricRow]:
    if not queries:
        return []
    rows: list[MetricRow] = []
    n = len(queries)
    for k in K_VALUES:
        rows.append(MetricRow(scope_type, scope_value, f"precision_at_{k}", sum(precision_at_k(q, k, threshold) for q in queries) / n, n))
        rows.append(MetricRow(scope_type, scope_value, f"recall_at_{k}", sum(recall_at_k(q, k, threshold) for q in queries) / n, n))
        rows.append(MetricRow(scope_type, scope_value, f"hit_rate_at_{k}", sum(hit_rate_at_k(q, k, threshold) for q in queries) / n, n))
        rows.append(MetricRow(scope_type, scope_value, f"ndcg_at_{k}", sum(ndcg_at_k(q, k) for q in queries) / n, n))
    rows.append(MetricRow(scope_type, scope_value, "mrr", sum(reciprocal_rank(q, threshold) for q in queries) / n, n))
    return rows


def compute_all_metrics(evaluations: list[QueryEvaluation], relevance_threshold: int) -> list[MetricRow]:
    """Overall + by-language + by-category + by-difficulty, all excluding
    negative-control queries."""
    scored = [q for q in evaluations if not q.is_negative_control]

    rows = _compute_scope_metrics("overall", None, scored, relevance_threshold)

    for scope_type, key_fn in (("language", lambda q: q.language), ("category", lambda q: q.category), ("difficulty", lambda q: q.difficulty)):
        values = sorted({key_fn(q) for q in scored})
        for value in values:
            group = [q for q in scored if key_fn(q) == value]
            rows.extend(_compute_scope_metrics(scope_type, value, group, relevance_threshold))

    return rows
