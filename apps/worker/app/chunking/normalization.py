"""
Deterministic text normalization (ADR 0014's normalization_version). V1
applies exactly one transform: Unicode NFC normalization. It does not
strip whitespace, collapse newlines, or alter case — any of those would
change chunk offsets and require a NORMALIZATION_VERSION bump (a fresh
deterministic identity, never a silent change to an already-succeeded
run's meaning).
"""
from __future__ import annotations

import unicodedata


def normalize_page_text(text: str) -> str:
    return unicodedata.normalize("NFC", text or "")
