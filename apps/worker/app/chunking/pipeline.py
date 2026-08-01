"""
Ties context retrieval, deterministic chunking, coverage verification, and
artifact construction/upload together for one document_chunking job (ADR
0014: one job, one whole document — unlike OCR's one-job-one-page). Runs
inside the existing WorkerLoop's heartbeat-thread window exactly like
app/pdf_extraction/pipeline.py and app/ocr/pipeline.py.
"""
from __future__ import annotations

import uuid

from app.chunking.artifact import build_canonical_chunking_artifact, chunks_to_rpc_payload
from app.chunking.artifact_storage import build_chunking_artifact_storage_path
from app.chunking.checksums import canonical_bytes, compute_artifact_checksum
from app.chunking.chunker import build_chunks_for_document
from app.chunking.config import ARTIFACT_MEDIA_TYPE, ARTIFACT_STORAGE_BUCKET, HARD_MAXIMUM_CHUNK_TOKENS, TARGET_CHUNK_TOKENS
from app.chunking.coverage import compute_coverage_and_duplication
from app.chunking.errors import ChunkingError
from app.chunking.manifest import build_input_manifest, compute_input_manifest_sha256
from app.chunking.models import ChunkDraft, PageRepresentation
from app.chunking.normalization import normalize_page_text
from app.pdf_extraction.artifact_storage import upload_and_verify_artifact
from app.pdf_extraction.errors import ExtractionError


class ChunkingPipelineOutcome:
    def __init__(self, chunks: list[ChunkDraft], metrics: dict, warnings: list[str], artifact_bytes: bytes, artifact_sha256: str, storage_path: str) -> None:
        self.chunks = chunks
        self.metrics = metrics
        self.warnings = warnings
        self.artifact_bytes = artifact_bytes
        self.artifact_sha256 = artifact_sha256
        self.storage_path = storage_path
        self.storage_bucket = ARTIFACT_STORAGE_BUCKET
        self.media_type = ARTIFACT_MEDIA_TYPE


def build_pages_from_context_rows(context_rows: list[dict]) -> list[PageRepresentation]:
    # character_count is recomputed from the NFC-normalized text (what
    # chunking and coverage actually operate on), not trusted from the
    # DB row's own count (which reflects the pre-normalization text
    # recorded at extraction/OCR time) — NFC composition can change
    # character counts (e.g. combining-character sequences). text_checksum
    # is kept as-is from the DB row: it is a provenance identifier for the
    # accepted representation, not a description of post-normalization
    # length.
    return [
        PageRepresentation(
            page_number=row["out_page_number"],
            representation_type=row["out_representation_type"],
            representation_id=str(row["out_representation_id"]),
            text_checksum=row["out_text_checksum"],
            normalized_text=normalize_page_text(row.get("out_normalized_text") or ""),
            character_count=len(normalize_page_text(row.get("out_normalized_text") or "")),
            word_count=row.get("out_word_count") or 0,
            warning_state=bool(row.get("out_warning_state")),
        )
        for row in sorted(context_rows, key=lambda r: r["out_page_number"])
    ]


def run_chunking_pipeline(
    *,
    pages: list[PageRepresentation],
    source_document_id: str,
    source_sha256: str,
    extraction_run_id: str,
    input_manifest: dict,
    input_manifest_sha256: str,
    pipeline_version: str,
    configuration_version: str,
    normalization_version: str,
    tokenizer_name: str,
    tokenizer_version: str,
    organization_id: str,
) -> ChunkingPipelineOutcome:
    chunks = build_chunks_for_document(pages)

    coverage_percentage, duplication_percentage, coverage_warnings = compute_coverage_and_duplication(pages, chunks)
    if coverage_percentage != 100.0:
        raise ChunkingError("coverage_validation_failed", "the chunking pipeline did not achieve 100% text coverage")
    if duplication_percentage != 0.0:
        raise ChunkingError("unexpected_duplication_detected", "the chunking pipeline produced overlapping chunk source spans")

    metrics = _build_metrics(pages, chunks, coverage_percentage, duplication_percentage)
    warnings = list(coverage_warnings) + [w for chunk in chunks for w in chunk.warnings if chunk.warning_state]

    try:
        artifact = build_canonical_chunking_artifact(
            source_document_id=source_document_id,
            source_sha256=source_sha256,
            extraction_run_id=extraction_run_id,
            input_manifest=input_manifest,
            input_manifest_sha256=input_manifest_sha256,
            pipeline_version=pipeline_version,
            configuration_version=configuration_version,
            normalization_version=normalization_version,
            tokenizer_name=tokenizer_name,
            tokenizer_version=tokenizer_version,
            chunks=chunks,
            metrics=metrics,
        )
        artifact_bytes = canonical_bytes(artifact)
        artifact_sha256 = compute_artifact_checksum(artifact)
    except ChunkingError:
        raise
    except Exception as exc:
        raise ChunkingError("artifact_serialization_failed", "the chunking artifact could not be serialized") from exc

    storage_path = build_chunking_artifact_storage_path(
        organization_id=organization_id,
        source_document_id=source_document_id,
        pipeline_version=pipeline_version,
        tokenizer_name=tokenizer_name,
        tokenizer_version=tokenizer_version,
        artifact_sha256=artifact_sha256,
    )

    return ChunkingPipelineOutcome(chunks, metrics, warnings, artifact_bytes, artifact_sha256, storage_path)


def upload_chunking_artifact(
    *, supabase_url: str, service_role_key: str, outcome: ChunkingPipelineOutcome, http_client=None
) -> None:
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
        raise ChunkingError(code, exc.message_safe) from exc


def _build_metrics(pages: list[PageRepresentation], chunks: list[ChunkDraft], coverage_percentage: float, duplication_percentage: float) -> dict:
    token_counts = [c.token_count for c in chunks]
    native_pages = sum(1 for p in pages if p.representation_type == "native")
    ocr_pages = sum(1 for p in pages if p.representation_type == "ocr")

    return {
        "chunk_count": len(chunks),
        "page_count": len(pages),
        "native_representation_page_count": native_pages,
        "ocr_representation_page_count": ocr_pages,
        "total_characters": sum(c.character_count for c in chunks),
        "total_words": sum(c.word_count for c in chunks),
        "total_tokens": sum(token_counts),
        "minimum_chunk_tokens": min(token_counts) if token_counts else 0,
        "maximum_chunk_tokens": max(token_counts) if token_counts else 0,
        "average_chunk_tokens": round(sum(token_counts) / len(token_counts), 4) if token_counts else 0,
        "chunks_below_minimum": sum(1 for c in chunks if "chunk_below_minimum_tokens" in c.warnings),
        "chunks_above_target": sum(1 for tok in token_counts if tok > TARGET_CHUNK_TOKENS),
        "chunks_at_hard_maximum": sum(1 for tok in token_counts if tok >= HARD_MAXIMUM_CHUNK_TOKENS),
        "hard_split_count": sum(1 for c in chunks if any(w.startswith("hard_split:") for w in c.warnings)),
        "heading_boundary_count": sum(1 for c in chunks if "heading_candidate" in c.block_type_summary),
        "list_boundary_count": sum(1 for c in chunks if "list_item" in c.block_type_summary),
        "table_like_chunk_count": sum(1 for c in chunks if "table_like" in c.block_type_summary),
        "warning_chunk_count": sum(1 for c in chunks if c.warning_state),
        "coverage_percentage": coverage_percentage,
        "duplication_percentage": duplication_percentage,
    }
