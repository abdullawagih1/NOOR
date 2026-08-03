"""
Deterministic checksums for the embedding pipeline (mission §16, ADR 0016).

`vector_serialization_v1`: each vector component is converted to a
canonical IEEE-754 float32, packed little-endian, concatenated in index
order, and SHA-256'd. This is explicitly NOT derived from Python's
`repr()`/`str()` of floats (locale-independent, but not float32-precision-
stable — two float64 values that round to the same float32 could otherwise
produce different checksums) and never uses locale-dependent string
formatting (mission's explicit requirement).

Precision note: multilingual-e5-base produces float32-precision output
internally (standard for `sentence-transformers`/PyTorch CPU inference), so
round-tripping through float32 here loses no real precision — it is exactly
the same representation the model already computed in.
"""
from __future__ import annotations

import hashlib
import json
import struct
from typing import Any, Sequence

VECTOR_SERIALIZATION_VERSION = "vector_serialization_v1"


def canonical_vector_bytes(values: Sequence[float]) -> bytes:
    return b"".join(struct.pack("<f", float(v)) for v in values)


def compute_vector_checksum(values: Sequence[float]) -> str:
    return hashlib.sha256(canonical_vector_bytes(values)).hexdigest()


def compute_vector_norm(values: Sequence[float]) -> float:
    return sum(v * v for v in values) ** 0.5


def compute_text_checksum(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def compute_manifest_checksum(manifest: dict) -> str:
    return hashlib.sha256(_canonical_json_bytes(manifest)).hexdigest()


def compute_artifact_checksum(artifact: dict) -> str:
    return hashlib.sha256(_canonical_json_bytes(artifact)).hexdigest()


def canonical_bytes(value: dict) -> bytes:
    return _canonical_json_bytes(value)


def vector_to_pgvector_literal(values: Sequence[float]) -> str:
    """`'[0.1,0.2,...]'` — the literal text format PostgREST/pgvector
    expects for a `vector` column via a plain JSON-array-shaped string
    parameter (pgvector accepts this exact bracketed form)."""
    return "[" + ",".join(repr(float(v)) for v in values) + "]"
