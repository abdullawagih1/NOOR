"""
Canonical JSON evaluation artifact — one artifact per evaluation run,
storing every ranked result, metric, and detected failure (mission §46-§48).
Stored in the same private "processed artifact" Storage model as chunking
(`guideline-processed`, ADR 0015) — never `evaluation-assets`. Field
ordering is irrelevant to determinism — `checksums.compute_artifact_checksum`
serializes with `sort_keys=True`.

Never included: secrets, signed URLs, local temporary file paths, the
Worker's lease token, or raw stack traces.
"""
from __future__ import annotations

from app.retrieval.config import ARTIFACT_SCHEMA_VERSION
from app.retrieval.failure_analysis import DetectedFailure
from app.retrieval.metrics import MetricRow
from app.retrieval.retriever import RetrievalCandidate


def build_canonical_evaluation_artifact(
    *,
    dataset_id: str,
    dataset_sha256: str,
    evaluation_run_id: str,
    retriever_name: str,
    retriever_version: str,
    retrieval_configuration_version: str,
    query_normalization_version: str,
    metric_definition_version: str,
    evaluation_runner_version: str,
    top_k_values: list[int],
    relevance_threshold: int,
    results_by_query: dict[str, list[RetrievalCandidate]],
    query_metadata: dict[str, dict],
    metrics: list[MetricRow],
    failures: list[DetectedFailure],
) -> dict:
    return {
        "schema_version": ARTIFACT_SCHEMA_VERSION,
        "dataset": {"dataset_id": dataset_id, "dataset_sha256": dataset_sha256},
        "evaluation_run_id": evaluation_run_id,
        "identity": {
            "retriever_name": retriever_name,
            "retriever_version": retriever_version,
            "retrieval_configuration_version": retrieval_configuration_version,
            "query_normalization_version": query_normalization_version,
            "metric_definition_version": metric_definition_version,
            "evaluation_runner_version": evaluation_runner_version,
            "top_k_values": top_k_values,
            "relevance_threshold": relevance_threshold,
        },
        "results": [
            {
                "query_id": query_id,
                "query_key": query_metadata[query_id]["query_key"],
                "language": query_metadata[query_id]["language"],
                "category": query_metadata[query_id]["category"],
                "difficulty": query_metadata[query_id]["difficulty"],
                "is_negative_control": query_metadata[query_id]["is_negative_control"],
                "ranked_candidates": [_candidate_to_dict(c) for c in candidates],
            }
            for query_id, candidates in sorted(results_by_query.items())
        ],
        "metrics": [
            {
                "scope_type": m.scope_type,
                "scope_value": m.scope_value,
                "metric_name": m.metric_name,
                "metric_value": m.metric_value,
                "sample_size": m.sample_size,
            }
            for m in metrics
        ],
        "failures": [{"query_id": f.query_id, "failure_category": f.failure_category} for f in failures],
    }


def _candidate_to_dict(candidate: RetrievalCandidate) -> dict:
    return {
        "corpus_item_id": candidate.corpus_item_id,
        "rank": candidate.rank,
        "final_score": candidate.final_score,
        "score_components": candidate.score_components,
        "matched_terms": list(candidate.matched_terms),
    }
