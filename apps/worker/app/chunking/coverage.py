"""
Coverage/duplication proof (ADR 0014, the mission's mandatory acceptance
gate) — computed independently of how chunks were assembled, so a
segmentation bug cannot silently report false coverage. Character-level:
for every page, the union of its chunks' source-span ranges must equal
exactly [0, character_count) with no gaps and no overlaps.

This is a genuine verification pass, not a restatement of an assumption —
app/chunking/segmentation.py's tiling guarantee is what SHOULD make
coverage 100% and duplication 0%, but this module recomputes both from
the actual emitted spans so a bug there is caught here, before
finalize_document_chunking_run's own SQL-level gate (migration 0012) is
ever reached.
"""
from __future__ import annotations

from app.chunking.models import ChunkDraft, PageRepresentation


def compute_coverage_and_duplication(
    pages: list[PageRepresentation], chunks: list[ChunkDraft]
) -> tuple[float, float, list[str]]:
    warnings: list[str] = []
    total_characters = 0
    covered_characters = 0
    duplicated_characters = 0

    spans_by_page: dict[int, list[tuple[int, int]]] = {}
    for chunk in chunks:
        for span in chunk.source_spans:
            spans_by_page.setdefault(span.page_number, []).append((span.start_offset, span.end_offset))

    for page in pages:
        length = page.character_count
        total_characters += length
        if length == 0:
            continue

        covered = bytearray(length)
        for start, end in sorted(spans_by_page.get(page.page_number, [])):
            clamped_end = min(end, length)
            for i in range(max(start, 0), clamped_end):
                if covered[i]:
                    duplicated_characters += 1
                covered[i] = 1

        page_covered = sum(covered)
        covered_characters += page_covered
        if page_covered != length:
            warnings.append(f"page {page.page_number}: incomplete coverage ({page_covered}/{length} characters)")

    if total_characters == 0:
        return 100.0, 0.0, warnings

    coverage_percentage = round((covered_characters / total_characters) * 100, 6)
    duplication_percentage = round((duplicated_characters / total_characters) * 100, 6)
    return coverage_percentage, duplication_percentage, warnings
