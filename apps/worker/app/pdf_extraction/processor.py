"""
The real extraction Processor (mission §24) — matches the same
`Processor` contract as `app/processing.py::noop_processor`
(`(job, heartbeat) -> ProcessingOutcome`), so it plugs into the existing,
already-proven `WorkerLoop` (Sprint 1.2A) with zero changes to that class.

`make_extraction_processor()` is a factory, not the processor itself,
because it needs an `OrchestrationClient` (DB/RPC access) and Settings
(Supabase URL/key, pinned versions) that the bare `(job, heartbeat)`
signature has no way to carry — the closure captures them once at Worker
startup (see app/main.py's lifespan handler).
"""
from __future__ import annotations

import logging
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
from typing import Callable

from app.orchestration_client import ClaimedJob, OrchestrationClient, OrchestrationError
from app.pdf_extraction.config import ExtractionConfiguration
from app.pdf_extraction.errors import ExtractionError
from app.pdf_extraction.extractor import PyPdfExtractor
from app.pdf_extraction.pipeline import ExtractionPipelineOutcome, run_extraction_pipeline
from app.processing import Processor, ProcessingOutcome

logger = logging.getLogger("noor.worker.pdf_extraction")


def make_extraction_processor(
    client: OrchestrationClient,
    *,
    worker_instance_id: str,
    supabase_url: str,
    service_role_key: str,
    pipeline_version: str,
    configuration_version: str,
    extractor_name: str,
    extractor_version: str,
    max_seconds: float | None,
    temp_directory: str | None = None,
) -> Processor:
    extractor = PyPdfExtractor(extractor_version)
    configuration = ExtractionConfiguration(version=configuration_version)

    def _extract(job: ClaimedJob, source_doc: dict) -> ExtractionPipelineOutcome:
        return run_extraction_pipeline(
            supabase_url=supabase_url,
            service_role_key=service_role_key,
            source_storage_bucket=source_doc["storage_bucket"],
            source_storage_path=source_doc["storage_path"],
            source_sha256=source_doc["sha256"],
            source_size_bytes=source_doc["size_bytes"],
            source_document_id=str(job.source_document_id),
            organization_id=str(job.organization_id),
            pipeline_version=pipeline_version,
            configuration_version=configuration_version,
            extractor=extractor,
            configuration=configuration,
            temp_directory=temp_directory,
        )

    def process(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        try:
            source_doc = client.get_source_document(job.source_document_id)
        except OrchestrationError as exc:
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="source_object_missing",
                error_class="source_object_missing",
                error_message_safe="the registered source document could not be read",
            )

        if source_doc.get("status") not in ("verified", "registered"):
            return ProcessingOutcome(
                kind="terminal_failure",
                error_code="source_document_not_verified",
                error_class="source_document_not_verified",
                error_message_safe="the source document is not in a verified/registered state",
            )

        extraction_run_id: uuid.UUID | None = None
        try:
            try:
                run_row = client.create_extraction_run(
                    job.job_id,
                    worker_instance_id,
                    job.lease_token,
                    source_doc["sha256"],
                    source_doc["size_bytes"],
                    pipeline_version,
                    configuration_version,
                    extractor_name,
                    extractor_version,
                    job.correlation_id,
                )
            except OrchestrationError as exc:
                # The DB function's own defense-in-depth checks (source not
                # verified/registered, checksum/size mismatch against the
                # registered document) surface here as a generic
                # OrchestrationError — classify by message substring, the
                # same pattern the Web app's error-mapping layer uses.
                message = str(exc).lower()
                if "checksum" in message:
                    raise ExtractionError("source_checksum_mismatch", "source checksum does not match the registered document") from exc
                if "size" in message:
                    raise ExtractionError("source_size_mismatch", "source size does not match the registered document") from exc
                if "not verified or registered" in message:
                    raise ExtractionError("source_document_not_verified", "the source document is not verified or registered") from exc
                raise ExtractionError("database_finalization_failed", "could not create the extraction run") from exc

            extraction_run_id = uuid.UUID(run_row["out_extraction_run_id"])
            reused = bool(run_row.get("out_reused"))

            if reused:
                logger.info("extraction identity already succeeded, reusing run_id=%s for job_id=%s", extraction_run_id, job.job_id)
                return ProcessingOutcome(
                    kind="succeeded",
                    result_summary={
                        "processor": extractor_name,
                        "pipeline_version": pipeline_version,
                        "extraction_run_id": str(extraction_run_id),
                        "reused": True,
                    },
                )

            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(_extract, job, source_doc)
                try:
                    outcome = future.result(timeout=max_seconds)
                except FutureTimeoutError as exc:
                    # The extraction thread keeps running to completion in
                    # the background (mission §26: "do not implement unsafe
                    # thread termination") — its eventual result is simply
                    # discarded; this attempt is reported as timed out now.
                    raise ExtractionError("extraction_timeout", "extraction exceeded the configured time limit") from exc

            heartbeat()

            pages_payload = [
                {
                    "organization_id": str(job.organization_id),
                    "extraction_run_id": str(extraction_run_id),
                    "source_document_id": str(job.source_document_id),
                    "page_number": p.page_number,
                    "width_points": p.width_points,
                    "height_points": p.height_points,
                    "rotation_degrees": p.rotation_degrees,
                    "raw_text": p.raw_text,
                    "normalized_text": p.normalized_text,
                    "character_count": p.character_count,
                    "word_count": p.word_count,
                    "is_blank": p.is_blank,
                    "suspected_scanned": p.suspected_scanned,
                    "extraction_status": p.extraction_status,
                    "warnings": p.warnings,
                    "page_checksum": p.page_checksum,
                }
                for p in outcome.result.pages
            ]
            try:
                client.insert_extraction_pages(pages_payload)

                finalize_row = client.finalize_extraction_run(
                    extraction_run_id,
                    job.job_id,
                    worker_instance_id,
                    job.lease_token,
                    outcome.result.page_count,
                    outcome.storage_bucket,
                    outcome.storage_path,
                    outcome.artifact_sha256,
                    len(outcome.artifact_bytes),
                    outcome.media_type,
                    document_metadata=outcome.result.document_metadata,
                    pages_with_text=outcome.result.pages_with_text,
                    blank_page_count=outcome.result.blank_page_count,
                    suspected_scanned_page_count=outcome.result.suspected_scanned_page_count,
                    total_character_count=outcome.result.total_character_count,
                    total_word_count=outcome.result.total_word_count,
                    warning_count=outcome.result.warning_count,
                    warnings=outcome.result.warnings,
                    correlation_id=job.correlation_id,
                )
            except OrchestrationError as exc:
                raise ExtractionError("database_finalization_failed", "could not persist pages or finalize the extraction run") from exc

            return ProcessingOutcome(
                kind="succeeded",
                result_summary={
                    "processor": extractor_name,
                    "pipeline_version": pipeline_version,
                    "extraction_run_id": str(extraction_run_id),
                    "artifact_sha256": outcome.artifact_sha256,
                    "page_count": outcome.result.page_count,
                    "status": finalize_row.get("out_status", "succeeded"),
                },
            )
        except ExtractionError as exc:
            logger.warning("extraction failed job_id=%s error_code=%s", job.job_id, exc.error_code)
            if extraction_run_id is not None:
                try:
                    client.fail_extraction_run(
                        extraction_run_id,
                        job.job_id,
                        worker_instance_id,
                        job.lease_token,
                        exc.error_code,
                        exc.error_class or exc.error_code,
                        exc.message_safe,
                        job.correlation_id,
                    )
                except OrchestrationError:
                    logger.exception("failed to record extraction-run failure for job_id=%s (lease likely lost)", job.job_id)

            return ProcessingOutcome(
                kind="retryable_failure" if exc.retryable else "terminal_failure",
                error_code=exc.error_code,
                error_class=exc.error_class,
                error_message_safe=exc.message_safe,
            )

    return process
