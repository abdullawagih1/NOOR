"""
Failure classification (mission §16). Every failure path in the
extraction pipeline raises `ExtractionError` with one of these 17 exact
error codes — never a bare exception whose message might leak internals
(a local temp path, a stack frame, storage credentials).

Retryable defaults follow the mission's baseline table exactly; where the
mission says "Depends on classification" (extractor internal error,
unsupported PDF feature), the conservative choice actually taken is
recorded in the comment next to it — see
docs/domain/document-extraction-lifecycle.md for the full rationale.
"""
from __future__ import annotations

from dataclasses import dataclass

ExtractionErrorCode = str  # one of the 17 codes below; kept as `str` to avoid import-order coupling with pipeline callers

RETRYABLE_BY_ERROR_CODE: dict[str, bool] = {
    "source_document_not_verified": False,
    "source_object_missing": True,  # "Possibly" per the mission's table — treated as retryable (storage eventual-consistency lag is plausible)
    "source_size_mismatch": False,
    "source_checksum_mismatch": False,
    "invalid_pdf_signature": False,
    "corrupt_pdf": False,
    "encrypted_pdf": False,
    "password_protected_pdf": False,
    "unsupported_pdf_feature": False,  # conservative default; a specific unsupported feature won't resolve itself on retry
    "pdf_open_failed": False,
    "page_extraction_failed": False,  # deterministic property of the PDF's content — retrying won't change the outcome
    "artifact_serialization_failed": True,
    "artifact_upload_failed": True,  # "transient artifact upload failure" per the mission's table
    "artifact_checksum_mismatch": True,  # likely a transport issue; a clean re-upload might succeed
    "database_finalization_failed": True,  # "database timeout" per the mission's table
    "lease_lost": False,  # not reported via fail_document_processing_job at all — see ExtractionError.__str__ note below
    "extraction_timeout": True,
    "extractor_internal_error": True,  # conservative default, matching the existing worker_loop.py unexpected-exception classification
}

ALL_ERROR_CODES = frozenset(RETRYABLE_BY_ERROR_CODE.keys())


@dataclass
class ExtractionError(Exception):
    error_code: str
    message_safe: str
    error_class: str | None = None

    def __post_init__(self) -> None:
        if self.error_code not in ALL_ERROR_CODES:
            raise ValueError(f"unknown extraction error_code: {self.error_code!r}")
        if self.error_class is None:
            self.error_class = self.error_code
        super().__init__(self.message_safe)

    @property
    def retryable(self) -> bool:
        return RETRYABLE_BY_ERROR_CODE[self.error_code]
