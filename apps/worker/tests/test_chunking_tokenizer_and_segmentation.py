"""
Unit-level determinism and correctness proofs for noor-simple-tokenizer
(ADR 0014) and the deterministic block segmenter (app/chunking/segmentation.py).
No PDF/OCR fixtures are needed here — chunking operates on already-accepted
page text, never on raw files.
"""
from __future__ import annotations

from app.chunking.config import HARD_MAXIMUM_CHUNK_TOKENS
from app.chunking.models import Block
from app.chunking.segmentation import detect_blocks, split_oversized_block
from app.chunking.tokenizer import count_tokens, tokenizer_identity

ARABIC_PARAGRAPH = (
    "هذه فقرة تجريبية باللغة العربية تحتوي على عدة كلمات لاختبار "
    "تقسيم النص بشكل صحيح ودقيق جدا جدا."
)


# ---------------------------------------------------------------------------
# Tokenizer
# ---------------------------------------------------------------------------


def test_tokenizer_identity_is_pinned():
    name, version = tokenizer_identity()
    assert name == "noor-simple-tokenizer"
    assert version == "1"


def test_tokenizer_is_deterministic():
    text = "Hello, world! This is a test — with an em dash and punctuation."
    assert count_tokens(text) == count_tokens(text)


def test_tokenizer_counts_words_and_punctuation_separately():
    # "Hello" + "," + "world" + "!" = 4 tokens
    assert count_tokens("Hello, world!") == 4


def test_tokenizer_treats_arabic_and_latin_scripts_identically():
    # Same structural shape (5 words, no punctuation) in both scripts must
    # yield the same token count — the whole point of not using a
    # Latin-biased BPE tokenizer (ADR 0014).
    latin = "one two three four five"
    arabic = "واحد اثنان ثلاثة أربعة خمسة"
    assert count_tokens(latin) == count_tokens(arabic) == 5


def test_tokenizer_handles_empty_string():
    assert count_tokens("") == 0


def test_tokenizer_is_never_confused_with_a_real_embedding_model_by_name():
    name, _ = tokenizer_identity()
    assert "tiktoken" not in name
    assert "gpt" not in name.lower()
    assert "embedding" not in name.lower()


# ---------------------------------------------------------------------------
# Block segmentation — tiling invariants (the property every other guarantee
# in this pipeline depends on)
# ---------------------------------------------------------------------------


def _assert_perfect_tiling(blocks: list[Block], text: str) -> None:
    assert blocks, "expected at least one block for non-empty text"
    boundary = 0
    for block in blocks:
        assert block.start_offset == boundary, "blocks must tile with zero gaps/overlaps"
        boundary = block.end_offset
    assert boundary == len(text), "blocks must cover the entire input text"
    assert "".join(b.text for b in blocks) == text, "reconstructed text must equal the original exactly"


def test_detect_blocks_tiles_english_mixed_content():
    text = (
        "Heading Line\n\n"
        "This is a paragraph with several words that should be grouped "
        "together as one paragraph block for testing purposes here.\n\n"
        "- item one\n- item two\n- item three\n\n"
        "Another paragraph after the list, to verify tiling continues "
        "correctly without gaps or overlaps in the final result.\n"
    )
    blocks = detect_blocks(text)
    _assert_perfect_tiling(blocks, text)
    types = [b.block_type for b in blocks]
    assert types == ["heading_candidate", "paragraph", "list_item", "paragraph"]


def test_detect_blocks_tiles_arabic_mixed_content():
    text = f"عنوان تجريبي\n\n{ARABIC_PARAGRAPH}\n\n- بند أول\n- بند ثاني\n"
    blocks = detect_blocks(text)
    _assert_perfect_tiling(blocks, text)


def test_detect_blocks_tiles_table_like_content():
    text = "Name        Age        City\nAli         30         Cairo\nSara        25         Giza\n"
    blocks = detect_blocks(text)
    _assert_perfect_tiling(blocks, text)
    assert any(b.block_type == "table_like" for b in blocks)


def test_detect_blocks_on_blank_only_text_still_covers_everything():
    text = "\n\n   \n\n"
    blocks = detect_blocks(text)
    _assert_perfect_tiling(blocks, text)


def test_detect_blocks_on_empty_text_returns_no_blocks():
    assert detect_blocks("") == []


def test_detect_blocks_is_deterministic():
    text = "Paragraph one.\n\nParagraph two.\n\n- a\n- b\n"
    assert detect_blocks(text) == detect_blocks(text)


# ---------------------------------------------------------------------------
# Oversized-block fallback — strict order, always terminates, always tiles
# ---------------------------------------------------------------------------


def test_split_oversized_block_uses_sentence_boundaries_first():
    # 10 tokens/sentence * 120 = 1200 tokens, well over HARD_MAXIMUM_CHUNK_TOKENS (800).
    long_text = "This is a sentence that repeats itself many times. " * 120
    block = Block(text=long_text, start_offset=0, end_offset=len(long_text), block_type="paragraph")
    pieces = split_oversized_block(block)
    assert len(pieces) > 1
    assert all(p.split_reason == "sentence_boundary" for p in pieces)
    _assert_perfect_tiling(pieces, long_text)
    assert all(count_tokens(p.text) <= HARD_MAXIMUM_CHUNK_TOKENS for p in pieces)


def test_split_oversized_block_falls_back_to_line_boundary_without_sentence_punctuation():
    # 10 tokens/line * 120 = 1200 tokens, well over HARD_MAXIMUM_CHUNK_TOKENS (800).
    long_text = ("this line has no terminal punctuation and just keeps going\n") * 120
    block = Block(text=long_text, start_offset=0, end_offset=len(long_text), block_type="paragraph")
    pieces = split_oversized_block(block)
    assert len(pieces) > 1
    _assert_perfect_tiling(pieces, long_text)
    assert all(count_tokens(p.text) <= HARD_MAXIMUM_CHUNK_TOKENS for p in pieces)


def test_split_oversized_block_falls_back_to_tokenizer_window_as_last_resort():
    # One single "sentence" with no periods, newlines, or commas at all —
    # forces the last-resort fallback.
    long_text = "word " * 2000
    block = Block(text=long_text, start_offset=0, end_offset=len(long_text), block_type="paragraph")
    pieces = split_oversized_block(block)
    assert len(pieces) > 1
    assert any(p.split_reason == "tokenizer_window" for p in pieces)
    _assert_perfect_tiling(pieces, long_text)
    assert all(count_tokens(p.text) <= HARD_MAXIMUM_CHUNK_TOKENS for p in pieces)


def test_split_oversized_block_never_silently_truncates_content():
    long_text = "Sentence number ends here. " * 100 + "no terminator at the very end"
    block = Block(text=long_text, start_offset=0, end_offset=len(long_text), block_type="paragraph")
    pieces = split_oversized_block(block)
    assert "".join(p.text for p in pieces) == long_text


def test_split_oversized_block_is_a_noop_for_small_blocks():
    small_text = "This block is small."
    block = Block(text=small_text, start_offset=0, end_offset=len(small_text), block_type="paragraph")
    assert split_oversized_block(block) == [block]
