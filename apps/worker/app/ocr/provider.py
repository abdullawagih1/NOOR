"""
OCR provider abstraction (ADR 0012) and its one implementation,
Tesseract via pytesseract. Exactly one provider — self-hosted, per the
mission's explicit bias toward not sending guideline content to any
cloud OCR API without prior architectural/privacy approval (none has
been granted — see ADR 0012's comparison table).

The pinned, checksum-verified model directory (app/ocr/config.py,
scripts/fetch_tessdata_models.py) is always pointed to explicitly via the
TESSDATA_PREFIX environment variable — never relying on whatever tessdata
a system package happened to install alongside the binary. TESSDATA_PREFIX
is used instead of the `--tessdata-dir` config-string flag because
pytesseract splits its config string with `shlex.split(..., posix=not
is_windows)` — on Windows, non-POSIX mode does not strip quote characters
from tokens, so a quoted Windows path is passed to Tesseract with the
quote marks still embedded in it, corrupting the path. TESSDATA_PREFIX
sidesteps config-string parsing entirely and works identically on every
platform.
"""
from __future__ import annotations

import contextlib
import io
import os
from pathlib import Path
from typing import Iterator, Protocol

import pytesseract
from PIL import Image

from app.ocr.checksums import compute_text_checksum
from app.ocr.config import OCR_PROVIDER_VERSION, OcrConfiguration
from app.ocr.errors import OcrError
from app.ocr.models import OcrPageResult
from app.pdf_extraction.normalization import count_characters, count_words, normalize_page_text

LOW_CONFIDENCE_THRESHOLD = 70


@contextlib.contextmanager
def _tessdata_prefix(tessdata_dir: Path) -> Iterator[None]:
    previous = os.environ.get("TESSDATA_PREFIX")
    os.environ["TESSDATA_PREFIX"] = str(tessdata_dir)
    try:
        yield
    finally:
        if previous is None:
            os.environ.pop("TESSDATA_PREFIX", None)
        else:
            os.environ["TESSDATA_PREFIX"] = previous


class OcrProvider(Protocol):
    @property
    def name(self) -> str: ...

    @property
    def version(self) -> str: ...

    def recognize(
        self, image_bytes: bytes, *, language_hints: list[str], configuration: OcrConfiguration, tessdata_dir: Path
    ) -> OcrPageResult: ...


class TesseractProvider:
    """See ADR 0012 for the selection rationale and known limitations."""

    def __init__(self, version: str = OCR_PROVIDER_VERSION) -> None:
        self._version = version

    @property
    def name(self) -> str:
        return "tesseract"

    @property
    def version(self) -> str:
        return self._version

    def recognize(
        self, image_bytes: bytes, *, language_hints: list[str], configuration: OcrConfiguration, tessdata_dir: Path
    ) -> OcrPageResult:
        try:
            image = Image.open(io.BytesIO(image_bytes))
            image.load()
        except Exception as exc:
            raise OcrError("page_render_failed", "the rendered page image could not be read") from exc

        lang = "+".join(language_hints)
        config = f"--oem {configuration.oem} --psm {configuration.psm}"

        try:
            with _tessdata_prefix(tessdata_dir):
                raw_text = pytesseract.image_to_string(image, lang=lang, config=config)
        except pytesseract.TesseractError as exc:
            raise OcrError("ocr_provider_error", "the OCR provider failed to process this page") from exc
        except Exception as exc:
            raise OcrError("ocr_internal_error", "an unexpected error occurred during OCR") from exc

        try:
            with _tessdata_prefix(tessdata_dir):
                data = pytesseract.image_to_data(image, lang=lang, config=config, output_type=pytesseract.Output.DICT)
        except Exception as exc:
            raise OcrError("ocr_provider_error", "the OCR provider failed to produce confidence data for this page") from exc

        confidences = [int(c) for c in data.get("conf", []) if str(c) not in ("", "-1") and int(c) >= 0]
        average_confidence = (sum(confidences) / len(confidences)) if confidences else None
        low_confidence_word_count = sum(1 for c in confidences if c < LOW_CONFIDENCE_THRESHOLD)

        confidence_summary = {
            "average_confidence": average_confidence,
            "word_count_with_confidence": len(confidences),
            "low_confidence_word_count": low_confidence_word_count,
            "low_confidence_threshold": LOW_CONFIDENCE_THRESHOLD,
        }

        warnings: list[str] = []
        if not raw_text.strip():
            warnings.append("ocr_produced_no_text: recognition completed but no text was detected on this page")
        elif average_confidence is not None and average_confidence < LOW_CONFIDENCE_THRESHOLD:
            warnings.append(
                f"low_average_confidence: average word confidence ({average_confidence:.1f}) is below the {LOW_CONFIDENCE_THRESHOLD} threshold"
            )

        normalized = normalize_page_text(raw_text)
        return OcrPageResult(
            raw_text=raw_text,
            normalized_text=normalized,
            character_count=count_characters(normalized),
            word_count=count_words(normalized),
            text_checksum=compute_text_checksum(normalized),
            confidence_summary=confidence_summary,
            warnings=warnings,
            provider_metadata_safe={"language_hints": list(language_hints), "oem": configuration.oem, "psm": configuration.psm},
        )
