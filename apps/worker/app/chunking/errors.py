"""
Chunking failure classification — mirrors app/pdf_extraction/errors.py and
app/ocr/errors.py's pattern exactly. Every failure path in the chunking
pipeline raises `ChunkingError` with one of these exact error codes —
never a bare exception whose message might leak internals.
"""
from __future__ import annotations

from dataclasses import dataclass

ChunkingErrorCode = str

RETRYABLE_BY_ERROR_CODE: dict[str, bool] = {
    "chunking_job_context_not_found": False,  # structurally shouldn't happen; not a transient condition
    "document_not_chunking_eligible": False,
    "coverage_validation_failed": False,  # a deterministic property of the segmentation logic, not transient
    "unexpected_duplication_detected": False,
    "artifact_serialization_failed": True,
    "artifact_upload_failed": True,
    "artifact_checksum_mismatch": True,
    "database_finalization_failed": True,
    "lease_lost": False,  # not reported via fail_document_chunking_run at all — see OcrError's own note
    "chunking_internal_error": True,  # conservative default, matching pdf_extraction's extractor_internal_error
}

ALL_ERROR_CODES = frozenset(RETRYABLE_BY_ERROR_CODE.keys())


@dataclass
class ChunkingError(Exception):
    error_code: str
    message_safe: str
    error_class: str | None = None

    def __post_init__(self) -> None:
        if self.error_code not in ALL_ERROR_CODES:
            raise ValueError(f"unknown chunking error_code: {self.error_code!r}")
        if self.error_class is None:
            self.error_class = self.error_code
        super().__init__(self.message_safe)

    @property
    def retryable(self) -> bool:
        return RETRYABLE_BY_ERROR_CODE[self.error_code]
