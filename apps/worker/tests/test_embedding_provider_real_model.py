"""
Real (non-mocked) `SentenceTransformerProvider` tests — actually loads and
runs the pinned `intfloat/multilingual-e5-base` model, unlike
test_embedding_provider.py / test_embedding_pipeline.py (which use a
deterministic fake to prove Worker orchestration logic in isolation).
Skipped cleanly, not failed, on a machine/CI runner that lacks torch/
sentence-transformers or has not already downloaded the pinned model
snapshot — mirrors test_ocr_renderer_and_provider.py's
`requires_ocr_engine` precedent exactly (real dependencies are checked for
pre-provisioned availability, never auto-installed/auto-downloaded by the
test itself). See docs/operations/embedding-worker-runbook.md for how to
provision the model locally.

Satisfies the mission's own explicit requirement: "Completion requires the
selected real provider/model to execute in a real integration or hosted
verification path" (§53) — this is that real integration path.
"""
from __future__ import annotations

import math

import pytest

try:
    from huggingface_hub import scan_cache_dir

    _cached_repo_ids = {repo.repo_id for repo in scan_cache_dir().repos}
    _model_cached = "intfloat/multilingual-e5-base" in _cached_repo_ids
except Exception:
    _model_cached = False

try:
    import sentence_transformers  # noqa: F401

    _library_available = True
except ImportError:
    _library_available = False

requires_embedding_model = pytest.mark.skipif(
    not (_library_available and _model_cached),
    reason="torch/sentence-transformers not installed and/or the pinned intfloat/multilingual-e5-base "
    "snapshot is not already cached locally — install requirements.txt and let the model download "
    "once (or pre-fetch it) to enable these tests",
)


@requires_embedding_model
def test_real_provider_resolves_pinned_identity():
    from app.embedding.provider import SentenceTransformerProvider

    provider = SentenceTransformerProvider(provider_version="5.6.1")

    assert provider.model_identifier == "intfloat/multilingual-e5-base"
    assert provider.model_revision == "d128750597153bb5987e10b1c3493a34e5a4502a"
    assert provider.dimension == 768


@requires_embedding_model
def test_real_provider_produces_l2_normalized_vectors():
    from app.embedding.provider import EmbeddingInput, SentenceTransformerProvider

    provider = SentenceTransformerProvider(provider_version="5.6.1")
    inputs = [EmbeddingInput(key="c1", text="Blood pressure measurement technique for adults", input_checksum="x", token_count=10, input_mode="passage")]

    vectors = provider.embed(inputs)

    assert len(vectors) == 1
    norm = math.sqrt(sum(v * v for v in vectors[0].values))
    assert math.isclose(norm, 1.0, abs_tol=1e-4)


@requires_embedding_model
def test_real_provider_ranks_semantically_related_passage_above_unrelated_one():
    from app.embedding.provider import EmbeddingInput, SentenceTransformerProvider

    provider = SentenceTransformerProvider(provider_version="5.6.1")
    passages = provider.embed(
        [
            EmbeddingInput(key="related", text="Blood pressure measurement technique for adults", input_checksum="x", token_count=8, input_mode="passage"),
            EmbeddingInput(key="unrelated", text="Unrelated hospital cafeteria menu", input_checksum="y", token_count=5, input_mode="passage"),
        ]
    )
    query = provider.embed([EmbeddingInput(key="q", text="blood pressure measurement", input_checksum="z", token_count=3, input_mode="query")])[0]

    def cosine(a, b):
        return sum(x * y for x, y in zip(a, b))

    related_vec = next(v for v in passages if v.key == "related")
    unrelated_vec = next(v for v in passages if v.key == "unrelated")

    assert cosine(query.values, related_vec.values) > cosine(query.values, unrelated_vec.values)


@requires_embedding_model
def test_real_provider_token_counting_matches_documented_max_length():
    from app.embedding.config import MAXIMUM_INPUT_TOKENS
    from app.embedding.provider import SentenceTransformerProvider

    provider = SentenceTransformerProvider(provider_version="5.6.1")
    short_count = provider.count_tokens("blood pressure", input_mode="query")

    assert 0 < short_count < MAXIMUM_INPUT_TOKENS
