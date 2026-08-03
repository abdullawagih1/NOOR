"""
Canonical embedding identity constants (Sprint 1-E2, ADR 0016). Pinned
exactly to the approved `embedding_configurations` row seeded by migration
0016 (`noor-multilingual-e5-base-v1`) — these constants exist so the Worker
never has to query the database to know its own identity, and so a mismatch
between the Worker's pinned values and the database's approved row is
detectable at startup (`assert_pinned_embedding_model`) rather than
discovered mid-run.

Bumping any of these is a deliberate, reviewed action that changes the
embedding identity (migration 0016 §13) and therefore produces a fresh
chunk/query embedding rather than reusing an existing one — see ADR 0016.
"""
from __future__ import annotations

EMBEDDING_CONFIGURATION_KEY = "noor-multilingual-e5-base-v1"

PROVIDER_NAME = "sentence-transformers"
PROVIDER_TYPE = "self_hosted"

# intfloat/multilingual-e5-base (ADR 0016) — MIT-licensed, self-hosted,
# revision confirmed live against the Hugging Face Hub API (not assumed
# from the README) at the time this configuration was approved.
MODEL_IDENTIFIER = "intfloat/multilingual-e5-base"
MODEL_REVISION = "d128750597153bb5987e10b1c3493a34e5a4502a"

EMBEDDING_DIMENSION = 768
MAXIMUM_INPUT_TOKENS = 512

PASSAGE_INPUT_TEMPLATE_VERSION = "1"
QUERY_INPUT_TEMPLATE_VERSION = "1"
PASSAGE_PREFIX = "passage: "
QUERY_PREFIX = "query: "

OUTPUT_NORMALIZATION = "l2_normalized"
DISTANCE_METRIC = "cosine"
EMBEDDING_CONFIGURATION_VERSION = "1"

VECTOR_SERIALIZATION_VERSION = "vector_serialization_v1"

ARTIFACT_SCHEMA_VERSION = "1.0"
ARTIFACT_MEDIA_TYPE = "application/json"
ARTIFACT_STORAGE_BUCKET = "guideline-processed"

# Batching (mission §26) — versioned so a change is a deliberate, reviewed
# action, not a silent tuning knob.
EMBEDDING_BATCH_CONFIGURATION_VERSION = "1"
EMBEDDING_MAX_BATCH_ITEMS = 16
EMBEDDING_MAX_BATCH_TOKENS = 4096
EMBEDDING_REQUEST_TIMEOUT_SECONDS = 120
EMBEDDING_MAX_RETRIES = 2


def assert_pinned_embedding_model(model_name: str, model_revision: str) -> None:
    """Fails closed at Worker startup / provider construction if the
    locally-resolved model identity does not match this module's pinned
    constants — the same discipline as
    app/pdf_extraction/config.py's assert_pinned_extractor_version() and
    app/ocr/config.py's assert_pinned_renderer_version()/
    assert_pinned_provider_version()."""
    if model_name != MODEL_IDENTIFIER:
        raise RuntimeError(
            f"Loaded embedding model ({model_name!r}) does not match the pinned "
            f"MODEL_IDENTIFIER ({MODEL_IDENTIFIER!r}) recorded in app/embedding/config.py."
        )
    if model_revision != MODEL_REVISION:
        raise RuntimeError(
            f"Loaded embedding model revision ({model_revision!r}) does not match the pinned "
            f"MODEL_REVISION ({MODEL_REVISION!r}) recorded in app/embedding/config.py. "
            "Update the constant (a deliberate, reviewed action — see ADR 0016) before deploying."
        )
