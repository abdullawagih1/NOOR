"""
Deterministic (system-sourced) failure detection (mission §42-§44, ADR
0015). Covers the subset of the 17-category taxonomy
(`retrieval_evaluation_failures.failure_category`, migration 0015) that a
purely mechanical rule can detect from ranked results and relevance
judgments alone. The remaining categories (`tokenization_failure`,
`tie_break_failure`, `judgment_gap`, `corpus_gap`, `other`) require human
judgment and are never emitted here — they exist only for
`create_failure_annotation` (a reviewer-driven, `source='human'` path,
already covered by the local RLS suite's TEST 12).

At most one failure is emitted per query — the first matching category in
`_DETECTORS` order (most specific / most actionable first) — so a single
query is never double-counted across overlapping symptoms.
"""
from __future__ import annotations

from dataclasses import dataclass

from app.retrieval.metrics import K_VALUES, QueryEvaluation, hit_rate_at_k, precision_at_k

_MAX_K = max(K_VALUES)


@dataclass(frozen=True)
class DetectedFailure:
    query_id: str
    failure_category: str


def _negative_control_false_positive(qr: QueryEvaluation, threshold: int) -> bool:
    return qr.is_negative_control and len(qr.ranked_corpus_item_ids) > 0


def _query_too_narrow(qr: QueryEvaluation, threshold: int) -> bool:
    # An empty result set for a negative control is the desired outcome,
    # not a failure — never flag it here (it has its own detector above).
    return not qr.is_negative_control and not qr.ranked_corpus_item_ids


def _missed_relevant_item(qr: QueryEvaluation, threshold: int) -> bool:
    relevant_ids = {cid for cid, grade in qr.relevance_by_corpus_item.items() if grade >= threshold}
    return bool(relevant_ids) and not (relevant_ids & set(qr.ranked_corpus_item_ids))


def _relevant_below_k(qr: QueryEvaluation, threshold: int) -> bool:
    relevant_ids = {cid for cid, grade in qr.relevance_by_corpus_item.items() if grade >= threshold}
    retrieved_relevant_ranks = [i for i, cid in enumerate(qr.ranked_corpus_item_ids, start=1) if cid in relevant_ids]
    return bool(retrieved_relevant_ranks) and min(retrieved_relevant_ranks) > _MAX_K


def _non_relevant_ranked_high(qr: QueryEvaluation, threshold: int) -> bool:
    """A relevant item WAS retrieved within the evaluated K (hit_rate@max
    == 1.0) but is outranked by at least one non-relevant item at rank 1 —
    distinct from `missed_relevant_item`/`relevant_below_k`, where no
    relevant item is retrieved within K at all."""
    if hit_rate_at_k(qr, _MAX_K, threshold) != 1.0:
        return False
    return bool(qr.ranked_corpus_item_ids) and qr.grade_of(qr.ranked_corpus_item_ids[0]) < threshold


def _exact_phrase_failure(qr: QueryEvaluation, threshold: int) -> bool:
    return qr.category in ("exact_phrase", "english_exact", "arabic_exact") and hit_rate_at_k(qr, 1, threshold) == 0.0


def _arabic_normalization_failure(qr: QueryEvaluation, threshold: int) -> bool:
    return qr.language == "ar" and hit_rate_at_k(qr, _MAX_K, threshold) == 0.0


def _mixed_language_failure(qr: QueryEvaluation, threshold: int) -> bool:
    return qr.category == "mixed_language" and hit_rate_at_k(qr, _MAX_K, threshold) == 0.0


def _numeric_match_failure(qr: QueryEvaluation, threshold: int) -> bool:
    return qr.category == "numeric_lookup" and hit_rate_at_k(qr, _MAX_K, threshold) == 0.0


def _abbreviation_failure(qr: QueryEvaluation, threshold: int) -> bool:
    return qr.category == "abbreviation" and hit_rate_at_k(qr, _MAX_K, threshold) == 0.0


def _query_too_broad(qr: QueryEvaluation, threshold: int) -> bool:
    return hit_rate_at_k(qr, _MAX_K, threshold) == 1.0 and precision_at_k(qr, _MAX_K, threshold) < 0.3


def _insufficient_lexical_overlap(qr: QueryEvaluation, threshold: int) -> bool:
    return hit_rate_at_k(qr, _MAX_K, threshold) == 0.0 and bool(qr.ranked_corpus_item_ids)


_DETECTORS: tuple[tuple[str, "callable"], ...] = (
    ("negative_control_false_positive", _negative_control_false_positive),
    ("query_too_narrow", _query_too_narrow),
    ("missed_relevant_item", _missed_relevant_item),
    ("relevant_below_k", _relevant_below_k),
    ("exact_phrase_failure", _exact_phrase_failure),
    ("arabic_normalization_failure", _arabic_normalization_failure),
    ("mixed_language_failure", _mixed_language_failure),
    ("numeric_match_failure", _numeric_match_failure),
    ("abbreviation_failure", _abbreviation_failure),
    ("non_relevant_ranked_high", _non_relevant_ranked_high),
    ("query_too_broad", _query_too_broad),
    ("insufficient_lexical_overlap", _insufficient_lexical_overlap),
)


def detect_failures(evaluations: list[QueryEvaluation], relevance_threshold: int) -> list[DetectedFailure]:
    detected: list[DetectedFailure] = []
    for qr in evaluations:
        for category, check in _DETECTORS:
            if check(qr, relevance_threshold):
                detected.append(DetectedFailure(query_id=qr.query_id, failure_category=category))
                break
    return detected
