"""
Embedding failure classification (mission §48) — mirrors
app/chunking/errors.py's pattern exactly. Every failure path in the
embedding pipeline raises `EmbeddingError` with one of these exact error
codes — never a bare exception whose message might leak internals or a
raw provider response.
"""
from __future__ import annotations

from dataclasses import dataclass

RETRYABLE_BY_ERROR_CODE: dict[str, bool] = {
    "embedding_configuration_not_approved": False,
    "embedding_input_not_ready": False,
    "embedding_input_invalidated": False,
    "embedding_input_checksum_mismatch": False,
    "embedding_input_exceeds_model_limit": False,  # a deterministic property of the input, not transient
    "embedding_provider_unavailable": True,
    "embedding_provider_timeout": True,
    "embedding_provider_rate_limited": True,
    "embedding_provider_auth_failed": False,
    "embedding_provider_response_incomplete": True,
    "embedding_model_unavailable": False,
    "embedding_model_checksum_mismatch": False,
    "embedding_dimension_mismatch": False,
    "embedding_vector_empty": True,
    "embedding_vector_non_finite": True,
    "embedding_vector_norm_invalid": True,
    "embedding_vector_checksum_failed": False,
    "embedding_persistence_failed": True,
    "embedding_artifact_failed": True,
    "embedding_coverage_incomplete": True,
    "query_embedding_dataset_not_frozen": False,
    "query_embedding_checksum_mismatch": False,
    "query_embedding_failed": True,
    "lease_lost": False,
    "database_finalization_failed": True,
    "embedding_internal_error": True,
}

ALL_ERROR_CODES = frozenset(RETRYABLE_BY_ERROR_CODE.keys())


@dataclass
class EmbeddingError(Exception):
    error_code: str
    message_safe: str
    error_class: str | None = None

    def __post_init__(self) -> None:
        if self.error_code not in ALL_ERROR_CODES:
            raise ValueError(f"unknown embedding error_code: {self.error_code!r}")
        if self.error_class is None:
            self.error_class = self.error_code
        super().__init__(self.message_safe)

    @property
    def retryable(self) -> bool:
        return RETRYABLE_BY_ERROR_CODE[self.error_code]
