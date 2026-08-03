"""
`app/embedding/pipeline.py` unit tests — input-limit rejection, batching/
stable-key mapping, and norm validation, all against a deterministic fake
provider (mission §12/§26/§53). Zero network or model access.
"""
from __future__ import annotations

import pytest

from app.embedding.config import EMBEDDING_MAX_BATCH_ITEMS, MAXIMUM_INPUT_TOKENS
from app.embedding.errors import EmbeddingError
from app.embedding.pipeline import embed_chunks_in_batches, finalize_chunk_result, validate_and_prepare_chunk
from app.embedding.provider import EmbeddingInput, EmbeddingVector


class _FakeProvider:
    name = "fake-provider"
    version = "test"
    dimension = 4

    def __init__(self) -> None:
        self.batch_sizes: list[int] = []

    def count_tokens(self, text: str, *, input_mode: str) -> int:
        return len(text.split())

    def embed(self, inputs: list[EmbeddingInput]) -> list[EmbeddingVector]:
        self.batch_sizes.append(len(inputs))
        # Deliberately reversed order in the returned list — proves the
        # caller maps by stable key, never by response position (mission §26).
        return [EmbeddingVector(key=item.key, values=(0.9, 0.01, 0.01, 0.01), dimension=4) for item in reversed(inputs)]


class _OversizeTokenProvider(_FakeProvider):
    def count_tokens(self, text: str, *, input_mode: str) -> int:
        return MAXIMUM_INPUT_TOKENS + 1


def test_validate_and_prepare_chunk_rejects_input_exceeding_model_limit():
    with pytest.raises(EmbeddingError) as exc_info:
        validate_and_prepare_chunk(
            provider=_OversizeTokenProvider(),
            organization_id="org-1",
            chunking_run_id="run-1",
            chunk_id="chunk-1",
            chunk_index=1,
            chunk_checksum="checksum-1",
            chunk_text="some text",
        )
    assert exc_info.value.error_code == "embedding_input_exceeds_model_limit"
    assert not exc_info.value.retryable  # a deterministic property of the input, not transient


def test_validate_and_prepare_chunk_accepts_input_within_limit():
    embedding_input, identity = validate_and_prepare_chunk(
        provider=_FakeProvider(),
        organization_id="org-1",
        chunking_run_id="run-1",
        chunk_id="chunk-1",
        chunk_index=1,
        chunk_checksum="checksum-1",
        chunk_text="blood pressure measurement",
    )
    assert embedding_input.key == "chunk-1"
    assert embedding_input.input_mode == "passage"
    assert len(identity) == 64  # sha256 hex digest


def test_embed_chunks_in_batches_maps_by_stable_key_not_response_order():
    provider = _FakeProvider()
    inputs = [EmbeddingInput(key=f"c{i}", text="x", input_checksum="x", token_count=1, input_mode="passage") for i in range(3)]

    values_by_key = embed_chunks_in_batches(provider, inputs)

    assert set(values_by_key.keys()) == {"c0", "c1", "c2"}
    assert all(values == (0.9, 0.01, 0.01, 0.01) for values in values_by_key.values())


def test_embed_chunks_in_batches_splits_by_max_batch_items():
    provider = _FakeProvider()
    inputs = [EmbeddingInput(key=f"c{i}", text="x", input_checksum="x", token_count=1, input_mode="passage") for i in range(EMBEDDING_MAX_BATCH_ITEMS + 5)]

    embed_chunks_in_batches(provider, inputs)

    assert provider.batch_sizes == [EMBEDDING_MAX_BATCH_ITEMS, 5]


def test_embed_chunks_in_batches_calls_heartbeat_once_per_batch():
    provider = _FakeProvider()
    inputs = [EmbeddingInput(key=f"c{i}", text="x", input_checksum="x", token_count=1, input_mode="passage") for i in range(EMBEDDING_MAX_BATCH_ITEMS + 1)]
    calls = []

    embed_chunks_in_batches(provider, inputs, heartbeat=lambda: calls.append(1))

    assert len(calls) == 2  # one heartbeat per batch, 2 batches


def test_finalize_chunk_result_computes_checksum_and_norm():
    embedding_input = EmbeddingInput(key="chunk-1", text="x", input_checksum="input-checksum", token_count=3, input_mode="passage")
    result = finalize_chunk_result(embedding_input, "identity-1", (1.0, 0.0, 0.0, 0.0), chunk_index=1, chunk_checksum="checksum-1")
    assert result.vector_norm == 1.0
    assert len(result.vector_checksum) == 64


def test_finalize_chunk_result_rejects_zero_norm():
    embedding_input = EmbeddingInput(key="chunk-1", text="x", input_checksum="input-checksum", token_count=3, input_mode="passage")
    with pytest.raises(EmbeddingError) as exc_info:
        finalize_chunk_result(embedding_input, "identity-1", (0.0, 0.0, 0.0, 0.0), chunk_index=1, chunk_checksum="checksum-1")
    assert exc_info.value.error_code == "embedding_vector_norm_invalid"
