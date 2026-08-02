"""
Retrieval-evaluation failure classification — mirrors
app/chunking/errors.py's pattern exactly. Every failure path in the
evaluation pipeline raises `RetrievalEvaluationError` with one of these
exact error codes — never a bare exception whose message might leak
internals.
"""
from __future__ import annotations

from dataclasses import dataclass

RETRYABLE_BY_ERROR_CODE: dict[str, bool] = {
    "evaluation_job_context_not_found": False,  # structurally shouldn't happen; not a transient condition
    "dataset_not_frozen": False,
    "candidate_fetch_failed": True,
    "artifact_serialization_failed": True,
    "artifact_upload_failed": True,
    "artifact_checksum_mismatch": True,
    "database_finalization_failed": True,
    "evaluation_internal_error": True,  # conservative default, matching ChunkingError's own
}

ALL_ERROR_CODES = frozenset(RETRYABLE_BY_ERROR_CODE.keys())


@dataclass
class RetrievalEvaluationError(Exception):
    error_code: str
    message_safe: str
    error_class: str | None = None

    def __post_init__(self) -> None:
        if self.error_code not in ALL_ERROR_CODES:
            raise ValueError(f"unknown retrieval evaluation error_code: {self.error_code!r}")
        if self.error_class is None:
            self.error_class = self.error_code
        super().__init__(self.message_safe)

    @property
    def retryable(self) -> bool:
        return RETRYABLE_BY_ERROR_CODE[self.error_code]
