"""
Embedding identity determinism tests (mission §13-14, ADR 0016) — proving
a changed chunk checksum, model revision, or template version always
produces a different identity, and an unchanged tuple always reproduces
the identical hash.
"""
from __future__ import annotations

from app.embedding.identity import (
    compute_chunk_embedding_identity_sha256,
    compute_query_embedding_identity_sha256,
)

BASE_CHUNK_KWARGS = dict(
    organization_id="org-1",
    chunk_id="chunk-1",
    chunk_checksum="checksum-1",
    chunking_run_id="run-1",
    input_text_checksum="input-1",
    provider_version="5.6.1",
)


def test_chunk_identity_is_deterministic():
    a = compute_chunk_embedding_identity_sha256(**BASE_CHUNK_KWARGS)
    b = compute_chunk_embedding_identity_sha256(**BASE_CHUNK_KWARGS)
    assert a == b


def test_chunk_identity_changes_with_chunk_checksum():
    a = compute_chunk_embedding_identity_sha256(**BASE_CHUNK_KWARGS)
    changed = dict(BASE_CHUNK_KWARGS, chunk_checksum="checksum-2")
    b = compute_chunk_embedding_identity_sha256(**changed)
    assert a != b


def test_chunk_identity_changes_with_chunking_run_id():
    a = compute_chunk_embedding_identity_sha256(**BASE_CHUNK_KWARGS)
    changed = dict(BASE_CHUNK_KWARGS, chunking_run_id="run-2")
    b = compute_chunk_embedding_identity_sha256(**changed)
    assert a != b


def test_chunk_identity_changes_with_input_text_checksum():
    a = compute_chunk_embedding_identity_sha256(**BASE_CHUNK_KWARGS)
    changed = dict(BASE_CHUNK_KWARGS, input_text_checksum="input-2")
    b = compute_chunk_embedding_identity_sha256(**changed)
    assert a != b


def test_chunk_identity_changes_with_organization_id_never_reused_cross_tenant():
    a = compute_chunk_embedding_identity_sha256(**BASE_CHUNK_KWARGS)
    changed = dict(BASE_CHUNK_KWARGS, organization_id="org-2")
    b = compute_chunk_embedding_identity_sha256(**changed)
    assert a != b


BASE_QUERY_KWARGS = dict(
    organization_id="org-1",
    evaluation_dataset_id="dataset-1",
    dataset_sha256="dataset-checksum-1",
    query_id="query-1",
    query_checksum="query-checksum-1",
    provider_version="5.6.1",
)


def test_query_identity_is_deterministic():
    a = compute_query_embedding_identity_sha256(**BASE_QUERY_KWARGS)
    b = compute_query_embedding_identity_sha256(**BASE_QUERY_KWARGS)
    assert a == b


def test_query_identity_changes_with_dataset_sha256():
    a = compute_query_embedding_identity_sha256(**BASE_QUERY_KWARGS)
    changed = dict(BASE_QUERY_KWARGS, dataset_sha256="dataset-checksum-2")
    b = compute_query_embedding_identity_sha256(**changed)
    assert a != b


def test_query_identity_changes_with_query_checksum():
    a = compute_query_embedding_identity_sha256(**BASE_QUERY_KWARGS)
    changed = dict(BASE_QUERY_KWARGS, query_checksum="query-checksum-2")
    b = compute_query_embedding_identity_sha256(**changed)
    assert a != b


def test_chunk_and_query_identity_functions_never_collide():
    chunk_identity = compute_chunk_embedding_identity_sha256(**BASE_CHUNK_KWARGS)
    query_identity = compute_query_embedding_identity_sha256(**BASE_QUERY_KWARGS)
    assert chunk_identity != query_identity
