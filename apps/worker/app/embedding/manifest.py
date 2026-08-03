"""
Deterministic ordered chunk manifest (mission §21, ADR 0016) — built
before any provider call, so `chunk_manifest_sha256` is stable regardless
of provider timing/retries. Never includes dynamic timestamps, lease
tokens, Worker identity, provider secrets, temporary paths, or signed URLs.
"""
from __future__ import annotations

from app.embedding.checksums import compute_manifest_checksum
from app.embedding.config import ARTIFACT_SCHEMA_VERSION


def build_chunk_manifest(
    *,
    chunking_run_id: str,
    chunking_review_id: str | None,
    configuration_key: str,
    provider_name: str,
    model_identifier: str,
    model_revision: str,
    embedding_dimension: int,
    chunks: list[dict],  # each: {chunk_id, chunk_index, chunk_checksum, input_text_checksum, input_token_count}
) -> dict:
    return {
        "schema_version": ARTIFACT_SCHEMA_VERSION,
        "chunking_run_id": chunking_run_id,
        "chunking_review_id": chunking_review_id,
        "embedding_configuration": {
            "configuration_key": configuration_key,
            "provider_name": provider_name,
            "model_identifier": model_identifier,
            "model_revision": model_revision,
            "dimension": embedding_dimension,
        },
        "chunks": sorted(
            (
                {
                    "chunk_id": c["chunk_id"],
                    "chunk_index": c["chunk_index"],
                    "chunk_checksum": c["chunk_checksum"],
                    "input_text_checksum": c["input_text_checksum"],
                    "input_token_count": c["input_token_count"],
                }
                for c in chunks
            ),
            key=lambda c: c["chunk_index"],
        ),
    }


def compute_chunk_manifest_sha256(manifest: dict) -> str:
    return compute_manifest_checksum(manifest)
