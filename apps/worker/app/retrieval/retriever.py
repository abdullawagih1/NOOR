"""
Provider-independent retrieval contracts (mission §31-§34, ADR 0015). A
`Retriever` is anything that turns a normalized query into a ranked list of
`RetrievalCandidate` objects for a given `RetrievalConfiguration`.
`LexicalRetriever` (Sprint 1-E1) and `VectorRetriever` (Sprint 1-E2, ADR
0016) are both implemented — `HybridRetriever` and `RerankerRetriever`
remain stubs so a future sprint slots into this same contract, but they
compute nothing here (mission's explicit hybrid/reranking boundary).

Both retrievers take an injected candidate-fetch callable rather than
calling PostgREST/httpx themselves, so the entire scoring/tie-break
pipeline is unit-testable with a fake in-memory fetcher — no network or
database access required (matching CI's `Worker` job, which has no
Postgres service).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Protocol

from app.retrieval.scoring import CandidateRow, ScoredCandidate, rank_candidates, score_candidate
from app.retrieval.tokenizer import tokenize


@dataclass(frozen=True)
class RetrievalConfiguration:
    retriever_name: str
    retriever_version: str
    configuration_version: str
    top_k: int


@dataclass(frozen=True)
class RetrievalCandidate:
    corpus_item_id: str
    rank: int
    final_score: float
    score_components: dict
    matched_terms: tuple[str, ...]


class Retriever(Protocol):
    def retrieve(self, normalized_query_text: str, configuration: RetrievalConfiguration) -> list[RetrievalCandidate]:
        ...


CandidateFetcher = Callable[[str], list[CandidateRow]]


class LexicalRetriever:
    """noor-lexical-baseline-v1 (ADR 0015) — the only `Retriever`
    implemented this sprint."""

    def __init__(self, fetch_candidates: CandidateFetcher) -> None:
        self._fetch_candidates = fetch_candidates

    def retrieve(self, normalized_query_text: str, configuration: RetrievalConfiguration) -> list[RetrievalCandidate]:
        rows = self._fetch_candidates(normalized_query_text)
        query_tokens = tokenize(normalized_query_text)
        scored = [score_candidate(row, normalized_query_text, query_tokens) for row in rows]
        ranked = rank_candidates(scored)[: configuration.top_k]
        return [_to_retrieval_candidate(c, rank) for rank, c in enumerate(ranked, start=1)]


def _to_retrieval_candidate(candidate: ScoredCandidate, rank: int) -> RetrievalCandidate:
    return RetrievalCandidate(
        corpus_item_id=candidate.corpus_item_id,
        rank=rank,
        final_score=candidate.final_score,
        score_components=candidate.score_components,
        matched_terms=candidate.matched_terms,
    )


@dataclass(frozen=True)
class VectorCandidateRow:
    corpus_item_id: str
    distance: float
    similarity: float
    display_order: int
    chunk_checksum: str


VectorCandidateFetcher = Callable[[], list[VectorCandidateRow]]


class VectorRetriever:
    """noor-vector-baseline-v1 (Sprint 1-E2, ADR 0016). Unlike
    `LexicalRetriever`, the fetch callable takes no query-text argument —
    the SQL layer (`get_vector_search_candidates`, migration 0017) already
    resolves the stored query embedding and performs the cosine-distance
    ordering (including tie-break) server-side; this class only assigns
    ranks and top-K clips, mirroring the exact same ordering the SQL
    query already produced rather than re-sorting in Python."""

    def __init__(self, fetch_candidates: VectorCandidateFetcher) -> None:
        self._fetch_candidates = fetch_candidates

    def retrieve(self, normalized_query_text: str, configuration: RetrievalConfiguration) -> list[RetrievalCandidate]:
        rows = self._fetch_candidates()
        top_k = rows[: configuration.top_k]
        return [
            RetrievalCandidate(
                corpus_item_id=row.corpus_item_id,
                rank=rank,
                final_score=row.similarity,
                score_components={"distance": row.distance, "similarity": row.similarity},
                matched_terms=(),
            )
            for rank, row in enumerate(top_k, start=1)
        ]


# ----------------------------------------------------------------------------
# Future retrieval strategies — explicitly out of scope this sprint (no
# fusion, no external AI calls, no reranking; ADR 0015/0016 "Boundaries").
# Declared only so a future sprint's implementation slots into the same
# `Retriever` contract; nothing here is implemented.
# ----------------------------------------------------------------------------


class HybridRetriever(Protocol):  # pragma: no cover - stub, not implemented
    def retrieve(self, normalized_query_text: str, configuration: RetrievalConfiguration) -> list[RetrievalCandidate]:
        ...


class RerankerRetriever(Protocol):  # pragma: no cover - stub, not implemented
    def rerank(self, normalized_query_text: str, candidates: list[RetrievalCandidate]) -> list[RetrievalCandidate]:
        ...
