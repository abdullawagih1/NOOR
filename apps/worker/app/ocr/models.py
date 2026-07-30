"""
Typed OCR result models. Plain dataclasses, matching
app/pdf_extraction/models.py's convention — these never cross an HTTP
boundary directly; the pipeline/processor convert them to RPC arguments
or the canonical artifact dict.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class RenderedPage:
    """One deterministically-rendered page image. The image bytes
    themselves are never persisted by default (mission §17) — only the
    checksum is recorded; the caller is responsible for deleting the
    encoded bytes once OCR has consumed them."""

    image_bytes: bytes
    width_px: int
    height_px: int
    checksum: str


@dataclass(frozen=True)
class OcrPageResult:
    raw_text: str
    normalized_text: str
    character_count: int
    word_count: int
    text_checksum: str
    confidence_summary: dict
    warnings: list[str] = field(default_factory=list)
    provider_metadata_safe: dict = field(default_factory=dict)
