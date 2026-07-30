"""
The real OCR Processor (ADR 0012) — matches the same `Processor` contract
as every other processor in this Worker (`(job, heartbeat) ->
ProcessingOutcome`), so it plugs into the existing WorkerLoop with zero
changes to that class. Mirrors app/pdf_extraction/processor.py's shape
exactly, one layer deeper: one job here is one OCR-eligible *page*, never
a whole document (ADR 0012).

`make_ocr_processor()` is a factory, not the processor itself, for the
same reason make_extraction_processor() is: it needs an
`OrchestrationClient` and pinned configuration that the bare
`(job, heartbeat)` signature has no way to carry.
"""
from __future__ import annotations

import logging
import uuid
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
from pathlib import Path
from typing import Callable

from app.ocr.config import OcrConfiguration
from app.ocr.errors import OcrError
from app.ocr.models import RenderedPage
from app.ocr.pipeline import OcrPipelineOutcome, recognize_and_build_artifact, render_source_page
from app.ocr.provider import TesseractProvider
from app.ocr.renderer import Pypdfium2Renderer
from app.orchestration_client import ClaimedJob, OrchestrationClient, OrchestrationError
from app.processing import Processor, ProcessingOutcome

logger = logging.getLogger("noor.worker.ocr")


def make_ocr_processor(
    client: OrchestrationClient,
    *,
    worker_instance_id: str,
    supabase_url: str,
    service_role_key: str,
    pipeline_version: str,
    render_dpi: int,
    render_color_mode: str,
    render_image_format: str,
    render_configuration_version: str,
    ocr_configuration_version: str,
    tessdata_dir: Path,
    max_seconds: float | None,
    temp_directory: str | None = None,
) -> Processor:
    renderer = Pypdfium2Renderer()
    provider = TesseractProvider()
    configuration = OcrConfiguration(version=ocr_configuration_version)

    def _render(job: ClaimedJob, source_doc: dict, ocr_context: dict) -> RenderedPage:
        return render_source_page(
            supabase_url=supabase_url,
            service_role_key=service_role_key,
            source_storage_bucket=source_doc["storage_bucket"],
            source_storage_path=source_doc["storage_path"],
            source_sha256=source_doc["sha256"],
            source_size_bytes=source_doc["size_bytes"],
            page_number=ocr_context["page_number"],
            renderer=renderer,
            render_dpi=render_dpi,
            render_color_mode=render_color_mode,
            render_image_format=render_image_format,
            temp_directory=temp_directory,
        )

    def _recognize(rendered: RenderedPage, job: ClaimedJob, source_doc: dict, ocr_context: dict) -> OcrPipelineOutcome:
        return recognize_and_build_artifact(
            rendered=rendered,
            source_document_id=str(job.source_document_id),
            source_sha256=source_doc["sha256"],
            organization_id=str(job.organization_id),
            extraction_run_id=str(ocr_context["extraction_run_id"]),
            page_number=ocr_context["page_number"],
            native_page_checksum=ocr_context["native_page_checksum"],
            pipeline_version=pipeline_version,
            renderer_name=ocr_context["renderer_name"],
            renderer_version=renderer.version,
            render_configuration_version=render_configuration_version,
            render_dpi=render_dpi,
            render_color_mode=render_color_mode,
            render_image_format=render_image_format,
            provider=provider,
            model_identifier=ocr_context["model_identifier"],
            model_version=ocr_context["model_version"],
            ocr_configuration_version=ocr_context["ocr_configuration_version"],
            language_hints=list(ocr_context["language_hints"]),
            configuration=configuration,
            tessdata_dir=tessdata_dir,
            supabase_url=supabase_url,
            service_role_key=service_role_key,
        )

    def process(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        try:
            ocr_context = client.get_ocr_job_context(job.job_id)
        except OrchestrationError:
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="ocr_request_page_not_found",
                error_class="ocr_request_page_not_found",
                error_message_safe="this job's OCR request page could not be read",
            )

        try:
            source_doc = client.get_source_document(job.source_document_id)
        except OrchestrationError:
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="source_object_missing",
                error_class="source_object_missing",
                error_message_safe="the registered source document could not be read",
            )

        ocr_run_id: uuid.UUID | None = None
        try:
            # Phase 1: render first. The OCR identity (migration 0011,
            # create_document_ocr_run's p_page_image_sha256 parameter) can
            # only be known once the page has actually been rasterized — a
            # render failure never creates a document_ocr_runs row at all
            # (there is no identity to attach it to), so it surfaces purely
            # as a job failure/retry, same as a claim-time validation error.
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(_render, job, source_doc, ocr_context)
                try:
                    rendered = future.result(timeout=max_seconds)
                except FutureTimeoutError as exc:
                    # Mirrors the extraction processor's own choice (mission
                    # §26: "do not implement unsafe thread termination") —
                    # the render thread keeps running to completion in the
                    # background; its eventual result is discarded.
                    raise OcrError("ocr_timeout", "page rendering exceeded the configured time limit") from exc

            heartbeat()

            # Phase 2: create (or idempotently reuse) the OCR run now that
            # the real page-image checksum is known.
            try:
                run_row = client.create_ocr_run(
                    job.job_id,
                    worker_instance_id,
                    job.lease_token,
                    source_doc["sha256"],
                    ocr_context["native_page_checksum"],
                    ocr_context["renderer_name"],
                    renderer.version,
                    ocr_context["render_configuration_version"],
                    render_dpi,
                    render_color_mode,
                    render_image_format,
                    rendered.checksum,
                    len(rendered.image_bytes),
                    ocr_context["provider_name"],
                    provider.version,
                    ocr_context["model_identifier"],
                    ocr_context["model_version"],
                    ocr_context["ocr_configuration_version"],
                    list(ocr_context["language_hints"]),
                    job.correlation_id,
                )
            except OrchestrationError as exc:
                message = str(exc).lower()
                if "checksum" in message:
                    raise OcrError("source_checksum_mismatch", "source checksum does not match the registered document") from exc
                if "no longer eligible" in message:
                    raise OcrError("ocr_request_not_eligible", "this OCR request is no longer eligible for processing") from exc
                if "not succeeded" in message:
                    raise OcrError("extraction_run_not_succeeded", "the underlying extraction run is no longer succeeded") from exc
                raise OcrError("database_finalization_failed", "could not create the OCR run") from exc

            ocr_run_id = uuid.UUID(run_row["out_ocr_run_id"])
            reused = bool(run_row.get("out_reused"))

            if reused:
                logger.info("OCR identity already succeeded, reusing ocr_run_id=%s for job_id=%s", ocr_run_id, job.job_id)
                return ProcessingOutcome(
                    kind="succeeded",
                    result_summary={
                        "processor": "tesseract",
                        "pipeline_version": pipeline_version,
                        "ocr_run_id": str(ocr_run_id),
                        "page_number": ocr_context["page_number"],
                        "reused": True,
                    },
                )

            # Phase 3: only now — never before an identity is confirmed
            # fresh — run OCR recognition and build/upload the artifact.
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(_recognize, rendered, job, source_doc, ocr_context)
                try:
                    outcome = future.result(timeout=max_seconds)
                except FutureTimeoutError as exc:
                    raise OcrError("ocr_timeout", "OCR exceeded the configured time limit") from exc

            heartbeat()

            try:
                finalize_row = client.finalize_ocr_page(
                    ocr_run_id,
                    job.job_id,
                    worker_instance_id,
                    job.lease_token,
                    outcome.result.raw_text,
                    outcome.result.normalized_text,
                    outcome.result.character_count,
                    outcome.result.word_count,
                    outcome.result.text_checksum,
                    outcome.result.confidence_summary,
                    outcome.result.warnings,
                    outcome.result.provider_metadata_safe,
                    outcome.storage_bucket,
                    outcome.storage_path,
                    outcome.artifact_sha256,
                    len(outcome.artifact_bytes),
                    outcome.media_type,
                    correlation_id=job.correlation_id,
                )
            except OrchestrationError as exc:
                raise OcrError("database_finalization_failed", "could not finalize the OCR run") from exc

            return ProcessingOutcome(
                kind="succeeded",
                result_summary={
                    "processor": "tesseract",
                    "pipeline_version": pipeline_version,
                    "ocr_run_id": str(ocr_run_id),
                    "page_number": ocr_context["page_number"],
                    "artifact_sha256": outcome.artifact_sha256,
                    "character_count": outcome.result.character_count,
                    "status": finalize_row.get("out_status", "succeeded"),
                },
            )
        except OcrError as exc:
            logger.warning("OCR failed job_id=%s error_code=%s", job.job_id, exc.error_code)
            if ocr_run_id is not None:
                try:
                    client.fail_ocr_run(
                        ocr_run_id,
                        job.job_id,
                        worker_instance_id,
                        job.lease_token,
                        exc.error_code,
                        exc.error_class or exc.error_code,
                        exc.message_safe,
                        job.correlation_id,
                    )
                except OrchestrationError:
                    logger.exception("failed to record OCR-run failure for job_id=%s (lease likely lost)", job.job_id)

            return ProcessingOutcome(
                kind="retryable_failure" if exc.retryable else "terminal_failure",
                error_code=exc.error_code,
                error_class=exc.error_class,
                error_message_safe=exc.message_safe,
            )

    return process
