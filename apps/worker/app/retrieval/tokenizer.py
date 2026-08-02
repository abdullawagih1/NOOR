"""
Tokenization for the lexical baseline's scoring layer only (token_coverage,
exact-phrase checks) — deliberately NOT a Unicode-normalization step of its
own. By the time text reaches this module it has already passed through
`normalize_retrieval_text()` (migration 0014: NFC, case-fold, Arabic
diacritic/tatweel removal, Arabic-Indic numeral mapping, punctuation
separation) and is stored/read back pre-normalized — so a plain whitespace
split is the correct, sufficient tokenizer here. See ADR 0015's
"Deterministic normalization lives in exactly one place: SQL" section for
why this module must never re-implement any of those rules.
"""
from __future__ import annotations


def tokenize(normalized_text: str) -> list[str]:
    if not normalized_text:
        return []
    return normalized_text.split()
