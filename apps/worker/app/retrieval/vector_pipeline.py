"""
Vector-baseline evaluation pipeline (Sprint 1-E2, ADR 0016) — extends the
existing S1-E1 evaluation framework rather than forking a parallel one.
`compute_all_metrics`, `detect_failures`, `build_canonical_evaluation_artifact`,
and the results-payload shape are all reused completely unmodified from
`app/retrieval/pipeline.py` / `metrics.py` / `failure_analysis.py` / `artifact.py`.

For every query this runs BOTH the exact (sequential-scan) and indexed
(HNSW) vector-search paths (mission §36) — the INDEXED result is treated as
the "official" ranked result evaluated for retrieval quality (Precision/
Recall/MRR/nDCG), while the exact path is the correctness reference used
only to compute exact-vs-indexed recall/rank-agreement metrics. This never
merges retrieval-quality and system-correctness scores into one number
(mission §43).
"""
from __future__ import annotations

from app.retrieval.artifact import build_canonical_evaluation_artifact
from app.retrieval.checksums import canonical_bytes, compute_artifact_checksum
from app.retrieval.config import ARTIFACT_MEDIA_TYPE, ARTIFACT_STORAGE_BUCKET
from app.retrieval.errors import RetrievalEvaluationError
from app.retrieval.failure_analysis import DetectedFailure, detect_failures
from app.retrieval.metrics import K_VALUES, MetricRow, QueryEvaluation, compute_all_metrics
from app.retrieval.pipeline import EvaluationPipelineOutcome, _build_results_payload, build_evaluation_artifact_storage_path
from app.retrieval.retriever import RetrievalConfiguration, VectorRetriever


def run_vector_evaluation_pipeline(
    *,
    organization_id: str,
    dataset_id: str,
    dataset_sha256: str,
    evaluation_run_id: str,
    query_rows: list[dict],
    judgment_rows: list[dict],
    fetch_exact_candidates,  # Callable[[str], list[VectorCandidateRow]] -- query_id -> rows
    fetch_indexed_candidates,  # Callable[[str], list[VectorCandidateRow]] -- query_id -> rows
    retriever_name: str,
    retriever_version: str,
    embedding_configuration_key: str,
    query_normalization_version: str,
    metric_definition_version: str,
    evaluation_runner_version: str,
    top_k_values: list[int],
    relevance_threshold: int,
) -> EvaluationPipelineOutcome:
    max_k = max(top_k_values)
    configuration = RetrievalConfiguration(
        retriever_name=retriever_name,
        retriever_version=retriever_version,
        configuration_version=embedding_configuration_key,
        top_k=max_k,
    )

    judgments_by_query: dict[str, dict[str, int]] = {}
    for row in judgment_rows:
        judgments_by_query.setdefault(str(row["query_id"]), {})[str(row["corpus_item_id"])] = int(row["relevance_grade"])

    results_by_query: dict[str, list] = {}
    evaluations: list[QueryEvaluation] = []
    query_metadata: dict[str, dict] = {}
    exact_vs_indexed_per_query: list[dict] = []
    disagreement_failures: list[DetectedFailure] = []

    for row in query_rows:
        query_id = str(row["out_query_id"])
        normalized_query_text = row["out_normalized_query_text"] or ""

        try:
            indexed_retriever = VectorRetriever(fetch_candidates=lambda qid=query_id: fetch_indexed_candidates(qid))
            exact_retriever = VectorRetriever(fetch_candidates=lambda qid=query_id: fetch_exact_candidates(qid))
            indexed_candidates = indexed_retriever.retrieve(normalized_query_text, configuration)
            exact_candidates = exact_retriever.retrieve(normalized_query_text, configuration)
        except Exception as exc:
            raise RetrievalEvaluationError("candidate_fetch_failed", "could not fetch vector retrieval candidates for a query") from exc

        results_by_query[query_id] = indexed_candidates
        query_metadata[query_id] = {
            "query_key": row["out_query_key"],
            "language": row["out_language"],
            "category": row["out_category"],
            "difficulty": row["out_difficulty"],
            "is_negative_control": bool(row["out_is_negative_control"]),
        }

        relevance = judgments_by_query.get(query_id, {})
        total_relevant = sum(1 for grade in relevance.values() if grade >= relevance_threshold)
        evaluations.append(
            QueryEvaluation(
                query_id=query_id,
                query_key=row["out_query_key"],
                language=row["out_language"],
                category=row["out_category"],
                difficulty=row["out_difficulty"],
                is_negative_control=bool(row["out_is_negative_control"]),
                ranked_corpus_item_ids=tuple(c.corpus_item_id for c in indexed_candidates),
                relevance_by_corpus_item=relevance,
                total_relevant_count=total_relevant,
            )
        )

        exact_vs_indexed_per_query.append(_compare_exact_vs_indexed(exact_candidates, indexed_candidates))

        exact_top1 = exact_candidates[0].corpus_item_id if exact_candidates else None
        indexed_top1 = indexed_candidates[0].corpus_item_id if indexed_candidates else None
        if exact_top1 != indexed_top1:
            disagreement_failures.append(DetectedFailure(query_id=query_id, failure_category="exact_index_disagreement"))

    metrics = compute_all_metrics(evaluations, relevance_threshold)
    metrics.extend(_compute_exact_vs_indexed_metrics(exact_vs_indexed_per_query))

    failures = detect_failures(evaluations, relevance_threshold)
    failures.extend(disagreement_failures)

    evaluations_by_id = {e.query_id: e for e in evaluations}
    results_payload = _build_results_payload(results_by_query, evaluations_by_id, relevance_threshold)
    metrics_payload = [
        {"scope_type": m.scope_type, "scope_value": m.scope_value, "metric_name": m.metric_name, "metric_value": m.metric_value, "sample_size": m.sample_size}
        for m in metrics
    ]
    failures_payload = [{"query_id": f.query_id, "failure_category": f.failure_category} for f in failures]

    try:
        artifact = build_canonical_evaluation_artifact(
            dataset_id=dataset_id,
            dataset_sha256=dataset_sha256,
            evaluation_run_id=evaluation_run_id,
            retriever_name=retriever_name,
            retriever_version=retriever_version,
            retrieval_configuration_version=embedding_configuration_key,
            query_normalization_version=query_normalization_version,
            metric_definition_version=metric_definition_version,
            evaluation_runner_version=evaluation_runner_version,
            top_k_values=top_k_values,
            relevance_threshold=relevance_threshold,
            results_by_query=results_by_query,
            query_metadata=query_metadata,
            metrics=metrics,
            failures=failures,
        )
        artifact_bytes = canonical_bytes(artifact)
        artifact_sha256 = compute_artifact_checksum(artifact)
    except Exception as exc:
        raise RetrievalEvaluationError("artifact_serialization_failed", "the vector evaluation artifact could not be serialized") from exc

    storage_path = build_evaluation_artifact_storage_path(
        organization_id=organization_id,
        dataset_id=dataset_id,
        evaluation_run_id=evaluation_run_id,
        retriever_name=retriever_name,
        retriever_version=retriever_version,
        artifact_sha256=artifact_sha256,
    )

    return EvaluationPipelineOutcome(
        results_payload=results_payload,
        metrics_payload=metrics_payload,
        failures_payload=failures_payload,
        artifact_bytes=artifact_bytes,
        artifact_sha256=artifact_sha256,
        storage_path=storage_path,
    )


