"""
Document-level determinism, coverage, and provenance proofs for the
chunking pipeline (Sprint 1-D3, ADR 0014) — the same discipline
test_pdf_extraction_determinism.py and test_ocr_processor.py apply one
layer downstream: identical accepted input + identical pipeline/
configuration/tokenizer versions must produce byte-identical canonical
artifacts, and every chunk's source spans must reconstruct exactly 100%
of each page's text with zero duplication.
"""
from __future__ import annotations

from app.chunking.artifact import build_canonical_chunking_artifact, chunks_to_rpc_payload
from app.chunking.checksums import canonical_bytes, compute_artifact_checksum
from app.chunking.chunker import build_chunks_for_document
from app.chunking.config import HARD_MAXIMUM_CHUNK_TOKENS
from app.chunking.coverage import compute_coverage_and_duplication
from app.chunking.manifest import build_input_manifest, compute_input_manifest_sha256
from app.chunking.models import PageRepresentation
from app.chunking.pipeline import build_pages_from_context_rows, run_chunking_pipeline

ENGLISH_PAGE_TEXT = (
    "Clinical Guideline Overview\n\n"
    "This section describes the general approach to patient triage in "
    "the emergency department, covering initial assessment and priority "
    "assignment for incoming cases.\n\n"
    "- Assess airway, breathing, circulation\n"
    "- Record vital signs\n"
    "- Assign triage category\n\n"
    "Escalation to a senior clinician is required whenever any vital "
    "sign falls outside the locally defined safe range for the patient's age group.\n"
)

ARABIC_PAGE_TEXT = (
    "نظرة عامة على الدليل السريري\n\n"
    "يصف هذا القسم النهج العام لفرز المرضى في قسم الطوارئ، بما في ذلك "
    "التقييم الأولي وتحديد الأولويات للحالات الواردة.\n\n"
    "- تقييم مجرى الهواء والتنفس والدورة الدموية\n"
    "- تسجيل العلامات الحيوية\n\n"
    "التصعيد إلى طبيب أول مطلوب كلما خرجت أي علامة حيوية عن النطاق الآمن.\n"
)


def _page(number: int, text: str, representation_type: str = "native", warning_state: bool = False) -> PageRepresentation:
    return PageRepresentation(
        page_number=number,
        representation_type=representation_type,
        representation_id=f"00000000-0000-0000-0000-00000000000{number}",
        text_checksum=f"checksum-{number}",
        normalized_text=text,
        character_count=len(text),
        word_count=len(text.split()),
        warning_state=warning_state,
    )


def _run(pages: list[PageRepresentation]):
    return run_chunking_pipeline(
        pages=pages,
        source_document_id="10000000-0000-0000-0000-000000000001",
        source_sha256="a" * 64,
        extraction_run_id="20000000-0000-0000-0000-000000000001",
        input_manifest=build_input_manifest(pages),
        input_manifest_sha256=compute_input_manifest_sha256(build_input_manifest(pages)),
        pipeline_version="controlled-page-aware-chunking-v1",
        configuration_version="1",
        normalization_version="1",
        tokenizer_name="noor-simple-tokenizer",
        tokenizer_version="1",
        organization_id="30000000-0000-0000-0000-000000000001",
    )


# ---------------------------------------------------------------------------
# Coverage / duplication — the mandatory acceptance gate
# ---------------------------------------------------------------------------


def test_english_page_achieves_full_coverage_and_zero_duplication():
    pages = [_page(1, ENGLISH_PAGE_TEXT)]
    chunks = build_chunks_for_document(pages)
    coverage, duplication, warnings = compute_coverage_and_duplication(pages, chunks)
    assert coverage == 100.0
    assert duplication == 0.0
    assert warnings == []


def test_arabic_page_achieves_full_coverage_and_zero_duplication():
    pages = [_page(1, ARABIC_PAGE_TEXT)]
    chunks = build_chunks_for_document(pages)
    coverage, duplication, warnings = compute_coverage_and_duplication(pages, chunks)
    assert coverage == 100.0
    assert duplication == 0.0
    assert warnings == []


