"""
One constructed QueryEvaluation per system-detectable failure category
(Sprint 1-E1, ADR 0015) — proves each detector fires on its own designed
trigger and that at most one category is ever emitted per query (priority
order in app/retrieval/failure_analysis.py's _DETECTORS).
"""
from __future__ import annotations

from app.retrieval.failure_analysis import detect_failures
from app.retrieval.metrics import QueryEvaluation

THRESHOLD = 2


def _qe(**overrides) -> QueryEvaluation:
    defaults = dict(
        query_id="q1", query_key="k1", language="en", category="other", difficulty="basic",
        is_negative_control=False, ranked_corpus_item_ids=(), relevance_by_corpus_item={}, total_relevant_count=0,
    )
    defaults.update(overrides)
    return QueryEvaluation(**defaults)


def _category_for(qe: QueryEvaluation) -> str | None:
    detected = detect_failures([qe], THRESHOLD)
    return detected[0].failure_category if detected else None


def test_negative_control_false_positive():
    qe = _qe(is_negative_control=True, category="negative_control", ranked_corpus_item_ids=("a",))
    assert _category_for(qe) == "negative_control_false_positive"


def test_negative_control_with_no_candidates_is_not_a_failure():
    qe = _qe(is_negative_control=True, category="negative_control", ranked_corpus_item_ids=())
    assert _category_for(qe) is None


def test_query_too_narrow_when_nothing_is_retrieved():
    qe = _qe(ranked_corpus_item_ids=(), relevance_by_corpus_item={"z": 3}, total_relevant_count=1)
    assert _category_for(qe) == "query_too_narrow"


def test_missed_relevant_item_when_relevant_chunk_never_retrieved():
    qe = _qe(ranked_corpus_item_ids=("x", "y"), relevance_by_corpus_item={"z": 3}, total_relevant_count=1)
    assert _category_for(qe) == "missed_relevant_item"


def test_relevant_below_k_when_relevant_item_ranked_past_ten():
    ranked = tuple(f"item{i}" for i in range(1, 12))  # 11 items; the relevant one is last
    qe = _qe(ranked_corpus_item_ids=ranked, relevance_by_corpus_item={"item11": 3}, total_relevant_count=1)
    assert _category_for(qe) == "relevant_below_k"


def test_exact_phrase_failure_on_top1_miss_for_exact_phrase_category():
    qe = _qe(category="exact_phrase", ranked_corpus_item_ids=("a",), relevance_by_corpus_item={}, total_relevant_count=0)
    assert _category_for(qe) == "exact_phrase_failure"


def test_arabic_normalization_failure():
    qe = _qe(language="ar", category="arabic_keyword", ranked_corpus_item_ids=("a",), relevance_by_corpus_item={}, total_relevant_count=0)
    assert _category_for(qe) == "arabic_normalization_failure"


def test_mixed_language_failure():
    qe = _qe(language="en", category="mixed_language", ranked_corpus_item_ids=("a",), relevance_by_corpus_item={}, total_relevant_count=0)
    assert _category_for(qe) == "mixed_language_failure"


def test_numeric_match_failure():
    qe = _qe(language="en", category="numeric_lookup", ranked_corpus_item_ids=("a",), relevance_by_corpus_item={}, total_relevant_count=0)
    assert _category_for(qe) == "numeric_match_failure"


def test_abbreviation_failure():
    qe = _qe(language="en", category="abbreviation", ranked_corpus_item_ids=("a",), relevance_by_corpus_item={}, total_relevant_count=0)
    assert _category_for(qe) == "abbreviation_failure"


def test_non_relevant_ranked_high_when_a_hit_exists_but_not_at_rank_one():
    # The relevant item ("b") IS retrieved within the top 10 (hit_rate@10
    # == 1.0) but is outranked by a non-relevant item ("a") at rank 1.
    qe = _qe(category="other", ranked_corpus_item_ids=("a", "b"), relevance_by_corpus_item={"b": 3}, total_relevant_count=1)
    assert _category_for(qe) == "non_relevant_ranked_high"


def test_query_too_broad_when_hit_exists_at_rank_one_but_precision_is_low():
    # Rank 1 IS relevant (so non_relevant_ranked_high does not fire), but
    # 9 irrelevant items follow it within the evaluated top 10.
    ranked = ("relevant",) + tuple(f"noise{i}" for i in range(9))
    qe = _qe(category="other", ranked_corpus_item_ids=ranked, relevance_by_corpus_item={"relevant": 3}, total_relevant_count=1)
    assert _category_for(qe) == "query_too_broad"


def test_healthy_query_raises_no_failure():
    qe = _qe(category="other", ranked_corpus_item_ids=("a", "b", "c"), relevance_by_corpus_item={"a": 3}, total_relevant_count=1)
    assert _category_for(qe) is None


def test_at_most_one_failure_emitted_per_query_across_a_batch():
    negative = _qe(query_id="n1", is_negative_control=True, category="negative_control", ranked_corpus_item_ids=("a",))
    narrow = _qe(query_id="n2", ranked_corpus_item_ids=(), relevance_by_corpus_item={"z": 3}, total_relevant_count=1)
    healthy = _qe(query_id="n3", ranked_corpus_item_ids=("a",), relevance_by_corpus_item={"a": 3}, total_relevant_count=1)

    detected = detect_failures([negative, narrow, healthy], THRESHOLD)
    by_query = {d.query_id: d.failure_category for d in detected}

    assert by_query == {"n1": "negative_control_false_positive", "n2": "query_too_narrow"}
    assert "n3" not in by_query