def _compare_exact_vs_indexed(exact_candidates: list, indexed_candidates: list) -> dict:
    exact_ids_by_k = {k: {c.corpus_item_id for c in exact_candidates[:k]} for k in K_VALUES}
    indexed_ids_by_k = {k: [c.corpus_item_id for c in indexed_candidates[:k]] for k in K_VALUES}
    recall_by_k = {}
    for k in K_VALUES:
        exact_set = exact_ids_by_k[k]
        if not exact_set:
            recall_by_k[k] = 1.0  # no exact neighbors to miss -> vacuously perfect agreement
            continue
        overlap = sum(1 for cid in indexed_ids_by_k[k] if cid in exact_set)
        recall_by_k[k] = overlap / len(exact_set)

    exact_order = [c.corpus_item_id for c in exact_candidates]
    indexed_order = [c.corpus_item_id for c in indexed_candidates]
    common = [cid for cid in indexed_order if cid in set(exact_order)]
    if len(common) >= 2:
        exact_ranks = {cid: i for i, cid in enumerate(exact_order)}
        agreements = sum(1 for a, b in zip(common, common[1:]) if exact_ranks[a] < exact_ranks[b])
        rank_agreement = agreements / (len(common) - 1)
    else:
        rank_agreement = 1.0

    return {"recall_by_k": recall_by_k, "rank_agreement": rank_agreement}


def _compute_exact_vs_indexed_metrics(per_query: list[dict]) -> list[MetricRow]:
    if not per_query:
        return []
    n = len(per_query)
    rows: list[MetricRow] = []
    for k in K_VALUES:
        avg_recall = sum(q["recall_by_k"][k] for q in per_query) / n
        rows.append(MetricRow("exact_vs_indexed", None, f"exact_vs_indexed_recall_at_{k}", avg_recall, n))
    avg_rank_agreement = sum(q["rank_agreement"] for q in per_query) / n
    rows.append(MetricRow("exact_vs_indexed", None, "exact_vs_indexed_rank_agreement", avg_rank_agreement, n))
    return rows
