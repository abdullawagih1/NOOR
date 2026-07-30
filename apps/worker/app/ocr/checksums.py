"""
Deterministic checksums for the OCR pipeline — same canonical-JSON
discipline as app/pdf_extraction/checksums.py (sorted keys, compact
separators, UTF-8, ensure_ascii=False so Arabic text hashes over its real
characters, not \\uXXXX escapes).
"""
from __future__ import annotations

import hashlib
import json
from typing import Any


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def compute_image_checksum(image_bytes: bytes) -> str:
    return hashlib.sha256(image_bytes).hexdigest()


def compute_text_checksum(normalized_text: str) -> str:
    return hashlib.sha256(normalized_text.encode("utf-8")).hexdigest()


def compute_artifact_checksum(artifact: dict) -> str:
    return hashlib.sha256(_canonical_bytes(artifact)).hexdigest()


def canonical_artifact_bytes(artifact: dict) -> bytes:
    return _canonical_bytes(artifact)
