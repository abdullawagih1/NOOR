"""
Hand-computed correctness proofs for Precision@K, Recall@K, Hit Rate@K,
MRR, and nDCG@K (Sprint 1-E1, ADR 0015, metric_definition_version = "1"),
plus the negative-control exclusion rule documented in
app/retrieval/metrics.py.
"""
from __future__ import annotations

import pytest

from app.retrieval.metrics import QueryEvaluation, compute_all_metrics, hit_rate_at_k, ndcg_at_k, precision_at_k, recall_at_k, reciprocal_rank

THRESHOLD = 2

PERFECT_HIT = QueryEvaluation(
    query_id="q-perfect",
    query_key="perfect",
    language="en",
    category="exact_phrase",
    difficulty="basic",
    is_negative_control=False,
    ranked_corpus_item_ids=("a", "b", "c"),
    relevance_by_corpus_item={"a": 3, "b": 0, "c": 0},
    total_relevant_count=1,
)

TOTAL_MISS = QueryEvaluation(
    query_id="q-miss",
    query_key="miss",
    language="ar",
    category="keyword_lookup",
    difficulty="moderate",
    is_negative_control=False,
    ranked_corpus_item_ids=("x", "y"),
    relevance_by_corpus_item={"z": 3},  # the one relevant item was never retrieved
    total_relevant_count=1,
)

NEGATIVE_CONTROL = QueryEvaluation(
    query_id="q-negative",
    query_key="negative",
    language="en",
    category="negative_control",
    difficulty="basic",
    is_negative_control=True,
    ranked_corpus_item_ids=(),
    relevance_by_corpus_item={},
    total_relevant_count=0,
)


def test_perfect_hit_metrics():
    assert precision_at_k(PERFECT_HIT, 1, THRESHOLD) == 1.0
    assert precision_at_k(PERFECT_HIT, 3, THRESHOLD) == pytest.approx(1 / 3)
    assert recall_at_k(PERFECT_HIT, 1, THRESHOLD) == 1.0
    assert recall_at_k(PERFECT_HIT, 3, THRESHOLD) == 1.0
    assert hit_rate_at_k(PERFECT_HIT, 1, THRESHOLD) == 1.0
    assert reciprocal_rank(PERFECT_HIT, THRESHOLD) == 1.0
    # actual grades [3, 0, 0] vs. ideal [3, 0, 0] (same set of judged
    # grades) -> DCG == IDCG -> nDCG == 1.0 exactly, at every K.
    assert ndcg_at_k(PERFECT_HIT, 1) == 1.0
    assert ndcg_at_k(PERFECT_HIT, 3) == 1.0


def test_total_miss_metrics():
    assert precision_at_k(TOTAL_MISS, 2, THRESHOLD) == 0.0
    assert recall_at_k(TOTAL_MISS, 2, THRESHOLD) == 0.0
    assert hit_rate_at_k(TOTAL_MISS, 2, THRESHOLD) == 0.0
    assert reciprocal_rank(TOTAL_MISS, THRESHOLD) == 0.0
    # No relevant grade appears anywhere in the ranked list -> DCG == 0;
    # IDCG is computed from the one known relevant grade (3) -> nDCG == 0.
    assert ndcg_at_k(TOTAL_MISS, 2) == 0.0


def test_recall_is_zero_when_no_relevant_items_are_judged_at_all():
    no_relevant = QueryEvaluation(
        query_id="q-none", query_key="none", language="en", category="other", difficulty="basic",
        is_negative_control=False, ranked_corpus_item_ids=("a",), relevance_by_corpus_item={}, total_relevant_count=0,
    )
    assert recall_at_k(no_relevant, 1, THRESHOLD) == 0.0
    assert ndcg_at_k(no_relevant, 1) == 0.0  # idcg <= 0 short-circuits to 0.0, never a division error


def test_compute_all_metrics_excludes_negative_controls_from_every_aggregate():
    rows = compute_all_metrics([PERFECT_HIT, TOTAL_MISS, NEGATIVE_CONTROL], THRESHOLD)

    overall_precision_1 = next(r for r in rows if r.scope_type == "overall" and r.metric_name == "precision_at_1")
    assert overall_precision_1.sample_size == 2  # never 3 -- the negative control is excluded
    assert overall_precision_1.metric_value == pytest.approx((1.0 + 0.0) / 2)

    # No scope_value == 'negative_control' (or any category tied to the
    # excluded query) ever appears in the metrics table.
    assert not any(r.scope_value == "negative_control" for r in rows)
    assert not any(r.scope_type == "language" and r.scope_value == "en" and r.sample_size != 1 for r in rows)


def test_compute_all_metrics_scopes_by_language_and_category():
    rows = compute_all_metrics([PERFECT_HIT, TOTAL_MISS], THRESHOLD)

    en_precision_1 = next(r for r in rows if r.scope_type == "language" and r.scope_value == "en" and r.metric_name == "precision_at_1")
    assert en_precision_1.metric_value == 1.0
    assert en_precision_1.sample_size == 1

    ar_precision_1 = next(r for r in rows if r.scope_type == "language" and r.scope_value == "ar" and r.metric_name == "precision_at_1")
    assert ar_precision_1.metric_value == 0.0

    category_row = next(r for r in rows if r.scope_type == "category" and r.scope_value == "exact_phrase" and r.metric_name == "mrr")
    assert category_row.metric_value == 1.0