def test_multi_page_mixed_language_document_achieves_full_coverage():
    pages = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT), _page(3, ENGLISH_PAGE_TEXT + ARABIC_PAGE_TEXT)]
    chunks = build_chunks_for_document(pages)
    coverage, duplication, warnings = compute_coverage_and_duplication(pages, chunks)
    assert coverage == 100.0
    assert duplication == 0.0
    assert warnings == []


def test_empty_page_is_vacuously_fully_covered():
    pages = [_page(1, "")]
    chunks = build_chunks_for_document(pages)
    assert chunks == []
    coverage, duplication, _ = compute_coverage_and_duplication(pages, chunks)
    assert coverage == 100.0
    assert duplication == 0.0


def test_oversized_paragraph_still_achieves_full_coverage_and_respects_hard_maximum():
    long_paragraph = "This is a repeated clinical sentence for load testing purposes. " * 200
    pages = [_page(1, long_paragraph)]
    chunks = build_chunks_for_document(pages)
    assert len(chunks) > 1
    assert all(c.token_count <= HARD_MAXIMUM_CHUNK_TOKENS for c in chunks)
    coverage, duplication, warnings = compute_coverage_and_duplication(pages, chunks)
    assert coverage == 100.0
    assert duplication == 0.0
    assert warnings == []


# ---------------------------------------------------------------------------
# V1 hard page-boundary policy — never cross a page, never overlap pages
# ---------------------------------------------------------------------------


def test_no_chunk_ever_crosses_a_page_boundary():
    pages = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT)]
    chunks = build_chunks_for_document(pages)
    for chunk in chunks:
        assert chunk.page_start == chunk.page_end
        assert len(chunk.source_spans) == 1
        assert chunk.source_spans[0].page_number == chunk.page_start


def test_chunk_indices_are_globally_sequential_across_pages():
    pages = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT)]
    chunks = build_chunks_for_document(pages)
    indices = [c.chunk_index for c in chunks]
    assert indices == list(range(1, len(chunks) + 1))


# ---------------------------------------------------------------------------
# Provenance — every chunk's span reconstructs exactly the right substring
# ---------------------------------------------------------------------------


def test_chunk_text_matches_its_own_source_span_exactly():
    pages = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT)]
    chunks = build_chunks_for_document(pages)
    pages_by_number = {p.page_number: p for p in pages}
    for chunk in chunks:
        span = chunk.source_spans[0]
        page_text = pages_by_number[span.page_number].normalized_text
        assert page_text[span.start_offset : span.end_offset] == chunk.chunk_text


def test_source_span_offsets_are_zero_based_start_inclusive_end_exclusive():
    pages = [_page(1, "abcdefghij")]
    chunks = build_chunks_for_document(pages)
    assert len(chunks) == 1
    span = chunks[0].source_spans[0]
    assert span.start_offset == 0
    assert span.end_offset == 10


# ---------------------------------------------------------------------------
# Determinism — the identity contract every downstream schema relies on
# ---------------------------------------------------------------------------


def test_identical_input_produces_identical_chunk_checksums():
    pages_1 = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT)]
    pages_2 = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT)]
    checksums_1 = [c.chunk_checksum for c in build_chunks_for_document(pages_1)]
    checksums_2 = [c.chunk_checksum for c in build_chunks_for_document(pages_2)]
    assert checksums_1 == checksums_2
    assert len(checksums_1) > 0


def test_input_manifest_is_deterministic_and_order_independent():
    pages_in_order = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT)]
    pages_reversed = [_page(2, ARABIC_PAGE_TEXT), _page(1, ENGLISH_PAGE_TEXT)]
    manifest_1 = build_input_manifest(pages_in_order)
    manifest_2 = build_input_manifest(pages_reversed)
    assert compute_input_manifest_sha256(manifest_1) == compute_input_manifest_sha256(manifest_2)


