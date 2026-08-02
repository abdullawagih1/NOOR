"""
`LexicalRetriever` unit tests (Sprint 1-E1, ADR 0015) — a fake in-memory
candidate fetcher only, proving the Retriever contract itself (ranking,
top_k truncation, rank numbering) with zero network or database access.
"""
from __future__ import annotations

from app.retrieval.retriever import LexicalRetriever, RetrievalConfiguration
from app.retrieval.scoring import CandidateRow

CONFIG = RetrievalConfiguration(retriever_name="noor-lexical-baseline", retriever_version="1", configuration_version="1", top_k=2)


def test_lexical_retriever_ranks_and_truncates_to_top_k():
    rows = [
        CandidateRow("low", full_text_rank=0.1, normalized_search_text="unrelated text entirely", token_count=3, display_order=3, chunk_checksum="c3"),
        CandidateRow("high", full_text_rank=0.9, normalized_search_text="blood pressure measurement", token_count=3, display_order=1, chunk_checksum="c1"),
        CandidateRow("mid", full_text_rank=0.5, normalized_search_text="blood pressure device", token_count=3, display_order=2, chunk_checksum="c2"),
    ]
    retriever = LexicalRetriever(fetch_candidates=lambda _text: rows)

    results = retriever.retrieve("blood pressure", CONFIG)

    assert len(results) == 2  # top_k=2, truncates the third candidate
    assert [r.corpus_item_id for r in results] == ["high", "mid"]
    assert [r.rank for r in results] == [1, 2]


def test_lexical_retriever_returns_empty_list_when_fetcher_returns_nothing():
    retriever = LexicalRetriever(fetch_candidates=lambda _text: [])
    assert retriever.retrieve("anything", CONFIG) == []


def test_lexical_retriever_passes_normalized_query_text_through_unchanged():
    seen: list[str] = []

    def fetcher(text: str) -> list[CandidateRow]:
        seen.append(text)
        return []

    retriever = LexicalRetriever(fetch_candidates=fetcher)
    retriever.retrieve("قياس ضغط الدم", CONFIG)
    assert seen == ["قياس ضغط الدم"]
