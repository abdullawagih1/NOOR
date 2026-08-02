"""
Canonical retrieval-evaluation identity constants (Sprint 1-E1, ADR 0015).
Bumping any of these is a deliberate, reviewed action that changes the
deterministic evaluation-run identity computed by
`create_retrieval_evaluation_run` (migration 0015) and therefore produces a
fresh run rather than reusing an existing one.

The ranking formula this configuration version pins:

    final_score = w_full_text * full_text_rank
                + w_coverage * token_coverage
                + (exact_phrase_bonus if exact_phrase_match else 0)

`full_text_rank` comes from PostgreSQL `ts_rank_cd` (migration 0015's
`get_retrieval_candidates`); `token_coverage` and `exact_phrase_match` are
computed in `app/retrieval/scoring.py`. This is a technical lexical-overlap
score — never described as a "relevance probability" anywhere (ADR 0015).
"""
from __future__ import annotations

RETRIEVER_NAME = "noor-lexical-baseline"
RETRIEVER_VERSION = "1"
RETRIEVAL_CONFIGURATION_VERSION = "1"
QUERY_NORMALIZATION_VERSION = "retrieval_text_normalization_v1"
METRIC_DEFINITION_VERSION = "1"
EVALUATION_RUNNER_VERSION = "1"

DEFAULT_TOP_K_VALUES = [1, 3, 5, 10]
DEFAULT_RELEVANCE_THRESHOLD = 2

# retrieval_configuration_version = "1"
WEIGHT_FULL_TEXT_RANK = 0.7
WEIGHT_TOKEN_COVERAGE = 0.3
EXACT_PHRASE_BONUS = 0.15

ARTIFACT_SCHEMA_VERSION = "1.0"
ARTIFACT_MEDIA_TYPE = "application/json"
ARTIFACT_STORAGE_BUCKET = "guideline-processed"
