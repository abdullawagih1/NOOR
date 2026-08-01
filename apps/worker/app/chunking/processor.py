"""
The real chunking Processor (Sprint 1-D3, ADR 0014) — matches the same
`Processor` contract as every other processor in this Worker
((job, heartbeat) -> ProcessingOutcome), so it plugs into the existing
WorkerLoop with zero changes to that class. Unlike OCR (page-scoped, ADR
0012), one job here is one whole chunking-eligible *document* (ADR 0014).

`make_chunking_processor()` is a factory, not the processor itself, for
the same reason make_extraction_processor()/make_ocr_processor() are: it
needs an `OrchestrationClient` and pinned configuration the bare
`(job, heartbeat)` signature has no way to carry.
"""
from __future__ import annotations

import logging
import uuid
from typing import Callable

from app.chunking.artifact import chunks_to_rpc_payload
from app.chunking.errors import ChunkingError
from app.chunking.manifest import build_input_manifest, compute_input_manifest_sha256
from app.chunking.pipeline import build_pages_from_context_rows, run_chunking_pipeline, upload_chunking_artifact
from app.chunking.tokenizer import tokenizer_identity
from app.orchestration_client import ClaimedJob, OrchestrationClient, OrchestrationError
from app.processing import Processor, ProcessingOutcome

logger = logging.getLogger("noor.worker.chunking")


