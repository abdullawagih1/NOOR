"""
Typed extraction result models (mission §9). Plain dataclasses, not
pydantic — these never cross an HTTP boundary directly (the artifact
serializer converts them to the canonical JSON dict; the RPC client
converts summary fields to plain function arguments), so pydantic's
validation/coercion machinery isn't needed here.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

PageExtractionStatus = Literal[
    "text_extracted", "blank_page", "no_text_layer", "partial_text", "extraction_warning", "failed"
]


@dataclass(frozen=True)
class ExtractedPage:
    page_number: int
    width_points: float | None
    height_points: float | None
    rotation_degrees: int
    raw_text: str
    normalized_text: str
    character_count: int
    word_count: int
    is_blank: bool
    suspected_scanned: bool
    extraction_status: PageExtractionStatus
    warnings: list[str]
    page_checksum: str


@dataclass(frozen=True)
class ExtractionResult:
    document_metadata: dict
    pages: list[ExtractedPage]
    warnings: list[str] = field(default_factory=list)

    @property
    def page_count(self) -> int:
        return len(self.pages)

    @property
    def pages_with_text(self) -> int:
        return sum(1 for p in self.pages if p.extraction_status in ("text_extracted", "partial_text"))

    @property
    def blank_page_count(self) -> int:
        return sum(1 for p in self.pages if p.is_blank)

    @property
    def suspected_scanned_page_count(self) -> int:
        return sum(1 for p in self.pages if p.suspected_scanned)

    @property
    def total_character_count(self) -> int:
        return sum(p.character_count for p in self.pages)

    @property
    def total_word_count(self) -> int:
        return sum(p.word_count for p in self.pages)

    @property
    def rotated_page_count(self) -> int:
        return sum(1 for p in self.pages if p.rotation_degrees % 360 != 0)

    @property
    def warning_count(self) -> int:
        return len(self.warnings) + sum(len(p.warnings) for p in self.pages)

    @property
    def average_characters_per_page(self) -> float:
        return self.total_character_count / self.page_count if self.page_count else 0.0

    @property
    def minimum_characters_on_nonblank_page(self) -> int | None:
        counts = [p.character_count for p in self.pages if not p.is_blank]
        return min(counts) if counts else None

    @property
    def maximum_characters_on_page(self) -> int | None:
        counts = [p.character_count for p in self.pages]
        return max(counts) if counts else None
