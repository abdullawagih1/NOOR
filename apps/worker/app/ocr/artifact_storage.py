"""
OCR artifact path convention — tenant-scoped, content-addressed, and
namespaced under the page number so two different pages of the same
document can never collide (mission §13, one layer deeper than
app/pdf_extraction/artifact_storage.py's document-level path).

Upload/verify itself is not duplicated here — it is bucket/path/content
agnostic, so app/pdf_extraction/artifact_storage.py's
`upload_and_verify_artifact` is reused directly by app/ocr/pipeline.py.
"""
from __future__ import annotations


def build_ocr_artifact_storage_path(
    *,
    organization_id: str,
    source_document_id: str,
    pipeline_version: str,
    page_number: int,
    provider_name: str,
    provider_version: str,
    artifact_sha256: str,
) -> str:
    return (
        f"{organization_id}/guideline-ocr/{source_document_id}/page-{page_number}/"
        f"{pipeline_version}/{provider_name}-{provider_version}/{artifact_sha256}.json"
    )
