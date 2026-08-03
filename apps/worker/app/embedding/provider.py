"""
Provider-neutral embedding contract (mission §24, ADR 0016) plus the one
concrete implementation this sprint approves: `SentenceTransformerProvider`,
wrapping the self-hosted, pinned `intfloat/multilingual-e5-base` model.

`EmbeddingProvider` is a `Protocol`, not an ABC — any future provider (an
external API client, a different self-hosted model) slots in without
inheriting from anything, matching this codebase's existing `Retriever`
Protocol convention (app/retrieval/retriever.py).

Every input/output is mapped by a stable string `key` the caller supplies
(mission §26: "Provider responses must be mapped by stable input keys, not
assumed response order alone") — `sentence_transformers.encode()` happens
to preserve input order faithfully for a single local synchronous call, but
this module never relies on that assumption.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Protocol

from app.embedding.config import (
    MODEL_IDENTIFIER,
    MODEL_REVISION,
    PASSAGE_PREFIX,
    PROVIDER_NAME,
    QUERY_PREFIX,
    assert_pinned_embedding_model,
)
from app.embedding.errors import EmbeddingError


@dataclass(frozen=True)
class EmbeddingInput:
    key: str
    text: str
    input_checksum: str
    token_count: int
    input_mode: str  # 'query' | 'passage'


@dataclass(frozen=True)
class EmbeddingVector:
    key: str
    values: tuple[float, ...]
    dimension: int
    provider_request_id: str | None = None
    metadata: dict = field(default_factory=dict)


class EmbeddingProvider(Protocol):
    @property
    def name(self) -> str: ...

    @property
    def version(self) -> str: ...

    @property
    def model_identifier(self) -> str: ...

    @property
    def model_revision(self) -> str: ...

    @property
    def dimension(self) -> int: ...

    def count_tokens(self, text: str, *, input_mode: str) -> int: ...

    def embed(self, inputs: list[EmbeddingInput]) -> list[EmbeddingVector]: ...


def _apply_prefix(text: str, input_mode: str) -> str:
    if input_mode == "passage":
        return f"{PASSAGE_PREFIX}{text}"
    if input_mode == "query":
        return f"{QUERY_PREFIX}{text}"
    raise ValueError(f"unknown input_mode: {input_mode!r}")


class SentenceTransformerProvider:
    """Self-hosted `intfloat/multilingual-e5-base` via `sentence-transformers`
    (ADR 0016). No network calls beyond the one-time model download —
    inference is entirely local CPU computation."""

    def __init__(self, *, provider_version: str, cache_folder: str | None = None) -> None:
        # Imported lazily so importing this module (e.g. from a pytest run
        # that only exercises the fake provider) never requires torch/
        # sentence-transformers to be installed — matching this codebase's
        # existing pattern of keeping heavy optional dependencies out of
        # module-level imports where a lighter test path exists.
        from sentence_transformers import SentenceTransformer

        self._model = SentenceTransformer(MODEL_IDENTIFIER, revision=MODEL_REVISION, cache_folder=cache_folder)
        # sentence-transformers renamed get_sentence_embedding_dimension() to
        # get_embedding_dimension() (still supported cross-version this way).
        get_dimension = getattr(self._model, "get_embedding_dimension", None) or self._model.get_sentence_embedding_dimension
        resolved_dimension = get_dimension()

        assert_pinned_embedding_model(MODEL_IDENTIFIER, MODEL_REVISION)
        if resolved_dimension != 768:
            raise EmbeddingError("embedding_dimension_mismatch", f"loaded model dimension ({resolved_dimension}) does not match the pinned configuration (768)")

        self._provider_version = provider_version
        self._dimension = resolved_dimension

    @property
    def name(self) -> str:
        return PROVIDER_NAME

    @property
    def version(self) -> str:
        return self._provider_version

    @property
    def model_identifier(self) -> str:
        return MODEL_IDENTIFIER

    @property
    def model_revision(self) -> str:
        return MODEL_REVISION

    @property
    def dimension(self) -> int:
        return self._dimension

    def count_tokens(self, text: str, *, input_mode: str) -> int:
        prefixed = _apply_prefix(text, input_mode)
        return len(self._model.tokenizer.encode(prefixed))

    def embed(self, inputs: list[EmbeddingInput]) -> list[EmbeddingVector]:
        if not inputs:
            return []
        prefixed_texts = [_apply_prefix(item.text, item.input_mode) for item in inputs]
        try:
            raw_vectors = self._model.encode(prefixed_texts, normalize_embeddings=True, convert_to_numpy=True, show_progress_bar=False)
        except Exception as exc:
            raise EmbeddingError("embedding_provider_unavailable", "the embedding model could not be run") from exc

        if len(raw_vectors) != len(inputs):
            raise EmbeddingError("embedding_provider_response_incomplete", "the embedding model returned a different number of vectors than inputs")

        results: list[EmbeddingVector] = []
        for item, raw in zip(inputs, raw_vectors):
            values = tuple(float(v) for v in raw)
            validate_raw_vector(values, expected_dimension=self._dimension)
            results.append(EmbeddingVector(key=item.key, values=values, dimension=self._dimension))
        return results


def validate_raw_vector(values: tuple[float, ...], *, expected_dimension: int) -> None:
    """Shared vector validation (mission §15) — dimension/finiteness/non-
    empty — called by every real `EmbeddingProvider.embed()` implementation
    and exercised directly by a fake provider in the unit-test suite, so
    the same checks are guaranteed for both without duplicating the rules."""
    if len(values) != expected_dimension:
        raise EmbeddingError("embedding_dimension_mismatch", f"expected dimension {expected_dimension}, got {len(values)}")
    if not all(math.isfinite(v) for v in values):
        raise EmbeddingError("embedding_vector_non_finite", "a produced vector contained NaN or Infinity")
    if all(v == 0.0 for v in values):
        raise EmbeddingError("embedding_vector_empty", "a produced vector was all-zero")
