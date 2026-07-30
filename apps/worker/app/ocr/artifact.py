"""
Canonical JSON OCR artifact construction — one artifact per page,
mirroring app/pdf_extraction/artifact.py one layer deeper (it additionally
records the rendering identity, since OCR input is a rendered image, not
the PDF bytes directly). Field ordering is irrelevant to determinism —
app/ocr/checksums.py's compute_artifact_checksum serializes with
sort_keys=True.

Never included: secrets, signed URLs, local temporary file paths, the
Worker's lease token, raw stack traces, or the rendered page image bytes
themselves (mission §12, §17, §38).
"""
from __future__ import annotations

from app.ocr.config import ARTIFACT_SCHEMA_VERSION
from app.ocr.models import OcrPageResult, RenderedPage


def build_canonical_ocr_artifact(
    *,
    source_document_id: str,
    source_sha256: str,
    extraction_run_id: str,
    page_number: int,
    native_page_checksum: str,
    renderer_name: str,
    renderer_version: str,
    render_configuration_version: str,
    render_dpi: int,
    render_color_mode: str,
    render_image_format: str,
    rendered: RenderedPage,
    provider_name: str,
    provider_version: str,
    model_identifier: str,
    model_version: str,
    ocr_configuration_version: str,
    language_hints: list[str],
    result: OcrPageResult,
) -> dict:
    return {
        "schema_version": ARTIFACT_SCHEMA_VERSION,
        "source": {
            "source_document_id": source_document_id,
            "source_sha256": source_sha256,
            "extraction_run_id": extraction_run_id,
            "page_number": page_number,
            "native_page_checksum": native_page_checksum,
        },
        "render": {
            "renderer_name": renderer_name,
            "renderer_version": renderer_version,
            "render_configuration_version": render_configuration_version,
            "render_dpi": render_dpi,
            "render_color_mode": render_color_mode,
            "render_image_format": render_image_format,
            "page_image_sha256": rendered.checksum,
            "page_image_width_px": rendered.width_px,
            "page_image_height_px": rendered.height_px,
        },
        "ocr": {
            "provider_name": provider_name,
            "provider_version": provider_version,
            "model_identifier": model_identifier,
            "model_version": model_version,
            "ocr_configuration_version": ocr_configuration_version,
            "language_hints": list(language_hints),
        },
        "result": {
            "normalized_text": result.normalized_text,
            "character_count": result.character_count,
            "word_count": result.word_count,
            "text_checksum": result.text_checksum,
            "confidence_summary": result.confidence_summary,
            "warnings": result.warnings,
        },
    }
