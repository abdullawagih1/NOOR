"""
noor-lexical-baseline-v1 scoring and deterministic tie-breaking (ADR 0015,
retrieval_configuration_version = "1"). Pure Python, no network/database
access — takes already-fetched candidate rows as plain data (see
`get_retrieval_candidates` in migration 0015 for where `full_text_rank`
comes from).
"""
from __future__ import annotations

from dataclasses import dataclass, field

from app.retrieval.config import EXACT_PHRASE_BONUS, WEIGHT_FULL_TEXT_RANK, WEIGHT_TOKEN_COVERAGE
from app.retrieval.tokenizer import tokenize


@dataclass(frozen=True)
class CandidateRow:
    """One row returned by `get_retrieval_candidates`."""

    corpus_item_id: str
    full_text_rank: float
    normalized_search_text: str
    token_count: int
    display_order: int
    chunk_checksum: str


@dataclass(frozen=True)
class ScoredCandidate:
    corpus_item_id: str
    final_score: float
    full_text_rank: float
    token_coverage: float
    exact_phrase_match: bool
    matched_token_count: int
    display_order: int
    chunk_checksum: str
    matched_terms: tuple[str, ...] = field(default_factory=tuple)

    @property
    def score_components(self) -> dict:
        return {
            "full_text_rank": self.full_text_rank,
            "token_coverage": self.token_coverage,
            "exact_phrase_bonus": EXACT_PHRASE_BONUS if self.exact_phrase_match else 0.0,
        }


def compute_token_coverage(query_tokens: list[str], document_tokens: set[str]) -> tuple[float, tuple[str, ...]]:
    """Fraction of unique normalized query tokens present in the normalized
    document text. Returns (coverage, matched_terms) — matched_terms is
    sorted for determinism, never set-iteration order."""
    if not query_tokens:
        return 0.0, ()
    unique_query_tokens = set(query_tokens)
    matched = unique_query_tokens & document_tokens
    return len(matched) / len(unique_query_tokens), tuple(sorted(matched))


def is_exact_phrase_match(normalized_query_text: str, normalized_document_text: str) -> bool:
    if not normalized_query_text:
        return False
    return normalized_query_text in normalized_document_text


def score_candidate(row: CandidateRow, normalized_query_text: str, query_tokens: list[str]) -> ScoredCandidate:
    document_tokens = set(tokenize(row.normalized_search_text))
    token_coverage, matched_terms = compute_token_coverage(query_tokens, document_tokens)
    exact_match = is_exact_phrase_match(normalized_query_text, row.normalized_search_text)
    final_score = (
        WEIGHT_FULL_TEXT_RANK * row.full_text_rank
        + WEIGHT_TOKEN_COVERAGE * token_coverage
        + (EXACT_PHRASE_BONUS if exact_match else 0.0)
    )
    return ScoredCandidate(
        corpus_item_id=row.corpus_item_id,
        final_score=final_score,
        full_text_rank=row.full_text_rank,
        token_coverage=token_coverage,
        exact_phrase_match=exact_match,
        matched_token_count=len(matched_terms),
        display_order=row.display_order,
        chunk_checksum=row.chunk_checksum,
        matched_terms=matched_terms,
    )


def rank_candidates(scored: list[ScoredCandidate]) -> list[ScoredCandidate]:
    """Deterministic tie-breaking (ADR 0015): score desc -> matched-token
    count desc -> corpus display_order asc -> chunk_checksum asc. Never
    database row-insertion order, which Postgres does not guarantee stable
    across query plans."""
    return sorted(
        scored,
        key=lambda c: (-c.final_score, -c.matched_token_count, c.display_order, c.chunk_checksum),
    )
