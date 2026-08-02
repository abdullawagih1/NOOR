"""
Hand-computed correctness proofs for the noor-lexical-baseline-v1 scoring
and tie-breaking layer (Sprint 1-E1, ADR 0015). Every expected value below
is computed by hand against the documented formula, not derived from the
implementation itself.
"""
from __future__ import annotations

import pytest

from app.retrieval.scoring import CandidateRow, ScoredCandidate, compute_token_coverage, is_exact_phrase_match, rank_candidates, score_candidate


def test_token_coverage_full_match_is_sorted_and_one():
    coverage, matched = compute_token_coverage(["pressure", "blood"], {"blood", "pressure", "measurement"})
    assert coverage == 1.0
    assert matched == ("blood", "pressure")  # sorted, not set-iteration order


def test_token_coverage_partial_match():
    coverage, matched = compute_token_coverage(["blood", "pressure", "unrelated"], {"blood", "pressure", "measurement"})
    assert coverage == 2 / 3
    assert matched == ("blood", "pressure")


def test_token_coverage_empty_query_is_zero():
    coverage, matched = compute_token_coverage([], {"blood", "pressure"})
    assert coverage == 0.0
    assert matched == ()


def test_exact_phrase_match_true_and_false():
    assert is_exact_phrase_match("blood pressure", "blood pressure measurement technique") is True
    assert is_exact_phrase_match("blood pressure", "measurement technique only") is False
    assert is_exact_phrase_match("", "anything") is False


def test_score_candidate_matches_hand_computed_formula():
    row = CandidateRow(
        corpus_item_id="c1",
        full_text_rank=0.5,
        normalized_search_text="blood pressure measurement technique",
        token_count=4,
        display_order=1,
        chunk_checksum="chk1",
    )
    scored = score_candidate(row, "blood pressure", ["blood", "pressure"])

    # final_score = 0.7 * 0.5 + 0.3 * 1.0 + 0.15 (exact phrase match) = 0.8
    assert scored.final_score == pytest.approx(0.8)
    assert scored.token_coverage == 1.0
    assert scored.exact_phrase_match is True
    assert scored.matched_token_count == 2
    assert scored.score_components == {"full_text_rank": 0.5, "token_coverage": 1.0, "exact_phrase_bonus": 0.15}


def test_score_candidate_without_exact_phrase_or_full_coverage():
    row = CandidateRow(
        corpus_item_id="c2",
        full_text_rank=0.2,
        normalized_search_text="unrelated hospital parking procedures",
        token_count=4,
        display_order=2,
        chunk_checksum="chk2",
    )
    scored = score_candidate(row, "blood pressure", ["blood", "pressure"])

    # No query tokens present at all -> coverage 0.0, no exact phrase match.
    # final_score = 0.7 * 0.2 + 0.3 * 0.0 + 0 = 0.14
    assert scored.final_score == pytest.approx(0.14)
    assert scored.token_coverage == 0.0
    assert scored.exact_phrase_match is False
    assert scored.matched_token_count == 0


def test_rank_candidates_tie_break_score_desc_then_matched_tokens_desc_then_display_order_then_checksum():
    a = ScoredCandidate("a", final_score=0.5, full_text_rank=0.5, token_coverage=1.0, exact_phrase_match=False, matched_token_count=2, display_order=3, chunk_checksum="zzz")
    b = ScoredCandidate("b", final_score=0.5, full_text_rank=0.5, token_coverage=1.0, exact_phrase_match=False, matched_token_count=3, display_order=1, chunk_checksum="aaa")
    c = ScoredCandidate("c", final_score=0.9, full_text_rank=0.9, token_coverage=1.0, exact_phrase_match=False, matched_token_count=1, display_order=2, chunk_checksum="bbb")
    d = ScoredCandidate("d", final_score=0.5, full_text_rank=0.5, token_coverage=1.0, exact_phrase_match=False, matched_token_count=2, display_order=1, chunk_checksum="aaa")

    ranked = rank_candidates([a, b, c, d])

    # c wins outright on score. Among the 0.5-score group: b (3 matched
    # tokens) beats a and d (2 matched tokens each); between a and d
    # (same score, same matched count), d's display_order (1) beats a's (3).
    assert [x.corpus_item_id for x in ranked] == ["c", "b", "d", "a"]


def test_rank_candidates_never_relies_on_input_order():
    # Same set of candidates, reversed input order, must produce the same
    # ranked output — proves the sort key, not list position, decides order.
    a = ScoredCandidate("a", final_score=0.3, full_text_rank=0.3, token_coverage=0.5, exact_phrase_match=False, matched_token_count=1, display_order=2, chunk_checksum="b")
    b = ScoredCandidate("b", final_score=0.3, full_text_rank=0.3, token_coverage=0.5, exact_phrase_match=False, matched_token_count=1, display_order=1, chunk_checksum="a")

    forward = [x.corpus_item_id for x in rank_candidates([a, b])]
    backward = [x.corpus_item_id for x in rank_candidates([b, a])]
    assert forward == backward == ["b", "a"]
