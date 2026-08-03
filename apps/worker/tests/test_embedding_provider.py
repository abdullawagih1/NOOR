"""
`validate_raw_vector` and a deterministic fake `EmbeddingProvider` (mission
§53: "Use a deterministic fake provider only for unit testing") — proves
dimension/NaN/Infinity/empty-vector rejection without loading the real
model or making any network call.
"""
from __future__ import annotations

import math

import pytest

from app.embedding.errors import EmbeddingError
from app.embedding.provider import EmbeddingInput, EmbeddingVector, validate_raw_vector


def test_validate_raw_vector_accepts_a_well_formed_vector():
    validate_raw_vector(tuple([0.1] * 768), expected_dimension=768)


def test_validate_raw_vector_rejects_wrong_dimension():
    with pytest.raises(EmbeddingError) as exc_info:
        validate_raw_vector(tuple([0.1] * 3), expected_dimension=768)
    assert exc_info.value.error_code == "embedding_dimension_mismatch"


def test_validate_raw_vector_rejects_nan():
    values = tuple([0.1] * 767 + [math.nan])
    with pytest.raises(EmbeddingError) as exc_info:
        validate_raw_vector(values, expected_dimension=768)
    assert exc_info.value.error_code == "embedding_vector_non_finite"


def test_validate_raw_vector_rejects_infinity():
    values = tuple([0.1] * 767 + [math.inf])
    with pytest.raises(EmbeddingError) as exc_info:
        validate_raw_vector(values, expected_dimension=768)
    assert exc_info.value.error_code == "embedding_vector_non_finite"


def test_validate_raw_vector_rejects_all_zero_vector():
    with pytest.raises(EmbeddingError) as exc_info:
        validate_raw_vector(tuple([0.0] * 768), expected_dimension=768)
    assert exc_info.value.error_code == "embedding_vector_empty"


class FakeEmbeddingProvider:
    """Deterministic fake — same "signal coordinate" convention as the SQL
    test suite's synthetic vectors (013/014), so both layers can be
    reasoned about identically. Never imports torch/sentence-transformers."""

    name = "fake-provider"
    version = "test"
    model_identifier = "fake/model"
    model_revision = "0"
    dimension = 8

    def __init__(self, *, force_bad_vector: str | None = None) -> None:
        self._force_bad_vector = force_bad_vector

    def count_tokens(self, text: str, *, input_mode: str) -> int:
        return len(text.split())

    def embed(self, inputs: list[EmbeddingInput]) -> list[EmbeddingVector]:
        results = []
        for item in inputs:
            if self._force_bad_vector == "nan":
                values = tuple([math.nan] * self.dimension)
            elif self._force_bad_vector == "wrong_dimension":
                values = tuple([0.1] * 3)
            elif self._force_bad_vector == "empty":
                values = tuple([0.0] * self.dimension)
            else:
                values = tuple([0.9 if i == 0 else 0.01 for i in range(self.dimension)])
            validate_raw_vector(values, expected_dimension=self.dimension)
            results.append(EmbeddingVector(key=item.key, values=values, dimension=self.dimension))
        return results


def test_fake_provider_produces_valid_vectors_by_default():
    provider = FakeEmbeddingProvider()
    inputs = [EmbeddingInput(key="a", text="hello world", input_checksum="x", token_count=2, input_mode="passage")]
    vectors = provider.embed(inputs)
    assert len(vectors) == 1
    assert vectors[0].dimension == 8


def test_fake_provider_forced_bad_vector_raises_embedding_error():
    provider = FakeEmbeddingProvider(force_bad_vector="nan")
    inputs = [EmbeddingInput(key="a", text="hello world", input_checksum="x", token_count=2, input_mode="passage")]
    with pytest.raises(EmbeddingError) as exc_info:
        provider.embed(inputs)
    assert exc_info.value.error_code == "embedding_vector_non_finite"
