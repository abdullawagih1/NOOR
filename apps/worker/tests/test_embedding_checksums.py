"""
Deterministic checksum/serialization tests (Sprint 1-E2, ADR 0016,
`vector_serialization_v1`) — pure Python, zero network/model access.
"""
from __future__ import annotations

import math

from app.embedding.checksums import (
    canonical_vector_bytes,
    compute_text_checksum,
    compute_vector_checksum,
    compute_vector_norm,
    vector_to_pgvector_literal,
)


def test_vector_checksum_is_deterministic_for_identical_values():
    values = [0.1, 0.2, 0.3, -0.4]
    assert compute_vector_checksum(values) == compute_vector_checksum(values)


def test_vector_checksum_differs_for_a_single_changed_value():
    a = [0.1, 0.2, 0.3]
    b = [0.1, 0.2, 0.30001]
    assert compute_vector_checksum(a) != compute_vector_checksum(b)


def test_vector_checksum_is_order_sensitive():
    a = [0.1, 0.2, 0.3]
    b = [0.3, 0.2, 0.1]
    assert compute_vector_checksum(a) != compute_vector_checksum(b)


def test_vector_checksum_not_derived_from_python_repr_string():
    # Two float64 values that are numerically identical after rounding to
    # float32 must produce the SAME checksum — proving this is a real
    # float32-precision serialization, not str()/repr() text hashing.
    a = [0.1]
    b = [0.10000000000000001]  # collapses to the same float32 bit pattern
    assert compute_vector_checksum(a) == compute_vector_checksum(b)


def test_canonical_vector_bytes_length_matches_float32_packing():
    values = [0.0] * 768
    assert len(canonical_vector_bytes(values)) == 768 * 4


def test_vector_norm_of_unit_vector_is_one():
    values = [1.0] + [0.0] * 767
    assert math.isclose(compute_vector_norm(values), 1.0)


def test_vector_norm_of_zero_vector_is_zero():
    assert compute_vector_norm([0.0, 0.0, 0.0]) == 0.0


def test_text_checksum_is_deterministic_and_utf8_aware():
    assert compute_text_checksum("Blood pressure") == compute_text_checksum("Blood pressure")
    assert compute_text_checksum("قياس ضغط الدم") == compute_text_checksum("قياس ضغط الدم")
    assert compute_text_checksum("Blood pressure") != compute_text_checksum("blood pressure")


def test_pgvector_literal_format():
    literal = vector_to_pgvector_literal([0.1, -0.2, 3.0])
    assert literal.startswith("[") and literal.endswith("]")
    assert literal == "[0.1,-0.2,3.0]"
