"""
Ties source download/revalidation, deterministic page rendering, OCR
recognition, and artifact construction/upload together for one
OCR-eligible page (ADR 0012: one job, one page). Runs inside the
existing WorkerLoop's heartbeat-thread window exactly like
app/pdf_extraction/pipeline.py — no manual heartbeat calls needed here.

Split into two phases, not one call, because the OCR run's identity
(mission §12.3) includes the *rendered image's* checksum — something
that can only be known after rendering, unlike extraction's identity
(known entirely from the already-registered source document). The
Worker-side dance this requires (app/ocr/processor.py):

  1. render_source_page()   -> RenderedPage (download + render only)
  2. [caller calls create_document_ocr_run() with the now-known image
     checksum — this is where identity-based idempotent reuse happens]
  3. recognize_and_build_artifact()  -> OcrPipelineOutcome (OCR + artifact,
     skipped entirely if step 2 reused an existing succeeded run)

The rendered page image lives only in memory for the duration of this
process (app/ocr/renderer.py) — it is never written to Storage or local
disk, only its checksum is recorded in the artifact.
"""
from __future__ import annotations

from pathlib import Path

import httpx

from app.ocr.artifact import build_canonical_ocr_artifact
from app.ocr.artifact_storage import build_ocr_artifact_storage_path
from app.ocr.checksums import canonical_artifact_bytes, compute_artifact_checksum
from app.ocr.config import ARTIFACT_MEDIA_TYPE, ARTIFACT_STORAGE_BUCKET, OcrConfiguration
from app.ocr.errors import OcrError
from app.ocr.models import OcrPageResult, RenderedPage
from app.ocr.provider import OcrProvider
from app.ocr.renderer import PdfPageRenderer
from app.pdf_extraction.artifact_storage import upload_and_verify_artifact
from app.pdf_extraction.errors import ExtractionError
from app.pdf_extraction.source_download import download_source_to_temp_file


class OcrPipelineOutcome:
    def __init__(
        self, rendered: RenderedPage, result: OcrPageResult, artifact_bytes: bytes, artifact_sha256: str, storage_path: str
    ) -> None:
        self.rendered = rendered
        self.result = result
        self.artifact_bytes = artifact_bytes
        self.artifact_sha256 = artifact_sha256
        self.storage_path = storage_path
        self.storage_bucket = ARTIFACT_STORAGE_BUCKET
        self.media_type = ARTIFACT_MEDIA_TYPE


def render_source_page(
    *,
    supabase_url: str,
    service_role_key: str,
    source_storage_bucket: str,
    source_storage_path: str,
    source_sha256: str,
    source_size_bytes: int,
    page_number: int,
    renderer: PdfPageRenderer,
    render_dpi: int,
    render_color_mode: str,
    render_image_format: str,
    http_client: httpx.Client | None = None,
    temp_directory: str | None = None,
) -> RenderedPage:
    try:
        with download_source_to_temp_file(
            supabase_url=supabase_url,
            service_role_key=service_role_key,
            storage_bucket=source_storage_bucket,
            storage_path=source_storage_path,
            expected_sha256=source_sha256,
            expected_size_bytes=source_size_bytes,
            http_client=http_client,
            temp_directory=temp_directory,
        ) as temp_path:
            return renderer.render_page(
                temp_path, page_number, dpi=render_dpi, color_mode=render_color_mode, image_format=render_image_format
            )
    except ExtractionError as exc:
        # download_source_to_temp_file raises app.pdf_extraction.errors.ExtractionError
        # (source_object_missing/invalid_pdf_signature/source_size_mismatch/
        # source_checksum_mismatch) — re-raised as OcrError so every caller of
        # this module only ever has to handle one exception type. Both error
        # taxonomies share these exact code strings by design.
        raise OcrError(exc.error_code, exc.message_safe) from exc


def recognize_and_build_artifact(
    *,
    rendered: RenderedPage,
    source_document_id: str,
    source_sha256: str,
    organization_id: str,
    extraction_run_id: str,
    page_number: int,
    native_page_checksum: str,
    pipeline_version: str,
    renderer_name: str,
    renderer_version: str,
    render_configuration_version: str,
    render_dpi: int,
    render_color_mode: str,
    render_image_format: str,
    provider: OcrProvider,
    model_identifier: str,
    model_version: str,
    ocr_configuration_version: str,
    language_hints: list[str],
    configuration: OcrConfiguration,
    tessdata_dir: Path,
    supabase_url: str,
    service_role_key: str,
    http_client: httpx.Client | None = None,
) -> OcrPipelineOutcome:
    result = provider.recognize(
        rendered.image_bytes, language_hints=language_hints, configuration=configuration, tessdata_dir=tessdata_dir
    )

    try:
        artifact = build_canonical_ocr_artifact(
            source_document_id=source_document_id,
            source_sha256=source_sha256,
            extraction_run_id=extraction_run_id,
            page_number=page_number,
            native_page_checksum=native_page_checksum,
            renderer_name=renderer_name,
            renderer_version=renderer_version,
            render_configuration_version=render_configuration_version,
            render_dpi=render_dpi,
            render_color_mode=render_color_mode,
            render_image_format=render_image_format,
            rendered=rendered,
            provider_name=provider.name,
            provider_version=provider.version,
            model_identifier=model_identifier,
            model_version=model_version,
            ocr_configuration_version=ocr_configuration_version,
            language_hints=language_hints,
            result=result,
        )
        artifact_bytes = canonical_artifact_bytes(artifact)
        artifact_sha256 = compute_artifact_checksum(artifact)
    except OcrError:
        raise
    except Exception as exc:
        raise OcrError("artifact_serialization_failed", "the OCR artifact could not be serialized") from exc

    storage_path = build_ocr_artifact_storage_path(
        organization_id=organization_id,
        source_document_id=source_document_id,
        pipeline_version=pipeline_version,
        page_number=page_number,
        provider_name=provider.name,
        provider_version=provider.version,
        artifact_sha256=artifact_sha256,
    )

    try:
        upload_and_verify_artifact(
            supabase_url=supabase_url,
            service_role_key=service_role_key,
            storage_bucket=ARTIFACT_STORAGE_BUCKET,
            storage_path=storage_path,
            content_bytes=artifact_bytes,
            media_type=ARTIFACT_MEDIA_TYPE,
            http_client=http_client,
        )
    except ExtractionError as exc:
        code = "artifact_checksum_mismatch" if exc.error_code == "artifact_checksum_mismatch" else "artifact_upload_failed"
        raise OcrError(code, exc.message_safe) from exc

    return OcrPipelineOutcome(rendered, result, artifact_bytes, artifact_sha256, storage_path)
