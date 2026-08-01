"""
Input manifest construction (ADR 0014) — an ordered, canonically-serialized
JSON of per-page representation identity, built and hashed by the Worker,
never by SQL — the same division of responsibility as
app/pdf_extraction/artifact.py and app/ocr/artifact.py's own canonical
artifacts. The manifest hash is part of a chunking run's deterministic
identity (migration 0012): any change to which representation a page
resolved to (native vs. OCR, or a re-accepted OCR run's checksum)
produces a different manifest hash and therefore a fresh chunking run,
never a silent reuse of stale input.
"""
from __future__ import annotations

from app.chunking.checksums import canonical_bytes, compute_manifest_checksum
from app.chunking.models import PageRepresentation

MANIFEST_SCHEMA_VERSION = "1.0"


def build_input_manifest(pages: list[PageRepresentation]) -> dict:
    return {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "pages": [
            {
                "page_number": page.page_number,
                "representation_type": page.representation_type,
                "representation_id": page.representation_id,
                "text_checksum": page.text_checksum,
                "character_count": page.character_count,
                "warning_state": page.warning_state,
            }
            for page in sorted(pages, key=lambda p: p.page_number)
        ],
    }


def compute_input_manifest_sha256(manifest: dict) -> str:
    return compute_manifest_checksum(manifest)


def manifest_bytes(manifest: dict) -> bytes:
    return canonical_bytes(manifest)
