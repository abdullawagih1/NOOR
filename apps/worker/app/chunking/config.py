"""
Canonical chunking identity constants (Sprint 1-D3, ADR 0014). Bumping any
of these is a deliberate, reviewed action that changes the deterministic
chunking identity and therefore produces a fresh chunking run rather than
reusing an existing one — see ADR 0014 and
docs/domain/chunking-technical-review.md.
"""
from __future__ import annotations

CHUNKING_PIPELINE_VERSION = "controlled-page-aware-chunking-v1"
CHUNKING_CONFIGURATION_VERSION = "1"
NORMALIZATION_VERSION = "1"

TOKENIZER_NAME = "noor-simple-tokenizer"
TOKENIZER_VERSION = "1"

# Deterministic chunk-size targets, expressed in noor-simple-tokenizer
# tokens — a technical size proxy only, never a real embedding model's
# context window (ADR 0014's explicit boundary).
TARGET_CHUNK_TOKENS = 400
MINIMUM_CHUNK_TOKENS = 50
HARD_MAXIMUM_CHUNK_TOKENS = 800

ARTIFACT_SCHEMA_VERSION = "1.0"
ARTIFACT_MEDIA_TYPE = "application/json"
ARTIFACT_STORAGE_BUCKET = "guideline-processed"
