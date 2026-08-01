"""
Canonical JSON chunking artifact — one artifact per chunking run, storing
the full ordered chunk list with provenance, mirroring
app/pdf_extraction/artifact.py and app/ocr/artifact.py's discipline. Field
ordering is irrelevant to determinism — app/chunking/checksums.py's
compute_artifact_checksum serializes with sort_keys=True.

Never included: secrets, signed URLs, local temporary file paths, the
Worker's lease token, or raw stack traces.
"""
from __future__ import annotations

from app.chunking.config import ARTIFACT_SCHEMA_VERSION
from app.chunking.models import ChunkDraft


def build_canonical_chunking_artifact(
    *,
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
    chunks: list[ChunkDraft],
    metrics: dict,
) -> dict:
    return {
        "schema_version": ARTIFACT_SCHEMA_VERSION,
        "source": {
            "source_document_id": source_document_id,
            "source_sha256": source_sha256,
            "extraction_run_id": extraction_run_id,
        },
        "input_manifest": input_manifest,
        "input_manifest_sha256": input_manifest_sha256,
        "identity": {
            "pipeline_version": pipeline_version,
            "configuration_version": configuration_version,
            "normalization_version": normalization_version,
            "tokenizer_name": tokenizer_name,
            "tokenizer_version": tokenizer_version,
        },
        "chunks": [_chunk_to_dict(chunk) for chunk in chunks],
        "metrics": metrics,
    }


def _chunk_to_dict(chunk: ChunkDraft) -> dict:
    return {
        "chunk_index": chunk.chunk_index,
        "chunk_text": chunk.chunk_text,
        "chunk_checksum": chunk.chunk_checksum,
        "page_start": chunk.page_start,
        "page_end": chunk.page_end,
        "token_count": chunk.token_count,
        "character_count": chunk.character_count,
        "word_count": chunk.word_count,
        "heading_context": chunk.heading_context,
        "block_type_summary": chunk.block_type_summary,
        "boundary_start_reason": chunk.boundary_start_reason,
        "boundary_end_reason": chunk.boundary_end_reason,
        "contains_native_text": chunk.contains_native_text,
        "contains_ocr_text": chunk.contains_ocr_text,
        "warning_state": chunk.warning_state,
        "warnings": chunk.warnings,
        "source_spans": [
            {
                "page_number": span.page_number,
                "representation_type": span.representation_type,
                "representation_id": span.representation_id,
                "representation_checksum": span.representation_checksum,
                "start_offset": span.start_offset,
                "end_offset": span.end_offset,
                "source_fragment_checksum": span.source_fragment_checksum,
                "span_order": span.span_order,
                "block_type_hint": span.block_type_hint,
                "boundary_reason": span.boundary_reason,
            }
            for span in chunk.source_spans
        ],
    }


def chunks_to_rpc_payload(chunks: list[ChunkDraft]) -> list[dict]:
    """Same shape as the artifact's chunk list — passed directly as the
    `p_chunks` jsonb argument to finalize_document_chunking_run (migration
    0012), which reads these exact keys."""
    return [_chunk_to_dict(chunk) for chunk in chunks]
