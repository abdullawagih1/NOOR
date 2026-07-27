"""
Canonical extraction identity constants (Sprint 1.2B, mission §10). These
four values plus a source document's SHA-256 are what "one identifiable
extraction result" means — see
docs/domain/document-extraction-lifecycle.md.

`PDF_EXTRACTOR_VERSION` is a pinned literal, not `pypdf.__version__` read
at runtime (mission: "Do not derive the extractor version from an
unpinned runtime package without recording it") — but `assert_pinned_extractor_version()`
cross-checks it against the actually-installed package at Worker startup,
so a `requirements.txt` bump that forgets to update this constant fails
loudly instead of silently extracting under the wrong recorded version.

Bumping any of these is a deliberate, reviewed action — see ADR 0010's
upgrade policy.
"""
from __future__ import annotations

from dataclasses import dataclass

EXTRACTION_PIPELINE_VERSION = "pdf-text-v1"
EXTRACTION_CONFIGURATION_VERSION = "1"
PDF_EXTRACTOR_NAME = "pypdf"
PDF_EXTRACTOR_VERSION = "6.14.2"

ARTIFACT_SCHEMA_VERSION = "1.0"
ARTIFACT_MEDIA_TYPE = "application/json"
ARTIFACT_STORAGE_BUCKET = "guideline-processed"


def assert_pinned_extractor_version() -> None:
    import pypdf

    if pypdf.__version__ != PDF_EXTRACTOR_VERSION:
        raise RuntimeError(
            f"Installed pypdf version ({pypdf.__version__}) does not match the pinned "
            f"PDF_EXTRACTOR_VERSION ({PDF_EXTRACTOR_VERSION}) recorded in "
            "app/pdf_extraction/config.py. Update the constant (and consider whether "
            "EXTRACTION_PIPELINE_VERSION also needs bumping) before deploying — see ADR 0010."
        )


@dataclass(frozen=True)
class ExtractionConfiguration:
    """Deterministic normalization settings — see docs/domain/document-extraction-artifacts.md."""

    version: str = EXTRACTION_CONFIGURATION_VERSION
    normalize_line_endings: bool = True
    normalize_unicode: bool = True
    preserve_page_breaks: bool = True
    include_geometry: bool = True
