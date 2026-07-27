"""
Deterministic checksums (mission §18, §12). Both the per-page checksum
and the whole-artifact checksum are computed over a canonical JSON
serialization — sorted keys, compact separators, UTF-8, `ensure_ascii=False`
(so Arabic/Unicode text hashes over its real characters, not `\\uXXXX`
escapes) — so the exact same logical content always produces the exact
same bytes to hash, independent of Python dict insertion order or
platform.

Never included: processing timestamps, Worker identity, attempt id, or
any other value that varies between two runs of the *same* source over
the *same* versions — see the determinism contract in ADR 0010.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def compute_page_checksum(
    *,
    page_number: int,
    rotation_degrees: int,
    width_points: float | None,
    height_points: float | None,
    normalized_text: str,
    extraction_status: str,
    warnings: list[str],
) -> str:
    canonical = {
        "page_number": page_number,
        "rotation_degrees": rotation_degrees,
        "width_points": width_points,
        "height_points": height_points,
        "normalized_text": normalized_text,
        "extraction_status": extraction_status,
        "warnings": sorted(warnings),
    }
    return hashlib.sha256(_canonical_bytes(canonical)).hexdigest()


def compute_artifact_checksum(artifact: dict) -> str:
    return hashlib.sha256(_canonical_bytes(artifact)).hexdigest()


def canonical_artifact_bytes(artifact: dict) -> bytes:
    return _canonical_bytes(artifact)
