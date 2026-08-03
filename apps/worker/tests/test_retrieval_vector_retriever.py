"""
`VectorRetriever` unit tests (Sprint 1-E2, ADR 0016) — a fake in-memory
candidate fetcher only, proving the Retriever contract (rank assignment,
top_k truncation) with zero network or database access. Unlike
`LexicalRetriever`, ordering itself is trusted from the fetcher (the SQL
layer already sorts by distance/tie-break) — this class only assigns ranks.
"""
from __future__ import annotations

from app.retrieval.retriever import RetrievalConfiguration, VectorCandidateRow, VectorRetriever

CONFIG = RetrievalConfiguration(retriever_name="noor-vector-baseline", retriever_version="1", configuration_version="noor-multilingual-e5-base-v1", top_k=2)


def test_vector_retriever_assigns_ranks_in_fetcher_order():
    rows = [
        VectorCandidateRow(corpus_item_id="closest", distance=0.05, similarity=0.95, display_order=2, chunk_checksum="c2"),
        VectorCandidateRow(corpus_item_id="mid", distance=0.3, similarity=0.7, display_order=1, chunk_checksum="c1"),
        VectorCandidateRow(corpus_item_id="farthest", distance=0.8, similarity=0.2, display_order=3, chunk_checksum="c3"),
    ]
    retriever = VectorRetriever(fetch_candidates=lambda: rows)

    results = retriever.retrieve("blood pressure", CONFIG)

    assert len(results) == 2  # top_k=2, truncates the third candidate
    assert [r.corpus_item_id for r in results] == ["closest", "mid"]
    assert [r.rank for r in results] == [1, 2]


def test_vector_retriever_final_score_is_cosine_similarity():
    rows = [VectorCandidateRow(corpus_item_id="a", distance=0.1, similarity=0.9, display_order=1, chunk_checksum="c1")]
    retriever = VectorRetriever(fetch_candidates=lambda: rows)

    results = retriever.retrieve("anything", CONFIG)

    assert results[0].final_score == 0.9
    assert results[0].score_components == {"distance": 0.1, "similarity": 0.9}


def test_vector_retriever_never_returns_matched_terms():
    rows = [VectorCandidateRow(corpus_item_id="a", distance=0.1, similarity=0.9, display_order=1, chunk_checksum="c1")]
    retriever = VectorRetriever(fetch_candidates=lambda: rows)

    results = retriever.retrieve("anything", CONFIG)

    assert results[0].matched_terms == ()


def test_vector_retriever_returns_empty_list_when_fetcher_returns_nothing():
    retriever = VectorRetriever(fetch_candidates=lambda: [])
    assert retriever.retrieve("anything", CONFIG) == []
