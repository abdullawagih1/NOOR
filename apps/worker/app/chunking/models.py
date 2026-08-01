"""
Typed chunking models. Plain dataclasses, matching
app/pdf_extraction/models.py and app/ocr/models.py's convention — these
never cross an HTTP boundary directly; app/chunking/pipeline.py converts
them to RPC arguments or the canonical artifact dict.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class PageRepresentation:
    """One page's canonical accepted text, as returned by the Worker-only
    get_document_chunking_job_context RPC (migration 0012)."""

    page_number: int
    representation_type: str  # "native" | "ocr"
    representation_id: str
    text_checksum: str
    normalized_text: str
    character_count: int
    word_count: int
    warning_state: bool


@dataclass(frozen=True)
class Block:
    """A deterministic, non-semantic structural hint within one page's
    text — a technical hint only, never claimed as clinically validated
    document structure (ADR 0014). Blocks from detect_blocks() always tile
    their page's full text with zero gaps and zero overlap."""

    text: str
    start_offset: int  # zero-based, into the page's normalized_text
    end_offset: int  # exclusive
    block_type: str  # "paragraph" | "list_item" | "heading_candidate" | "table_like"
    split_reason: str | None = None  # set only on fragments produced by the oversized-block fallback


@dataclass
class SourceSpanDraft:
    page_number: int
    representation_type: str
    representation_id: str
    representation_checksum: str
    start_offset: int
    end_offset: int
    source_fragment_checksum: str
    span_order: int
    block_type_hint: str | None
    boundary_reason: str | None


@dataclass
class ChunkDraft:
    chunk_index: int
    chunk_text: str
    chunk_checksum: str
    page_start: int
    page_end: int
    token_count: int
    character_count: int
    word_count: int
    heading_context: str | None
    block_type_summary: list[str]
    boundary_start_reason: str
    boundary_end_reason: str
    contains_native_text: bool
    contains_ocr_text: bool
    warning_state: bool
    warnings: list[str] = field(default_factory=list)
    source_spans: list[SourceSpanDraft] = field(default_factory=list)
