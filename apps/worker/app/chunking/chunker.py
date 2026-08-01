"""
Assembles the deterministic blocks from app/chunking/segmentation.py into
document_chunks-shaped drafts: a greedy, deterministic bin-pack toward
TARGET_CHUNK_TOKENS, splitting any single block over
HARD_MAXIMUM_CHUNK_TOKENS via the oversized-block fallback first.

Because detect_blocks() always tiles a page's text with zero gaps
(app/chunking/segmentation.py), a "chunk" here is always exactly one
contiguous character range of exactly one page — which is also why each
chunk needs only a single source span (V1's hard page-boundary policy,
ADR 0014, makes multi-span chunks unnecessary).
"""
from __future__ import annotations

from app.chunking.checksums import compute_text_checksum
from app.chunking.config import HARD_MAXIMUM_CHUNK_TOKENS, MINIMUM_CHUNK_TOKENS, TARGET_CHUNK_TOKENS
from app.chunking.models import Block, ChunkDraft, PageRepresentation, SourceSpanDraft
from app.chunking.segmentation import detect_blocks, split_oversized_block
from app.chunking.tokenizer import count_tokens


def expand_and_group_blocks(blocks: list[Block]) -> list[list[Block]]:
    """Greedily bin-packs blocks toward TARGET_CHUNK_TOKENS. A fragment
    produced by the oversized-block fallback (block.split_reason is set)
    is NOT forced into its own chunk — e.g. a large paragraph with no
    blank-line breaks that gets split at sentence boundaries should still
    be re-packed up toward the target, not shattered into one
    below-minimum chunk per sentence. The only hard rule is that no
    accumulated group may ever exceed HARD_MAXIMUM_CHUNK_TOKENS, which is
    checked unconditionally (unlike the soft TARGET check, which is
    skipped while the group is still under MINIMUM_CHUNK_TOKENS)."""
    expanded: list[Block] = []
    for block in blocks:
        if count_tokens(block.text) > HARD_MAXIMUM_CHUNK_TOKENS:
            expanded.extend(split_oversized_block(block))
        else:
            expanded.append(block)

    groups: list[list[Block]] = []
    current: list[Block] = []
    current_tokens = 0
    for block in expanded:
        tokens = count_tokens(block.text)
        would_exceed_hard_maximum = current_tokens + tokens > HARD_MAXIMUM_CHUNK_TOKENS
        would_exceed_soft_target = current_tokens + tokens > TARGET_CHUNK_TOKENS and current_tokens >= MINIMUM_CHUNK_TOKENS
        if current and (would_exceed_hard_maximum or would_exceed_soft_target):
            groups.append(current)
            current, current_tokens = [], 0
        current.append(block)
        current_tokens += tokens
    if current:
        groups.append(current)
    return groups


def build_chunk_draft(page: PageRepresentation, block_group: list[Block], chunk_index: int) -> ChunkDraft:
    start = block_group[0].start_offset
    end = block_group[-1].end_offset
    chunk_text = page.normalized_text[start:end]
    token_count = count_tokens(chunk_text)
    block_types = [b.block_type for b in block_group]
    heading_context = next((b.text.strip() for b in block_group if b.block_type == "heading_candidate"), None)

    hard_split_reasons = sorted({b.split_reason for b in block_group if b.split_reason})
    warnings: list[str] = []
    if token_count < MINIMUM_CHUNK_TOKENS:
        warnings.append("chunk_below_minimum_tokens")
    if hard_split_reasons:
        warnings.append("hard_split:" + ",".join(hard_split_reasons))

    unique_types = sorted(set(block_types))
    span = SourceSpanDraft(
        page_number=page.page_number,
        representation_type=page.representation_type,
        representation_id=page.representation_id,
        representation_checksum=page.text_checksum,
        start_offset=start,
        end_offset=end,
        source_fragment_checksum=compute_text_checksum(chunk_text),
        span_order=1,
        block_type_hint=unique_types[0] if len(unique_types) == 1 else "mixed",
        boundary_reason="hard_split" if hard_split_reasons else "block_boundary",
    )

    boundary_start_reason = "hard_split" if block_group[0].split_reason else ("page_start" if start == 0 else "block_boundary")
    boundary_end_reason = "hard_split" if block_group[-1].split_reason else ("page_end" if end == len(page.normalized_text) else "block_boundary")

    return ChunkDraft(
        chunk_index=chunk_index,
        chunk_text=chunk_text,
        chunk_checksum=compute_text_checksum(chunk_text),
        page_start=page.page_number,
        page_end=page.page_number,
        token_count=token_count,
        character_count=len(chunk_text),
        word_count=len(chunk_text.split()),
        heading_context=heading_context,
        block_type_summary=unique_types,
        boundary_start_reason=boundary_start_reason,
        boundary_end_reason=boundary_end_reason,
        contains_native_text=(page.representation_type == "native"),
        contains_ocr_text=(page.representation_type == "ocr"),
        warning_state=bool(warnings) or page.warning_state,
        warnings=warnings,
        source_spans=[span],
    )


def build_chunks_for_document(pages: list[PageRepresentation]) -> list[ChunkDraft]:
    chunks: list[ChunkDraft] = []
    chunk_index = 1
    for page in sorted(pages, key=lambda p: p.page_number):
        if not page.normalized_text:
            continue
        blocks = detect_blocks(page.normalized_text)
        if not blocks:
            continue
        for group in expand_and_group_blocks(blocks):
            chunks.append(build_chunk_draft(page, group, chunk_index))
            chunk_index += 1
    return chunks