def make_chunking_processor(
    client: OrchestrationClient,
    *,
    worker_instance_id: str,
    supabase_url: str,
    service_role_key: str,
    pipeline_version: str,
    configuration_version: str,
    normalization_version: str,
) -> Processor:
    tokenizer_name, tokenizer_version = tokenizer_identity()

    def process(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        try:
            context_rows = client.get_chunking_job_context(job.job_id, worker_instance_id, job.lease_token)
        except OrchestrationError as exc:
            message = str(exc).lower()
            if "not chunking-eligible" in message or "no succeeded extraction run" in message:
                return ProcessingOutcome(
                    kind="terminal_failure",
                    error_code="document_not_chunking_eligible",
                    error_class="document_not_chunking_eligible",
                    error_message_safe="this document is not chunking-eligible",
                )
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="chunking_job_context_not_found",
                error_class="chunking_job_context_not_found",
                error_message_safe="this job's chunking context could not be read",
            )

        if not context_rows:
            return ProcessingOutcome(
                kind="terminal_failure",
                error_code="document_not_chunking_eligible",
                error_class="document_not_chunking_eligible",
                error_message_safe="this document has no ready pages to chunk",
            )

        try:
            source_doc = client.get_source_document(job.source_document_id)
        except OrchestrationError:
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="chunking_job_context_not_found",
                error_class="chunking_job_context_not_found",
                error_message_safe="the registered source document could not be read",
            )

        first_row = context_rows[0]
        extraction_run_id = uuid.UUID(str(first_row["out_extraction_run_id"]))
        extraction_review_id = uuid.UUID(str(first_row["out_extraction_review_id"]))
        ocr_request_id = uuid.UUID(str(first_row["out_ocr_request_id"])) if first_row.get("out_ocr_request_id") else None
        ocr_review_id = uuid.UUID(str(first_row["out_ocr_review_id"])) if first_row.get("out_ocr_review_id") else None

        pages = build_pages_from_context_rows(context_rows)
        manifest = build_input_manifest(pages)
        manifest_sha256 = compute_input_manifest_sha256(manifest)

        try:
            run_row = client.create_chunking_run(
                job.job_id,
                worker_instance_id,
                job.lease_token,
                extraction_run_id,
                extraction_review_id,
                source_doc["sha256"],
                manifest,
                manifest_sha256,
                pipeline_version,
                configuration_version,
                normalization_version,
                tokenizer_name,
                tokenizer_version,
                ocr_request_id=ocr_request_id,
                ocr_review_id=ocr_review_id,
                correlation_id=job.correlation_id,
            )
        except OrchestrationError as exc:
            message = str(exc).lower()
            if "no longer chunking-eligible" in message:
                return ProcessingOutcome(
                    kind="terminal_failure",
                    error_code="document_not_chunking_eligible",
                    error_class="document_not_chunking_eligible",
                    error_message_safe="this document is no longer chunking-eligible",
                )
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="database_finalization_failed",
                error_class="database_finalization_failed",
                error_message_safe="could not create the chunking run",
            )

        chunking_run_id = uuid.UUID(str(run_row["out_chunking_run_id"]))
        reused = bool(run_row.get("out_reused"))

        if reused:
            logger.info("chunking identity already succeeded, reusing chunking_run_id=%s for job_id=%s", chunking_run_id, job.job_id)
            return ProcessingOutcome(
                kind="succeeded",
                result_summary={
                    "processor": "controlled-page-aware-chunking",
                    "pipeline_version": pipeline_version,
                    "chunking_run_id": str(chunking_run_id),
                    "reused": True,
                },
            )

        heartbeat()

        try:
            outcome = run_chunking_pipeline(
                pages=pages,
                source_document_id=str(job.source_document_id),
                source_sha256=source_doc["sha256"],
                extraction_run_id=str(extraction_run_id),
                input_manifest=manifest,
                input_manifest_sha256=manifest_sha256,
                pipeline_version=pipeline_version,
                configuration_version=configuration_version,
                normalization_version=normalization_version,
                tokenizer_name=tokenizer_name,
                tokenizer_version=tokenizer_version,
                organization_id=str(job.organization_id),
            )
            heartbeat()
            upload_chunking_artifact(supabase_url=supabase_url, service_role_key=service_role_key, outcome=outcome)
        except ChunkingError as exc:
            logger.warning("chunking failed job_id=%s error_code=%s", job.job_id, exc.error_code)
            try:
                client.fail_chunking_run(
                    chunking_run_id, job.job_id, worker_instance_id, job.lease_token,
                    exc.error_code, exc.error_class or exc.error_code, exc.message_safe, job.correlation_id,
                )
            except OrchestrationError:
                logger.exception("failed to record chunking-run failure for job_id=%s (lease likely lost)", job.job_id)
            return ProcessingOutcome(
                kind="retryable_failure" if exc.retryable else "terminal_failure",
                error_code=exc.error_code,
                error_class=exc.error_class,
                error_message_safe=exc.message_safe,
            )

        try:
            finalize_row = client.finalize_chunking_run(
                chunking_run_id,
                job.job_id,
                worker_instance_id,
                job.lease_token,
                chunks_to_rpc_payload(outcome.chunks),
                outcome.metrics,
                outcome.warnings,
                outcome.storage_bucket,
                outcome.storage_path,
                outcome.artifact_sha256,
                len(outcome.artifact_bytes),
                outcome.media_type,
                correlation_id=job.correlation_id,
            )
        except OrchestrationError:
            try:
                client.fail_chunking_run(
                    chunking_run_id, job.job_id, worker_instance_id, job.lease_token,
                    "database_finalization_failed", "database_finalization_failed",
                    "could not finalize the chunking run", job.correlation_id,
                )
            except OrchestrationError:
                logger.exception("failed to record chunking-run failure after finalize error for job_id=%s", job.job_id)
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="database_finalization_failed",
                error_class="database_finalization_failed",
                error_message_safe="could not finalize the chunking run",
            )

        return ProcessingOutcome(
            kind="succeeded",
            result_summary={
                "processor": "controlled-page-aware-chunking",
                "pipeline_version": pipeline_version,
                "chunking_run_id": str(chunking_run_id),
                "chunk_count": finalize_row.get("out_chunk_count", len(outcome.chunks)),
                "artifact_sha256": outcome.artifact_sha256,
                "status": finalize_row.get("out_status", "succeeded"),
            },
        )

    return process
