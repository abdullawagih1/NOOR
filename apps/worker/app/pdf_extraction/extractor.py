"""
The PdfExtractor abstraction (mission §9) and its one implementation this
sprint, `PyPdfExtractor` (ADR 0010). No second extractor exists — nothing
in this abstraction prevents adding one later behind the same interface.
"""
from __future__ import annotations

from pathlib import Path
from typing import Protocol

import pypdf
from pypdf.errors import FileNotDecryptedError, PdfReadError

from app.pdf_extraction.checksums import compute_page_checksum
from app.pdf_extraction.config import ExtractionConfiguration
from app.pdf_extraction.errors import ExtractionError
from app.pdf_extraction.models import ExtractedPage, ExtractionResult
from app.pdf_extraction.normalization import count_characters, count_words, is_blank, normalize_page_text

PDF_SIGNATURE = b"%PDF-"


class PdfExtractor(Protocol):
    @property
    def name(self) -> str: ...

    @property
    def version(self) -> str: ...

    def extract(self, file_path: Path, *, configuration: ExtractionConfiguration) -> ExtractionResult: ...


def _count_image_xobjects(page) -> int:
    """Low-level XObject inspection — deliberately avoids pypdf's `page.images`
    convenience property, which pulls in Pillow to decode images; counting
    `/Subtype /Image` entries needs no image decoding at all, keeping Pillow
    out of the Worker's production runtime dependencies entirely (it remains
    a fixture-generation-only, test-time dependency — see ADR 0010)."""
    resources = page.get("/Resources")
    if resources is None:
        return 0
    xobjects = resources.get("/XObject")
    if xobjects is None:
        return 0
    xobjects = xobjects.get_object() if hasattr(xobjects, "get_object") else xobjects
    count = 0
    for _, ref in xobjects.items():
        obj = ref.get_object() if hasattr(ref, "get_object") else ref
        if obj.get("/Subtype") == "/Image":
            count += 1
    return count


class PyPdfExtractor:
    """See ADR 0010 for the selection rationale and known limitations."""

    def __init__(self, version: str) -> None:
        self._version = version

    @property
    def name(self) -> str:
        return "pypdf"

    @property
    def version(self) -> str:
        return self._version

    def extract(self, file_path: Path, *, configuration: ExtractionConfiguration) -> ExtractionResult:
        try:
            with open(file_path, "rb") as fh:
                header = fh.read(len(PDF_SIGNATURE))
            if header != PDF_SIGNATURE:
                raise ExtractionError("invalid_pdf_signature", "the file does not have a valid PDF signature")

            reader = pypdf.PdfReader(str(file_path))
        except ExtractionError:
            raise
        except FileNotDecryptedError as exc:
            raise ExtractionError("encrypted_pdf", "the PDF is encrypted and could not be read") from exc
        except PdfReadError as exc:
            raise ExtractionError("corrupt_pdf", "the PDF could not be parsed (corrupt or malformed)") from exc
        except Exception as exc:
            raise ExtractionError("pdf_open_failed", "the PDF could not be opened") from exc

        if reader.is_encrypted:
            try:
                # An empty-password attempt is the standard way to check for
                # PDFs "encrypted" only with owner-permission restrictions but
                # no real user password — reader.decrypt("") succeeds for
                # those and fails (raises) for genuinely password-protected
                # files, which we then classify distinctly.
                result = reader.decrypt("")
                if result == 0:
                    raise ExtractionError("password_protected_pdf", "the PDF requires a password and could not be opened")
            except ExtractionError:
                raise
            except Exception as exc:
                raise ExtractionError("password_protected_pdf", "the PDF requires a password and could not be opened") from exc

        document_metadata: dict = {}
        if reader.metadata:
            for key, value in reader.metadata.items():
                clean_key = key.lstrip("/")
                document_metadata[clean_key] = str(value) if value is not None else None

        pages: list[ExtractedPage] = []
        document_warnings: list[str] = []

        for index, page in enumerate(reader.pages):
            page_number = index + 1
            try:
                raw_text = page.extract_text() or ""
                rotation = int(page.rotation) % 360
                width = float(page.mediabox.width) if page.mediabox else None
                height = float(page.mediabox.height) if page.mediabox else None
                warnings: list[str] = []

                normalized = (
                    normalize_page_text(raw_text) if configuration.normalize_unicode or configuration.normalize_line_endings else raw_text
                )
                char_count = count_characters(normalized)
                word_count = count_words(normalized)
                blank = is_blank(normalized)

                image_count = _count_image_xobjects(page)
                # Conservative heuristic (mission §20): a page with no
                # extractable text AND at least one embedded image is
                # *suspected* scanned — never asserted as certain, and OCR
                # is never run to confirm or refute it.
                suspected_scanned = blank and image_count > 0

                if blank and image_count == 0:
                    # Truly empty (no text, no images/graphics) — e.g. a
                    # deliberate "this page intentionally left blank" divider.
                    status = "blank_page"
                elif blank and image_count > 0:
                    # Has visual content but no extractable text layer —
                    # the conservative "might be a scan" signal.
                    status = "no_text_layer"
                    warnings.append("suspected_scanned: no extractable text layer detected; OCR may be required in a later workflow")
                else:
                    status = "text_extracted"

                pages.append(
                    ExtractedPage(
                        page_number=page_number,
                        width_points=width,
                        height_points=height,
                        rotation_degrees=rotation,
                        raw_text=raw_text,
                        normalized_text=normalized,
                        character_count=char_count,
                        word_count=word_count,
                        is_blank=blank,
                        suspected_scanned=suspected_scanned,
                        extraction_status=status,
                        warnings=warnings,
                        page_checksum=compute_page_checksum(
                            page_number=page_number,
                            rotation_degrees=rotation,
                            width_points=width,
                            height_points=height,
                            normalized_text=normalized,
                            extraction_status=status,
                            warnings=warnings,
                        ),
                    )
                )
            except Exception as exc:
                raise ExtractionError(
                    "page_extraction_failed", f"page {page_number} could not be extracted"
                ) from exc

        return ExtractionResult(document_metadata=document_metadata, pages=pages, warnings=document_warnings)
