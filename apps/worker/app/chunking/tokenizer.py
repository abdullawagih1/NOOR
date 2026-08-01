"""
noor-simple-tokenizer v1 (ADR 0014) — a deterministic, dependency-free
technical size proxy used only to bound chunk size. Counts tokens as the
number of regex matches of `\\w+|[^\\w\\s]` (Unicode mode) over
NFC-normalized text: each run of "word" characters (any script — Arabic
and Latin are treated identically, unlike tiktoken's Latin-corpus-biased
BPE merges) or each non-whitespace punctuation/symbol character is one
token.

This is NEVER the token count of any real embedding model eventually
chosen for retrieval — see ADR 0014's comparison table and the mission's
own explicit warning against that conflation. Changing the regex or the
normalization step is a TOKENIZER_VERSION bump (app/chunking/config.py),
never a silent change — it would alter every existing chunking run's
deterministic identity.
"""
from __future__ import annotations

import re
import unicodedata

from app.chunking.config import TOKENIZER_NAME, TOKENIZER_VERSION

_TOKEN_PATTERN = re.compile(r"\w+|[^\w\s]", re.UNICODE)


def normalize_for_tokenization(text: str) -> str:
    return unicodedata.normalize("NFC", text)


def count_tokens(text: str) -> int:
    if not text:
        return 0
    return len(_TOKEN_PATTERN.findall(normalize_for_tokenization(text)))


def tokenizer_identity() -> tuple[str, str]:
    return TOKENIZER_NAME, TOKENIZER_VERSION
