"""
Canonical embedding-run artifact (mission §32, ADR 0016) — per-chunk
identity/checksums/dimension/norm/reuse-state plus aggregate summary. Full
vector arrays are deliberately never included (mission: "Do not store the
entire vector arrays in the artifact... unless required... and file size
remains controlled" — for this sprint's synthetic evaluation-scale corpora
the vectors are cheaply reproducible from the immutable database rows, so
there is no reproducibility need that would justify the size cost).
"""
from __future__ import annotations

from app.embedding.config import ARTIFACT_SCHEMA_VERSION


def build_canonical_embedding_artifact(
    *,
    run_identity_sha256: str,
    chunk_manifest_sha256: str,
    configuration_key: str,
    provider_name: str,
    provider_version: str,
    model_identifier: str,
    model_revision: str,
    embedding_dimension: int,
    distance_metric: str,
    items: list[dict],  # each: {chunk_index, chunk_checksum, input_text_checksum, embedding_identity_sha256, vector_checksum, dimension, norm, reused}
) -> dict:
    generated = sum(1 for item in items if not item["reused"])
    reused = sum(1 for item in items if item["reused"])
    return {
        "schema_version": ARTIFACT_SCHEMA_VERSION,
        "embedding_run": {
            "run_identity_sha256": run_identity_sha256,
            "chunk_manifest_sha256": chunk_manifest_sha256,
        },
        "configuration": {
            "configuration_key": configuration_key,
            "provider_name": provider_name,
            "provider_version": provider_version,
            "model_identifier": model_identifier,
            "model_revision": model_revision,
            "dimension": embedding_dimension,
            "distance_metric": distance_metric,
        },
        "summary": {
            "total_chunks": len(items),
            "generated": generated,
            "reused": reused,
            "failed": 0,
        },
        "items": sorted(
            (
                {
                    "chunk_index": item["chunk_index"],
                    "chunk_checksum": item["chunk_checksum"],
                    "input_text_checksum": item["input_text_checksum"],
                    "embedding_identity_sha256": item["embedding_identity_sha256"],
                    "vector_checksum": item["vector_checksum"],
                    "dimension": item["dimension"],
                    "norm": item["norm"],
                    "reused": item["reused"],
                }
                for item in items
            ),
            key=lambda item: item["chunk_index"],
        ),
    }
