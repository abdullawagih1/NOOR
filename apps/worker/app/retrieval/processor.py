"""
The real retrieval-evaluation Processor (Sprint 1-E1, ADR 0015) — matches
the same `Processor` contract as every other processor in this Worker
((job, heartbeat) -> ProcessingOutcome). Unlike chunking (one job, one
document), one job here is one whole evaluation run against a *frozen
dataset* spanning arbitrarily many documents.

`make_retrieval_evaluation_processor()` is a factory, not the processor
itself, for the same reason `make_chunking_processor()` is: it needs an
`OrchestrationClient` and pinned configuration the bare
`(job, heartbeat) -> ProcessingOutcome` signature has no way to carry.
"""
from __future__ import annotations

import logging
import uuid
from typing import Callable

from app.orchestration_client import ClaimedJob, OrchestrationClient, OrchestrationError
from app.processing import Processor, ProcessingOutcome
from app.retrieval.errors import RetrievalEvaluationError
from app.retrieval.pipeline import run_evaluation_pipeline, upload_evaluation_artifact
from app.retrieval.scoring import CandidateRow

logger = logging.getLogger("noor.worker.retrieval")


def make_retrieval_evaluation_processor(
    client: OrchestrationClient,
    *,
    worker_instance_id: str,
    supabase_url: str,
    service_role_key: str,
) -> Processor:
    def process(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        try:
            context_rows = client.get_retrieval_evaluation_job_context(job.job_id, worker_instance_id, job.lease_token)
        except OrchestrationError as exc:
            message = str(exc).lower()
            if "no longer frozen" in message:
                return ProcessingOutcome(
                    kind="terminal_failure",
                    error_code="dataset_not_frozen",
                    error_class="dataset_not_frozen",
                    error_message_safe="the evaluation dataset is no longer frozen",
                )
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="evaluation_job_context_not_found",
                error_class="evaluation_job_context_not_found",
                error_message_safe="this job's evaluation context could not be read",
            )

        if not context_rows:
            return ProcessingOutcome(
                kind="terminal_failure",
                error_code="evaluation_job_context_not_found",
                error_class="evaluation_job_context_not_found",
                error_message_safe="this dataset has no active queries to evaluate",
            )

        first_row = context_rows[0]
        dataset_id = uuid.UUID(str(first_row["out_dataset_id"]))
        run_id = uuid.UUID(str(first_row["out_run_id"]))

        try:
            judgment_rows = client.get_relevance_judgments(dataset_id)
        except OrchestrationError:
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="evaluation_job_context_not_found",
                error_class="evaluation_job_context_not_found",
                error_message_safe="this dataset's relevance judgments could not be read",
            )

        def fetch_candidates(normalized_query_text: str) -> list[CandidateRow]:
            rows = client.get_retrieval_candidates(job.job_id, worker_instance_id, job.lease_token, dataset_id, normalized_query_text)
            return [
                CandidateRow(
                    corpus_item_id=str(r["out_corpus_item_id"]),
                    full_text_rank=float(r["out_full_text_rank"]),
                    normalized_search_text=r["out_normalized_search_text"] or "",
                    token_count=int(r["out_token_count"] or 0),
                    display_order=int(r["out_display_order"]),
                    chunk_checksum=r["out_chunk_checksum"],
                )
                for r in rows
            ]

        heartbeat()

        try:
            outcome = run_evaluation_pipeline(
                organization_id=str(job.organization_id),
                dataset_id=str(dataset_id),
                dataset_sha256=first_row["out_dataset_sha256"],
                evaluation_run_id=str(run_id),
                query_rows=context_rows,
                judgment_rows=judgment_rows,
                fetch_candidates=fetch_candidates,
                retriever_name=first_row["out_retriever_name"],
                retriever_version=first_row["out_retriever_version"],
                retrieval_configuration_version=first_row["out_retrieval_configuration_version"],
                query_normalization_version=first_row["out_query_normalization_version"],
                metric_definition_version=first_row["out_metric_definition_version"],
                evaluation_runner_version="1",
                top_k_values=list(first_row["out_top_k_values"]),
                relevance_threshold=int(first_row["out_relevance_threshold"]),
            )
            heartbeat()
            upload_evaluation_artifact(supabase_url=supabase_url, service_role_key=service_role_key, outcome=outcome)
        except RetrievalEvaluationError as exc:
            logger.warning("retrieval evaluation failed job_id=%s error_code=%s", job.job_id, exc.error_code)
            try:
                client.fail_retrieval_evaluation_run(
                    run_id, job.job_id, worker_instance_id, job.lease_token,
                    exc.error_code, exc.error_class or exc.error_code, exc.message_safe, job.correlation_id,
                )
            except OrchestrationError:
                logger.exception("failed to record evaluation-run failure for job_id=%s (lease likely lost)", job.job_id)
            return ProcessingOutcome(
                kind="retryable_failure" if exc.retryable else "terminal_failure",
                error_code=exc.error_code,
                error_class=exc.error_class,
                error_message_safe=exc.message_safe,
            )

        try:
            finalize_row = client.finalize_retrieval_evaluation_run(
                run_id,
                job.job_id,
                worker_instance_id,
                job.lease_token,
                outcome.results_payload,
                outcome.metrics_payload,
                outcome.failures_payload,
                outcome.storage_bucket,
                outcome.storage_path,
                outcome.artifact_sha256,
                len(outcome.artifact_bytes),
                outcome.media_type,
                correlation_id=job.correlation_id,
            )
        except OrchestrationError:
            try:
                client.fail_retrieval_evaluation_run(
                    run_id, job.job_id, worker_instance_id, job.lease_token,
                    "database_finalization_failed", "database_finalization_failed",
                    "could not finalize the evaluation run", job.correlation_id,
                )
            except OrchestrationError:
                logger.exception("failed to record evaluation-run failure after finalize error for job_id=%s", job.job_id)
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="database_finalization_failed",
                error_class="database_finalization_failed",
                error_message_safe="could not finalize the evaluation run",
            )

        return ProcessingOutcome(
            kind="succeeded",
            result_summary={
                "processor": "noor-lexical-baseline",
                "evaluation_run_id": str(run_id),
                "result_count": finalize_row.get("out_result_count", len(outcome.results_payload)),
                "artifact_sha256": outcome.artifact_sha256,
                "status": finalize_row.get("out_status", "succeeded"),
            },
        )

    return process
