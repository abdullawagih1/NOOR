"""
Ties job context, candidate recall, scoring, metrics, failure analysis, and
artifact construction/upload together for one retrieval_evaluation job
(ADR 0015). Runs inside the existing WorkerLoop's heartbeat-thread window
exactly like app/chunking/pipeline.py.
"""
from __future__ import annotations

import hashlib
import math

from app.pdf_extraction.artifact_storage import upload_and_verify_artifact
from app.pdf_extraction.errors import ExtractionError
from app.retrieval.artifact import build_canonical_evaluation_artifact
from app.retrieval.checksums import canonical_bytes, compute_artifact_checksum
from app.retrieval.config import ARTIFACT_MEDIA_TYPE, ARTIFACT_STORAGE_BUCKET
from app.retrieval.errors import RetrievalEvaluationError
from app.retrieval.failure_analysis import detect_failures
from app.retrieval.metrics import QueryEvaluation, compute_all_metrics
from app.retrieval.retriever import LexicalRetriever, RetrievalConfiguration, RetrievalCandidate


def build_evaluation_artifact_storage_path(
    *, organization_id: str, dataset_id: str, evaluation_run_id: str, retriever_name: str, retriever_version: str, artifact_sha256: str
) -> str:
    return (
        f"{organization_id}/retrieval-evaluation/{dataset_id}/"
        f"{retriever_name}-{retriever_version}/{evaluation_run_id}/{artifact_sha256}.json"
    )


class EvaluationPipelineOutcome:
    def __init__(
        self,
        *,
        results_payload: list[dict],
        metrics_payload: list[dict],
        failures_payload: list[dict],
        artifact_bytes: bytes,
        artifact_sha256: str,
        storage_path: str,
    ) -> None:
        self.results_payload = results_payload
        self.metrics_payload = metrics_payload
        self.failures_payload = failures_payload
        self.artifact_bytes = artifact_bytes
        self.artifact_sha256 = artifact_sha256
        self.storage_path = storage_path
        self.storage_bucket = ARTIFACT_STORAGE_BUCKET
        self.media_type = ARTIFACT_MEDIA_TYPE


def run_evaluation_pipeline(
    *,
    organization_id: str,
    dataset_id: str,
    dataset_sha256: str,
    evaluation_run_id: str,
    query_rows: list[dict],
    judgment_rows: list[dict],
    fetch_candidates,  # Callable[[str], list[CandidateRow]] -- normalized_query_text -> rows, already bound to this dataset
    retriever_name: str,
    retriever_version: str,
    retrieval_configuration_version: str,
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
        configuration_version=retrieval_configuration_version,
        top_k=max_k,
    )

    judgments_by_query: dict[str, dict[str, int]] = {}
    for row in judgment_rows:
        judgments_by_query.setdefault(str(row["query_id"]), {})[str(row["corpus_item_id"])] = int(row["relevance_grade"])

    results_by_query: dict[str, list[RetrievalCandidate]] = {}
    evaluations: list[QueryEvaluation] = []
    query_metadata: dict[str, dict] = {}

    for row in query_rows:
        query_id = str(row["out_query_id"])
        normalized_query_text = row["out_normalized_query_text"] or ""

        retriever = LexicalRetriever(fetch_candidates=fetch_candidates)
        try:
            candidates = retriever.retrieve(normalized_query_text, configuration)
        except Exception as exc:
            raise RetrievalEvaluationError("candidate_fetch_failed", "could not fetch retrieval candidates for a query") from exc

        results_by_query[query_id] = candidates
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
                ranked_corpus_item_ids=tuple(c.corpus_item_id for c in candidates),
                relevance_by_corpus_item=relevance,
                total_relevant_count=total_relevant,
            )
        )

    metrics = compute_all_metrics(evaluations, relevance_threshold)
    failures = detect_failures(evaluations, relevance_threshold)

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
            retrieval_configuration_version=retrieval_configuration_version,
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
        raise RetrievalEvaluationError("artifact_serialization_failed", "the evaluation artifact could not be serialized") from exc

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


def _build_results_payload(
    results_by_query: dict[str, list[RetrievalCandidate]],
    evaluations_by_id: dict[str, QueryEvaluation],
    relevance_threshold: int,
) -> list[dict]:
    payload: list[dict] = []
    for query_id, candidates in results_by_query.items():
        evaluation = evaluations_by_id[query_id]
        first_relevant_rank: int | None = None
        for candidate in candidates:
            grade = evaluation.grade_of(candidate.corpus_item_id)
            is_hit = grade >= relevance_threshold
            if is_hit and first_relevant_rank is None:
                first_relevant_rank = candidate.rank
            reciprocal_rank_contribution = (1.0 / candidate.rank) if (is_hit and candidate.rank == first_relevant_rank) else 0.0
            dcg_contribution = (2**grade - 1) / math.log2(candidate.rank + 1)
            result_checksum_input = f"{query_id}:{candidate.corpus_item_id}:{candidate.rank}:{candidate.final_score}:{grade}"
            payload.append(
                {
                    "query_id": query_id,
                    "corpus_item_id": candidate.corpus_item_id,
                    "rank": candidate.rank,
                    "final_score": candidate.final_score,
                    "score_components": candidate.score_components,
                    "matched_terms": list(candidate.matched_terms),
                    "relevance_grade": grade,
                    "reciprocal_rank_contribution": reciprocal_rank_contribution,
                    "dcg_contribution": dcg_contribution,
                    "is_hit": is_hit,
                    "result_checksum": _sha256_hex(result_checksum_input),
                }
            )
    return payload


def _sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def upload_evaluation_artifact(*, supabase_url: str, service_role_key: str, outcome: EvaluationPipelineOutcome, http_client=None) -> None:
    try:
        upload_and_verify_artifact(
            supabase_url=supabase_url,
            service_role_key=service_role_key,
            storage_bucket=outcome.storage_bucket,
            storage_path=outcome.storage_path,
            content_bytes=outcome.artifact_bytes,
            media_type=outcome.media_type,
            http_client=http_client,
        )
    except ExtractionError as exc:
        code = "artifact_checksum_mismatch" if exc.error_code == "artifact_checksum_mismatch" else "artifact_upload_failed"
        raise RetrievalEvaluationError(code, exc.message_safe) from exc
