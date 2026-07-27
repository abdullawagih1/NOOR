"""
Canonical, deterministic text normalization (mission §17). Every change to
this function's behavior must bump `EXTRACTION_CONFIGURATION_VERSION`
(app/pdf_extraction/config.py) — the whole point of a configuration
version is that "same source + same versions" is a promise about *this*
function's output too, not just the extractor's raw output.

Deliberately NOT done here (mission §17, §2.3): spell-correction, content
reordering, missing-text inference, translation, or any LLM involvement.
This is a pure, offline, character-level transform — nothing here reads
the page's *meaning*, only its bytes.
"""
from __future__ import annotations

import unicodedata


def normalize_page_text(raw_text: str) -> str:
    if not raw_text:
        return ""

    text = raw_text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("\x00", "")
    text = unicodedata.normalize("NFC", text)

    lines = [line.rstrip(" \t") for line in text.split("\n")]
    return "\n".join(lines)


def count_words(normalized_text: str) -> int:
    return len(normalized_text.split())


def count_characters(normalized_text: str) -> int:
    return len(normalized_text)


def is_blank(normalized_text: str) -> bool:
    return len(normalized_text.strip()) == 0
