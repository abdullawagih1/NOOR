"""
Chunk-embedding and query-embedding identity computation (mission §13-14,
ADR 0016) — pure Python, computed the same canonical-JSON way as every
other identity hash in this codebase (see app/chunking/checksums.py). The
SQL layer (`record_document_chunk_embedding`/`record_query_embedding`,
migrations 0016/0017) does not itself validate the *content* of the
identity string beyond uniqueness/idempotency — the Worker is the single
source of truth for how the tuple is composed, documented here exactly
once and never duplicated.
"""
from __future__ import annotations

import hashlib
import json

from app.embedding.config import (
    DISTANCE_METRIC,
    EMBEDDING_CONFIGURATION_VERSION,
    EMBEDDING_DIMENSION,
    MODEL_IDENTIFIER,
    MODEL_REVISION,
    OUTPUT_NORMALIZATION,
    PASSAGE_INPUT_TEMPLATE_VERSION,
    PROVIDER_NAME,
    QUERY_INPUT_TEMPLATE_VERSION,
)


def _hash_identity(identity: dict) -> str:
    canonical = json.dumps(identity, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def compute_chunk_embedding_identity_sha256(
    *,
    organization_id: str,
    chunk_id: str,
    chunk_checksum: str,
    chunking_run_id: str,
    input_text_checksum: str,
    provider_version: str,
) -> str:
    return _hash_identity(
        {
            "organization_id": organization_id,
            "chunk_id": chunk_id,
            "chunk_checksum": chunk_checksum,
            "chunking_run_id": chunking_run_id,
            "input_text_checksum": input_text_checksum,
            "passage_input_template_version": PASSAGE_INPUT_TEMPLATE_VERSION,
            "provider_name": PROVIDER_NAME,
            "provider_version": provider_version,
            "model_identifier": MODEL_IDENTIFIER,
            "model_revision": MODEL_REVISION,
            "embedding_dimension": EMBEDDING_DIMENSION,
            "output_normalization": OUTPUT_NORMALIZATION,
            "distance_metric": DISTANCE_METRIC,
            "embedding_configuration_version": EMBEDDING_CONFIGURATION_VERSION,
        }
    )


def compute_query_embedding_identity_sha256(
    *,
    organization_id: str,
    evaluation_dataset_id: str,
    dataset_sha256: str,
    query_id: str,
    query_checksum: str,
    provider_version: str,
) -> str:
    return _hash_identity(
        {
            "organization_id": organization_id,
            "evaluation_dataset_id": evaluation_dataset_id,
            "dataset_sha256": dataset_sha256,
            "query_id": query_id,
            "query_checksum": query_checksum,
            "query_input_template_version": QUERY_INPUT_TEMPLATE_VERSION,
            "provider_name": PROVIDER_NAME,
            "provider_version": provider_version,
            "model_identifier": MODEL_IDENTIFIER,
            "model_revision": MODEL_REVISION,
            "embedding_dimension": EMBEDDING_DIMENSION,
            "output_normalization": OUTPUT_NORMALIZATION,
            "distance_metric": DISTANCE_METRIC,
            "embedding_configuration_version": EMBEDDING_CONFIGURATION_VERSION,
        }
    )
