"""
OCR failure classification — mirrors app/pdf_extraction/errors.py's
pattern exactly (mission §16 applied one layer deeper). Every failure
path in the OCR pipeline raises `OcrError` with one of these exact error
codes — never a bare exception whose message might leak internals (a
local temp path, a stack frame, provider stderr with file paths).
"""
from __future__ import annotations

from dataclasses import dataclass

OcrErrorCode = str

RETRYABLE_BY_ERROR_CODE: dict[str, bool] = {
    "ocr_request_page_not_found": False,  # structurally shouldn't happen; not a transient condition
    "extraction_run_not_succeeded": False,
    "ocr_request_not_eligible": False,
    "source_object_missing": True,  # storage eventual-consistency lag is plausible, same as extraction
    "source_size_mismatch": False,
    "source_checksum_mismatch": False,
    "invalid_pdf_signature": False,
    "corrupt_pdf": False,
    "page_render_failed": False,  # deterministic property of the page's content
    "ocr_provider_error": True,  # a provider subprocess failure may be transient (resource pressure)
    "ocr_timeout": True,
    "artifact_serialization_failed": True,
    "artifact_upload_failed": True,
    "artifact_checksum_mismatch": True,
    "database_finalization_failed": True,
    "lease_lost": False,  # not reported via fail_document_ocr_run at all — see OcrError.__str__ note below
    "ocr_internal_error": True,  # conservative default, matching pdf_extraction's extractor_internal_error
}

ALL_ERROR_CODES = frozenset(RETRYABLE_BY_ERROR_CODE.keys())


@dataclass
class OcrError(Exception):
    error_code: str
    message_safe: str
    error_class: str | None = None

    def __post_init__(self) -> None:
        if self.error_code not in ALL_ERROR_CODES:
            raise ValueError(f"unknown OCR error_code: {self.error_code!r}")
        if self.error_class is None:
            self.error_class = self.error_code
        super().__init__(self.message_safe)

    @property
    def retryable(self) -> bool:
        return RETRYABLE_BY_ERROR_CODE[self.error_code]