def test_input_manifest_changes_when_a_page_representation_changes():
    pages_native = [_page(1, ENGLISH_PAGE_TEXT, representation_type="native")]
    pages_ocr = [_page(1, ENGLISH_PAGE_TEXT, representation_type="ocr")]
    manifest_1 = build_input_manifest(pages_native)
    manifest_2 = build_input_manifest(pages_ocr)
    assert compute_input_manifest_sha256(manifest_1) != compute_input_manifest_sha256(manifest_2)


def test_full_pipeline_produces_byte_identical_artifacts_for_identical_input():
    pages_1 = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT)]
    pages_2 = [_page(1, ENGLISH_PAGE_TEXT), _page(2, ARABIC_PAGE_TEXT)]
    outcome_1 = _run(pages_1)
    outcome_2 = _run(pages_2)
    assert outcome_1.artifact_bytes == outcome_2.artifact_bytes
    assert outcome_1.artifact_sha256 == outcome_2.artifact_sha256


def test_full_pipeline_artifact_bytes_contain_no_wall_clock_timestamp():
    outcome = _run([_page(1, ENGLISH_PAGE_TEXT)])
    payload = outcome.artifact_bytes.decode("utf-8")
    assert '"created_at"' not in payload
    assert '"generated_at"' not in payload
    assert '"processed_at"' not in payload


def test_different_input_produces_different_artifact_checksum():
    outcome_1 = _run([_page(1, ENGLISH_PAGE_TEXT)])
    outcome_2 = _run([_page(1, ARABIC_PAGE_TEXT)])
    assert outcome_1.artifact_sha256 != outcome_2.artifact_sha256


# ---------------------------------------------------------------------------
# Context-row conversion — the Worker-only RPC boundary
# ---------------------------------------------------------------------------


def test_build_pages_from_context_rows_recomputes_character_count_after_normalization():
    # A precomposed vs. decomposed accented character: NFC normalization
    # can change the character count, so it must be measured on the
    # normalized text the pipeline actually chunks, never trusted
    # verbatim from the DB row's own count.
    decomposed = "é"  # 'e' + combining acute accent = 2 codepoints
    rows = [
        {
            "out_page_number": 1,
            "out_representation_type": "native",
            "out_representation_id": "00000000-0000-0000-0000-000000000001",
            "out_text_checksum": "checksum-1",
            "out_normalized_text": decomposed,
            "out_character_count": 2,  # the DB's own pre-normalization count
            "out_word_count": 1,
            "out_warning_state": False,
        }
    ]
    pages = build_pages_from_context_rows(rows)
    assert pages[0].character_count == 1  # NFC composes to a single 'é'


def test_build_pages_from_context_rows_sorts_by_page_number():
    rows = [
        {"out_page_number": 2, "out_representation_type": "native", "out_representation_id": "id-2", "out_text_checksum": "c2", "out_normalized_text": "b", "out_character_count": 1, "out_word_count": 1, "out_warning_state": False},
        {"out_page_number": 1, "out_representation_type": "native", "out_representation_id": "id-1", "out_text_checksum": "c1", "out_normalized_text": "a", "out_character_count": 1, "out_word_count": 1, "out_warning_state": False},
    ]
    pages = build_pages_from_context_rows(rows)
    assert [p.page_number for p in pages] == [1, 2]


# ---------------------------------------------------------------------------
# RPC payload shape — must match finalize_document_chunking_run's expected keys
# ---------------------------------------------------------------------------


def test_chunks_to_rpc_payload_uses_the_keys_finalize_document_chunking_run_expects():
    pages = [_page(1, ENGLISH_PAGE_TEXT)]
    chunks = build_chunks_for_document(pages)
    payload = chunks_to_rpc_payload(chunks)
    assert payload, "expected at least one chunk"
    chunk_dict = payload[0]
    for key in ("chunk_index", "chunk_text", "chunk_checksum", "page_start", "page_end", "token_count", "source_spans"):
        assert key in chunk_dict
    span_dict = chunk_dict["source_spans"][0]
    for key in ("page_number", "representation_type", "representation_id", "start_offset", "end_offset", "span_order"):
        assert key in span_dict
