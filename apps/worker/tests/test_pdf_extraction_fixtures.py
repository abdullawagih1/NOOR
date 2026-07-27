"""
Extractor behavior against the synthetic fixture suite (mission §31, §33,
§34). Every fixture is generated, static, and committed —
tests/fixtures/pdf/generate_fixtures.py is a one-off authoring script, not
run at test time.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from app.pdf_extraction.config import ExtractionConfiguration
from app.pdf_extraction.errors import ExtractionError
from app.pdf_extraction.extractor import PyPdfExtractor

FIXTURES_DIR = Path(__file__).parent / "fixtures" / "pdf"


@pytest.fixture
def extractor() -> PyPdfExtractor:
    return PyPdfExtractor("6.14.2")


@pytest.fixture
def configuration() -> ExtractionConfiguration:
    return ExtractionConfiguration()


def test_one_page_english(extractor, configuration):
    result = extractor.extract(FIXTURES_DIR / "one_page_english.pdf", configuration=configuration)
    assert result.page_count == 1
    assert result.pages[0].extraction_status == "text_extracted"
    assert result.pages[0].character_count > 0
    assert "noor" in result.pages[0].normalized_text.lower()


def test_multi_page(extractor, configuration):
    result = extractor.extract(FIXTURES_DIR / "multi_page.pdf", configuration=configuration)
    assert result.page_count == 5
    assert [p.page_number for p in result.pages] == [1, 2, 3, 4, 5]
    assert all(p.extraction_status == "text_extracted" for p in result.pages)


def test_arabic_and_english(extractor, configuration):
    result = extractor.extract(FIXTURES_DIR / "arabic_and_english.pdf", configuration=configuration)
    assert result.page_count == 1
    text = result.pages[0].normalized_text
    assert "english" in text.lower()
    # Genuine Arabic Unicode codepoints must survive extraction+normalization
    # unmodified — never transliterated, never reordered by our own code.
    assert any(0x0600 <= ord(ch) <= 0x06FF for ch in text)


def test_empty_page_is_blank_not_scanned(extractor, configuration):
    result = extractor.extract(FIXTURES_DIR / "empty_page.pdf", configuration=configuration)
    page = result.pages[0]
    assert page.is_blank is True
    assert page.suspected_scanned is False
    assert page.extraction_status == "blank_page"
    assert page.character_count == 0


def test_rotated_page_records_rotation(extractor, configuration):
    result = extractor.extract(FIXTURES_DIR / "rotated_page.pdf", configuration=configuration)
    assert result.pages[0].rotation_degrees == 90
    assert result.rotated_page_count == 1


def test_mixed_blank_and_text(extractor, configuration):
    result = extractor.extract(FIXTURES_DIR / "mixed_blank_and_text.pdf", configuration=configuration)
    assert result.page_count == 3
    assert result.pages[0].is_blank is False
    assert result.pages[1].is_blank is True
    assert result.pages[2].is_blank is False
    assert result.blank_page_count == 1


def test_image_only_page_is_suspected_scanned(extractor, configuration):
    result = extractor.extract(FIXTURES_DIR / "image_only_no_text_layer.pdf", configuration=configuration)
    page = result.pages[0]
    assert page.is_blank is True
    assert page.suspected_scanned is True
    assert page.extraction_status == "no_text_layer"
    assert any("suspected_scanned" in w for w in page.warnings)


def test_unusual_metadata_does_not_crash(extractor, configuration):
    result = extractor.extract(FIXTURES_DIR / "unusual_metadata.pdf", configuration=configuration)
    assert result.page_count == 1
    # Long/unusual metadata values are passed through as plain strings, not
    # rejected or truncated silently.
    assert isinstance(result.document_metadata.get("Author", ""), str)


def test_corrupt_pdf_raises_corrupt_pdf(extractor, configuration):
    with pytest.raises(ExtractionError) as excinfo:
        extractor.extract(FIXTURES_DIR / "corrupt.pdf", configuration=configuration)
    assert excinfo.value.error_code == "corrupt_pdf"
    assert excinfo.value.retryable is False


def test_encrypted_pdf_raises_password_protected(extractor, configuration):
    with pytest.raises(ExtractionError) as excinfo:
        extractor.extract(FIXTURES_DIR / "encrypted.pdf", configuration=configuration)
    assert excinfo.value.error_code == "password_protected_pdf"
    assert excinfo.value.retryable is False


def test_invalid_signature_raises_invalid_pdf_signature(extractor, configuration):
    with pytest.raises(ExtractionError) as excinfo:
        extractor.extract(FIXTURES_DIR / "invalid_signature.pdf", configuration=configuration)
    assert excinfo.value.error_code == "invalid_pdf_signature"
    assert excinfo.value.retryable is False


def test_no_extraction_error_message_leaks_internals(extractor, configuration):
    """Every raised ExtractionError's safe message must never include a
    local file path (mission §15: 'Never expose temp paths in user-facing
    errors')."""
    for fixture in ["corrupt.pdf", "encrypted.pdf", "invalid_signature.pdf"]:
        path = FIXTURES_DIR / fixture
        try:
            extractor.extract(path, configuration=configuration)
        except ExtractionError as exc:
            assert str(path) not in exc.message_safe
            assert "tests/fixtures" not in exc.message_safe
