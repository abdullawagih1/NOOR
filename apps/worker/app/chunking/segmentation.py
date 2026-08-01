"""
Deterministic, non-semantic block segmentation (ADR 0014) and the
oversized-block fallback cascade (mission's required strict order:
sentence -> line -> punctuation-safe -> tokenizer-window).

`detect_blocks()` always returns blocks that tile the ENTIRE input text
with zero gaps and zero overlap — including blank lines and inter-block
whitespace, which are absorbed into the start of the block that follows
them (or the end of the last block, for trailing whitespace). This is
deliberate: it is what makes 100%-coverage, contiguous chunk source spans
possible without a separate "gap-filling" pass later (see
app/chunking/coverage.py and docs/domain/chunk-provenance-and-source-spans.md).

Block *type* classification (paragraph/list_item/heading_candidate/
table_like) is a technical hint only — never a claim of real document
structure, table reconstruction, or clinical section identity (ADR 0014,
mission's explicit out-of-scope list).
"""
from __future__ import annotations

import re

from app.chunking.config import HARD_MAXIMUM_CHUNK_TOKENS
from app.chunking.models import Block
from app.chunking.tokenizer import count_tokens

_LIST_MARKER = re.compile(r"^\s*([-*•]|\d+[.)]|[٠-٩]+[.)])\s+")
_MULTI_WHITESPACE = re.compile(r"\s{2,}|\t")
_SENTENCE_END = re.compile(r"(?<=[.!?؟؛])\s+")
_LINE_BREAK = re.compile(r"\n")
_PUNCTUATION_SAFE = re.compile(r"(?<=[,;:،])\s+")

_HEADING_MAX_LENGTH = 80
_SENTENCE_END_CHARS = ".!?؟؛"


def detect_blocks(text: str) -> list[Block]:
    """Splits `text` into content-line groups (separated by blank lines),
    classifies each group, then expands group boundaries so consecutive
    blocks are contiguous across the full text (see module docstring)."""
    if not text:
        return []

    lines: list[tuple[int, int, str]] = []
    line_start = 0
    for i, ch in enumerate(text):
        if ch == "\n":
            lines.append((line_start, i, text[line_start:i]))
            line_start = i + 1
    lines.append((line_start, len(text), text[line_start:]))

    groups: list[list[tuple[int, int, str]]] = []
    current: list[tuple[int, int, str]] = []
    for entry in lines:
        _, _, line_text = entry
        if line_text.strip() == "":
            if current:
                groups.append(current)
                current = []
        else:
            current.append(entry)
    if current:
        groups.append(current)

    if not groups:
        # The whole page is blank/whitespace-only — one paragraph block
        # covering everything, so coverage still accounts for every
        # character even though there is no real content to chunk.
        return [Block(text=text, start_offset=0, end_offset=len(text), block_type="paragraph")]

    classified: list[tuple[int, int, str]] = []  # (content_start, content_end, block_type)
    for group in groups:
        group_start = group[0][0]
        group_end = group[-1][1]
        group_text = text[group_start:group_end]
        block_type = _classify_group(group, group_text)
        classified.append((group_start, group_end, block_type))

    # Tile: absorb each inter-group gap (blank lines, trailing/leading
    # whitespace) entirely into the END of the preceding block, so the
    # next block's start is always exactly the previous block's end — a
    # single forward pass, not two independently-computed boundaries
    # (which would double-count the gap as both a trailing region of one
    # block and a leading region of the next, producing an overlap).
    blocks: list[Block] = []
    boundary = 0
    for i, (_content_start, _content_end, block_type) in enumerate(classified):
        end = len(text) if i == len(classified) - 1 else classified[i + 1][0]
        blocks.append(Block(text=text[boundary:end], start_offset=boundary, end_offset=end, block_type=block_type))
        boundary = end
    return blocks


def _classify_group(group: list[tuple[int, int, str]], group_text: str) -> str:
    list_line_count = sum(1 for (_, _, lt) in group if _LIST_MARKER.match(lt))
    if list_line_count == len(group) and list_line_count > 0:
        return "list_item"

    if len(group) == 1 and len(group_text.strip()) <= _HEADING_MAX_LENGTH and group_text.strip()[-1:] not in _SENTENCE_END_CHARS:
        return "heading_candidate"

    table_line_count = sum(1 for (_, _, lt) in group if len(_MULTI_WHITESPACE.findall(lt)) >= 2)
    if len(group) >= 2 and table_line_count == len(group):
        return "table_like"

    return "paragraph"


def split_oversized_block(block: Block) -> list[Block]:
    """Recursively splits a block exceeding HARD_MAXIMUM_CHUNK_TOKENS,
    trying each fallback strategy in the mission's required strict order
    before falling back to a guaranteed-terminating tokenizer-window
    split. Every returned fragment still tiles the original block's exact
    [start_offset, end_offset) range with zero gaps."""
    if count_tokens(block.text) <= HARD_MAXIMUM_CHUNK_TOKENS:
        return [block]

    for reason, pattern in (("sentence_boundary", _SENTENCE_END), ("line_boundary", _LINE_BREAK), ("punctuation_boundary", _PUNCTUATION_SAFE)):
        pieces = _split_keep_offsets(block.text, pattern)
        if len(pieces) > 1:
            result: list[Block] = []
            for start, end, piece_text in pieces:
                sub_block = Block(
                    text=piece_text,
                    start_offset=block.start_offset + start,
                    end_offset=block.start_offset + end,
                    block_type=block.block_type,
                    split_reason=reason,
                )
                result.extend(split_oversized_block(sub_block))
            return result

    return _tokenizer_window_split(block)


def _split_keep_offsets(text: str, pattern: re.Pattern) -> list[tuple[int, int, str]]:
    """Splits on `pattern`, keeping the matched separator attached to the
    PRECEDING piece so pieces tile the input with zero gaps."""
    pieces: list[tuple[int, int, str]] = []
    start = 0
    for match in pattern.finditer(text):
        end = match.end()
        if end > start:
            pieces.append((start, end, text[start:end]))
            start = end
    if start < len(text):
        pieces.append((start, len(text), text[start:len(text)]))
    return pieces


def _tokenizer_window_split(block: Block) -> list[Block]:
    """Last-resort fallback: binary-searches the largest prefix that stays
    within HARD_MAXIMUM_CHUNK_TOKENS, preferring to cut at the nearest
    preceding space when one exists (never mid-word if avoidable).
    Guaranteed to terminate — every step consumes at least one character —
    so this is the fallback of last resort, never silent truncation."""
    text = block.text
    n = len(text)
    pieces: list[tuple[int, int]] = []
    start = 0
    while start < n:
        lo, hi = start + 1, n
        best = start + 1
        while lo <= hi:
            mid = (lo + hi) // 2
            if count_tokens(text[start:mid]) <= HARD_MAXIMUM_CHUNK_TOKENS:
                best = mid
                lo = mid + 1
            else:
                hi = mid - 1
        end = best
        if end < n:
            space_index = text.rfind(" ", start, end)
            if space_index > start:
                end = space_index + 1
        pieces.append((start, end))
        start = end

    return [
        Block(
            text=text[s:e],
            start_offset=block.start_offset + s,
            end_offset=block.start_offset + e,
            block_type=block.block_type,
            split_reason="tokenizer_window",
        )
        for (s, e) in pieces
    ]
