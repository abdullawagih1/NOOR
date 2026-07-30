"""
Real (non-mocked) renderer/provider tests — actually rasterizes fixture PDF
pages with pypdfium2 and actually runs Tesseract, unlike
test_ocr_processor.py (which fakes both to prove Worker orchestration
logic in isolation). Skipped cleanly, not failed, on a machine/CI runner
that lacks the `tesseract` binary or the pinned tessdata models — see
docs/operations/ocr-worker-runbook.md for how to provision both locally,
and the Dockerfile for how the production image provisions them at build
time.
"""
from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from app.ocr.checksums import compute_image_checksum
from app.ocr.config import DEFAULT_TESSDATA_DIR, OcrConfiguration
from app.ocr.provider import TesseractProvider
from app.ocr.renderer import Pypdfium2Renderer

FIXTURES_DIR = Path(__file__).parent / "fixtures" / "pdf"

tesseract_available = shutil.which("tesseract") is not None
tessdata_available = (DEFAULT_TESSDATA_DIR / "eng.traineddata").is_file() and (DEFAULT_TESSDATA_DIR / "ara.traineddata").is_file()

requires_ocr_engine = pytest.mark.skipif(
    not (tesseract_available and tessdata_available),
    reason="tesseract binary and/or pinned tessdata models not available on this machine — "
    "run apps/worker/scripts/fetch_tessdata_models.py and install tesseract-ocr to enable",
)


def test_renderer_produces_deterministic_checksum_for_the_same_page():
    renderer = Pypdfium2Renderer()
    pdf_path = FIXTURES_DIR / "one_page_english.pdf"

    first = renderer.render_page(pdf_path, 1, dpi=300, color_mode="rgb", image_format="png")
    second = renderer.render_page(pdf_path, 1, dpi=300, color_mode="rgb", image_format="png")

    assert first.checksum == second.checksum
    assert first.checksum == compute_image_checksum(first.image_bytes)
    assert first.width_px > 0 and first.height_px > 0


def test_renderer_different_dpi_produces_different_checksum():
    renderer = Pypdfium2Renderer()
    pdf_path = FIXTURES_DIR / "one_page_english.pdf"

    low_dpi = renderer.render_page(pdf_path, 1, dpi=150, color_mode="rgb", image_format="png")
    high_dpi = renderer.render_page(pdf_path, 1, dpi=300, color_mode="rgb", image_format="png")

    assert low_dpi.checksum != high_dpi.checksum
    assert high_dpi.width_px > low_dpi.width_px


def test_renderer_out_of_range_page_raises_page_render_failed():
    from app.ocr.errors import OcrError

    renderer = Pypdfium2Renderer()
    pdf_path = FIXTURES_DIR / "one_page_english.pdf"

    with pytest.raises(OcrError) as exc_info:
        renderer.render_page(pdf_path, 99, dpi=300, color_mode="rgb", image_format="png")
    assert exc_info.value.error_code == "page_render_failed"


def test_renderer_corrupt_pdf_raises_corrupt_pdf():
    from app.ocr.errors import OcrError

    renderer = Pypdfium2Renderer()
    pdf_path = FIXTURES_DIR / "corrupt.pdf"

    with pytest.raises(OcrError) as exc_info:
        renderer.render_page(pdf_path, 1, dpi=300, color_mode="rgb", image_format="png")
    assert exc_info.value.error_code == "corrupt_pdf"


@requires_ocr_engine
def test_english_page_is_recognized_with_high_confidence():
    renderer = Pypdfium2Renderer()
    provider = TesseractProvider()
    configuration = OcrConfiguration()

    rendered = renderer.render_page(FIXTURES_DIR / "one_page_english.pdf", 1, dpi=300, color_mode="rgb", image_format="png")
    result = provider.recognize(rendered.image_bytes, language_hints=["eng"], configuration=configuration, tessdata_dir=DEFAULT_TESSDATA_DIR)

    assert "english" in result.normalized_text.lower() or "fixture" in result.normalized_text.lower()
    assert result.character_count > 0
    assert result.confidence_summary["average_confidence"] is not None
    assert result.confidence_summary["average_confidence"] > 80
    assert "ocr_produced_no_text" not in result.warnings


@requires_ocr_engine
def test_mixed_arabic_english_page_is_recognized_with_both_scripts():
    renderer = Pypdfium2Renderer()
    provider = TesseractProvider()
    configuration = OcrConfiguration()

    rendered = renderer.render_page(FIXTURES_DIR / "arabic_and_english.pdf", 1, dpi=300, color_mode="rgb", image_format="png")
    result = provider.recognize(rendered.image_bytes, language_hints=["eng", "ara"], configuration=configuration, tessdata_dir=DEFAULT_TESSDATA_DIR)

    assert result.character_count > 0
    has_latin = any("a" <= c.lower() <= "z" for c in result.normalized_text)
    has_arabic = any("؀" <= c <= "ۿ" for c in result.normalized_text)
    assert has_latin, f"expected Latin characters in mixed-language recognition, got: {result.normalized_text!r}"
    assert has_arabic, f"expected Arabic characters in mixed-language recognition, got: {result.normalized_text!r}"


@requires_ocr_engine
def test_empty_image_page_produces_no_text_warning():
    renderer = Pypdfium2Renderer()
    provider = TesseractProvider()
    configuration = OcrConfiguration()

    rendered = renderer.render_page(FIXTURES_DIR / "empty_page.pdf", 1, dpi=300, color_mode="rgb", image_format="png")
    result = provider.recognize(rendered.image_bytes, language_hints=["eng"], configuration=configuration, tessdata_dir=DEFAULT_TESSDATA_DIR)

    assert result.character_count == 0
    assert any("ocr_produced_no_text" in w for w in result.warnings)


@requires_ocr_engine
def test_recognition_never_leaks_the_tessdata_path_in_provider_metadata():
    renderer = Pypdfium2Renderer()
    provider = TesseractProvider()
    configuration = OcrConfiguration()

    rendered = renderer.render_page(FIXTURES_DIR / "one_page_english.pdf", 1, dpi=300, color_mode="rgb", image_format="png")
    result = provider.recognize(rendered.image_bytes, language_hints=["eng"], configuration=configuration, tessdata_dir=DEFAULT_TESSDATA_DIR)

    assert str(DEFAULT_TESSDATA_DIR) not in str(result.provider_metadata_safe)
