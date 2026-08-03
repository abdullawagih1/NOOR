"""
Chunk-manifest determinism tests (mission §21, ADR 0016) — the manifest
must hash identically regardless of input chunk ordering (it is always
re-sorted by chunk_index internally) and must change if any chunk's
checksum/token count changes.
"""
from __future__ import annotations

from app.embedding.manifest import build_chunk_manifest, compute_chunk_manifest_sha256

CONFIG_KWARGS = dict(
    chunking_run_id="run-1",
    chunking_review_id="review-1",
    configuration_key="noor-multilingual-e5-base-v1",
    provider_name="sentence-transformers",
    model_identifier="intfloat/multilingual-e5-base",
    model_revision="d128750597153bb5987e10b1c3493a34e5a4502a",
    embedding_dimension=768,
)

CHUNK_1 = {"chunk_id": "c1", "chunk_index": 1, "chunk_checksum": "checksum-1", "input_text_checksum": "input-1", "input_token_count": 5}
CHUNK_2 = {"chunk_id": "c2", "chunk_index": 2, "chunk_checksum": "checksum-2", "input_text_checksum": "input-2", "input_token_count": 7}


def test_manifest_checksum_is_deterministic():
    manifest = build_chunk_manifest(chunks=[CHUNK_1, CHUNK_2], **CONFIG_KWARGS)
    a = compute_chunk_manifest_sha256(manifest)
    b = compute_chunk_manifest_sha256(build_chunk_manifest(chunks=[CHUNK_1, CHUNK_2], **CONFIG_KWARGS))
    assert a == b


def test_manifest_checksum_is_independent_of_input_chunk_order():
    forward = build_chunk_manifest(chunks=[CHUNK_1, CHUNK_2], **CONFIG_KWARGS)
    reversed_order = build_chunk_manifest(chunks=[CHUNK_2, CHUNK_1], **CONFIG_KWARGS)
    assert compute_chunk_manifest_sha256(forward) == compute_chunk_manifest_sha256(reversed_order)


def test_manifest_checksum_changes_when_a_chunk_checksum_changes():
    original = build_chunk_manifest(chunks=[CHUNK_1, CHUNK_2], **CONFIG_KWARGS)
    changed_chunk = dict(CHUNK_2, chunk_checksum="a-different-checksum")
    changed = build_chunk_manifest(chunks=[CHUNK_1, changed_chunk], **CONFIG_KWARGS)
    assert compute_chunk_manifest_sha256(original) != compute_chunk_manifest_sha256(changed)


def test_manifest_checksum_changes_when_model_revision_changes():
    original = build_chunk_manifest(chunks=[CHUNK_1, CHUNK_2], **CONFIG_KWARGS)
    changed_kwargs = dict(CONFIG_KWARGS, model_revision="a-different-revision")
    changed = build_chunk_manifest(chunks=[CHUNK_1, CHUNK_2], **changed_kwargs)
    assert compute_chunk_manifest_sha256(original) != compute_chunk_manifest_sha256(changed)


def test_manifest_never_includes_dynamic_or_secret_fields():
    manifest = build_chunk_manifest(chunks=[CHUNK_1], **CONFIG_KWARGS)
    serialized = str(manifest).lower()
    for forbidden in ("lease_token", "timestamp", "secret", "signed_url"):
        assert forbidden not in serialized
