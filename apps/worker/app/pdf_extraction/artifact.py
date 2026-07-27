"""
Canonical JSON artifact construction (mission §12). Field ordering within
the resulting dict is irrelevant to determinism — `checksums.compute_artifact_checksum`
serializes with `sort_keys=True`, so any two calls that build logically
identical dicts hash identically regardless of Python's dict insertion
order.

Never included: secrets, signed URLs, local temporary file paths, the
Worker's lease token, or raw stack traces (mission §12, §38) — this
module only ever receives already-sanitized `ExtractionResult` data, never
anything from the Worker's internal error-handling machinery.
"""
from __future__ import annotations

from app.pdf_extraction.config import ARTIFACT_SCHEMA_VERSION
from app.pdf_extraction.models import ExtractionResult


def build_canonical_artifact(
    *,
    source_document_id: str,
    source_sha256: str,
    source_size_bytes: int,
    pipeline_version: str,
    configuration_version: str,
    extractor_name: str,
    extractor_version: str,
    result: ExtractionResult,
) -> dict:
    return {
        "schema_version": ARTIFACT_SCHEMA_VERSION,
        "source": {
            "source_document_id": source_document_id,
            "source_sha256": source_sha256,
            "source_size_bytes": source_size_bytes,
        },
        "pipeline": {
            "pipeline_version": pipeline_version,
            "configuration_version": configuration_version,
            "extractor_name": extractor_name,
            "extractor_version": extractor_version,
        },
        "document": {
            "page_count": result.page_count,
            "metadata": result.document_metadata,
        },
        "metrics": {
            "pages_with_text": result.pages_with_text,
            "blank_pages": result.blank_page_count,
            "suspected_scanned_pages": result.suspected_scanned_page_count,
            "total_characters": result.total_character_count,
            "total_words": result.total_word_count,
            "rotated_page_count": result.rotated_page_count,
            "average_characters_per_page": result.average_characters_per_page,
            "minimum_characters_on_nonblank_page": result.minimum_characters_on_nonblank_page,
            "maximum_characters_on_page": result.maximum_characters_on_page,
        },
        "warnings": list(result.warnings),
        "pages": [
            {
                "page_number": p.page_number,
                "width_points": p.width_points,
                "height_points": p.height_points,
                "rotation_degrees": p.rotation_degrees,
                "normalized_text": p.normalized_text,
                "character_count": p.character_count,
                "word_count": p.word_count,
                "is_blank": p.is_blank,
                "suspected_scanned": p.suspected_scanned,
                "extraction_status": p.extraction_status,
                "warnings": p.warnings,
                "page_checksum": p.page_checksum,
            }
            for p in result.pages
        ],
    }
