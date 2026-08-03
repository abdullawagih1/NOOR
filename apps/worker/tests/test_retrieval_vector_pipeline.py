"""
Vector-evaluation pipeline tests (Sprint 1-E2, ADR 0016) — exact-vs-indexed
comparison metrics (mission §36) and the end-to-end pipeline reusing
S1-E1's metric/failure/artifact machinery unmodified. Zero network or
database access — fake candidate fetchers only.
"""
from __future__ import annotations

from app.retrieval.retriever import RetrievalCandidate
from app.retrieval.vector_pipeline import (
    _compare_exact_vs_indexed,
    _compute_exact_vs_indexed_metrics,
    run_vector_evaluation_pipeline,
)


def _candidate(corpus_item_id: str, rank: int) -> RetrievalCandidate:
    return RetrievalCandidate(corpus_item_id=corpus_item_id, rank=rank, final_score=1.0 - rank * 0.1, score_components={}, matched_terms=())


def test_compare_exact_vs_indexed_perfect_agreement():
    exact = [_candidate("a", 1), _candidate("b", 2), _candidate("c", 3)]
    indexed = [_candidate("a", 1), _candidate("b", 2), _candidate("c", 3)]
    result = _compare_exact_vs_indexed(exact, indexed)
    assert result["recall_by_k"][1] == 1.0
    assert result["recall_by_k"][3] == 1.0
    assert result["rank_agreement"] == 1.0


def test_compare_exact_vs_indexed_detects_missing_top1():
    exact = [_candidate("a", 1), _candidate("b", 2)]
    indexed = [_candidate("z", 1), _candidate("b", 2)]  # top-1 disagrees
    result = _compare_exact_vs_indexed(exact, indexed)
    assert result["recall_by_k"][1] == 0.0  # "a" missing from indexed top-1


def test_compare_exact_vs_indexed_no_exact_neighbors_is_vacuously_perfect():
    result = _compare_exact_vs_indexed([], [])
    assert all(v == 1.0 for v in result["recall_by_k"].values())


def test_compute_exact_vs_indexed_metrics_empty_input():
    assert _compute_exact_vs_indexed_metrics([]) == []


def test_compute_exact_vs_indexed_metrics_averages_across_queries():
    per_query = [
        {"recall_by_k": {1: 1.0, 3: 1.0, 5: 1.0, 10: 1.0}, "rank_agreement": 1.0},
        {"recall_by_k": {1: 0.0, 3: 1.0, 5: 1.0, 10: 1.0}, "rank_agreement": 0.5},
    ]
    metrics = _compute_exact_vs_indexed_metrics(per_query)
    by_name = {m.metric_name: m.metric_value for m in metrics}
    assert by_name["exact_vs_indexed_recall_at_1"] == 0.5
    assert by_name["exact_vs_indexed_recall_at_3"] == 1.0
    assert by_name["exact_vs_indexed_rank_agreement"] == 0.75
    assert all(m.scope_type == "exact_vs_indexed" for m in metrics)


def _query_row(query_id: str, query_key: str) -> dict:
    return {
        "out_query_id": query_id,
        "out_query_key": query_key,
        "out_normalized_query_text": "blood pressure",
        "out_language": "en",
        "out_category": "english_exact",
        "out_difficulty": "basic",
        "out_is_negative_control": False,
    }


def test_run_vector_evaluation_pipeline_end_to_end_with_fake_fetchers():
    query_rows = [_query_row("q1", "q-diabetes")]
    judgment_rows = [{"query_id": "q1", "corpus_item_id": "chunk-1", "relevance_grade": 3}]

    def fetch_exact(_query_id: str):
        from app.retrieval.retriever import VectorCandidateRow

        return [VectorCandidateRow(corpus_item_id="chunk-1", distance=0.05, similarity=0.95, display_order=1, chunk_checksum="c1")]

    def fetch_indexed(_query_id: str):
        from app.retrieval.retriever import VectorCandidateRow

        return [VectorCandidateRow(corpus_item_id="chunk-1", distance=0.05, similarity=0.95, display_order=1, chunk_checksum="c1")]

    outcome = run_vector_evaluation_pipeline(
        organization_id="org-1",
        dataset_id="dataset-1",
        dataset_sha256="dataset-checksum",
        evaluation_run_id="run-1",
        query_rows=query_rows,
        judgment_rows=judgment_rows,
        fetch_exact_candidates=fetch_exact,
        fetch_indexed_candidates=fetch_indexed,
        retriever_name="noor-vector-baseline",
        retriever_version="1",
        embedding_configuration_key="noor-multilingual-e5-base-v1",
        query_normalization_version="retrieval_text_normalization_v1",
        metric_definition_version="1",
        evaluation_runner_version="1",
        top_k_values=[1, 3, 5, 10],
        relevance_threshold=2,
    )

    assert len(outcome.results_payload) == 1
    assert outcome.results_payload[0]["corpus_item_id"] == "chunk-1"
    assert outcome.results_payload[0]["is_hit"] is True

    metric_names = {m["metric_name"] for m in outcome.metrics_payload}
    assert "mrr" in metric_names  # standard retrieval-quality metric, reused unmodified
    assert "exact_vs_indexed_recall_at_1" in metric_names  # new vector-specific metric
    assert "exact_vs_indexed_rank_agreement" in metric_names
