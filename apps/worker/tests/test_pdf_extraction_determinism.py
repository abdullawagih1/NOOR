"""
Determinism proof (mission §32): identical source bytes + identical
pipeline/configuration/extractor versions must produce byte-identical
canonical artifacts, identical artifact SHA-256, and identical page
checksums across independent extraction runs.
"""
from __future__ import annotations

from pathlib import Path

from app.pdf_extraction.artifact import build_canonical_artifact
from app.pdf_extraction.checksums import canonical_artifact_bytes, compute_artifact_checksum
from app.pdf_extraction.config import ExtractionConfiguration
from app.pdf_extraction.extractor import PyPdfExtractor

FIXTURES_DIR = Path(__file__).parent / "fixtures" / "pdf"


def _extract_and_build_artifact(fixture_name: str):
    extractor = PyPdfExtractor("6.14.2")
    configuration = ExtractionConfiguration()
    result = extractor.extract(FIXTURES_DIR / fixture_name, configuration=configuration)
    artifact = build_canonical_artifact(
        source_document_id="00000000-0000-0000-0000-000000000001",
        source_sha256="a" * 64,
        source_size_bytes=(FIXTURES_DIR / fixture_name).stat().st_size,
        pipeline_version="pdf-text-v1",
        configuration_version="1",
        extractor_name=extractor.name,
        extractor_version=extractor.version,
        result=result,
    )
    return result, artifact


def test_same_fixture_twice_produces_identical_artifact_bytes():
    _, artifact_1 = _extract_and_build_artifact("multi_page.pdf")
    _, artifact_2 = _extract_and_build_artifact("multi_page.pdf")
    assert canonical_artifact_bytes(artifact_1) == canonical_artifact_bytes(artifact_2)


def test_same_fixture_twice_produces_identical_artifact_checksum():
    _, artifact_1 = _extract_and_build_artifact("arabic_and_english.pdf")
    _, artifact_2 = _extract_and_build_artifact("arabic_and_english.pdf")
    assert compute_artifact_checksum(artifact_1) == compute_artifact_checksum(artifact_2)


def test_same_fixture_twice_produces_identical_page_checksums():
    result_1, _ = _extract_and_build_artifact("mixed_blank_and_text.pdf")
    result_2, _ = _extract_and_build_artifact("mixed_blank_and_text.pdf")
    checksums_1 = [p.page_checksum for p in result_1.pages]
    checksums_2 = [p.page_checksum for p in result_2.pages]
    assert checksums_1 == checksums_2
    assert len(set(checksums_1)) == len(checksums_1), "distinct pages must not collide on checksum"


def test_same_fixture_twice_produces_identical_metrics():
    result_1, _ = _extract_and_build_artifact("multi_page.pdf")
    result_2, _ = _extract_and_build_artifact("multi_page.pdf")
    assert result_1.page_count == result_2.page_count
    assert result_1.total_character_count == result_2.total_character_count
    assert result_1.total_word_count == result_2.total_word_count
    assert result_1.blank_page_count == result_2.blank_page_count
    assert result_1.suspected_scanned_page_count == result_2.suspected_scanned_page_count


def test_different_fixtures_produce_different_artifact_checksums():
    _, artifact_1 = _extract_and_build_artifact("one_page_english.pdf")
    _, artifact_2 = _extract_and_build_artifact("multi_page.pdf")
    assert compute_artifact_checksum(artifact_1) != compute_artifact_checksum(artifact_2)


def test_artifact_bytes_do_not_contain_a_wall_clock_timestamp():
    """No processing timestamp may leak into the hashed content — the
    determinism contract is about the *artifact*, not about when it was
    produced (mission §12)."""
    _, artifact = _extract_and_build_artifact("one_page_english.pdf")
    payload = canonical_artifact_bytes(artifact).decode("utf-8")
    # A real wall-clock timestamp field would appear as an ISO-ish string;
    # the only date-like content allowed is whatever the source PDF's own
    # embedded metadata legitimately contains (not asserted here), never a
    # field we introduced ourselves.
    assert '"created_at"' not in payload
    assert '"generated_at"' not in payload
    assert '"processed_at"' not in payload
