"""
Chunking artifact path convention — tenant-scoped, content-addressed, one
segment per document (chunking is document-scoped, ADR 0014, unlike OCR's
page-scoped path in app/ocr/artifact_storage.py).

Upload/verify itself is not duplicated here — it is bucket/path/content
agnostic, so app/pdf_extraction/artifact_storage.py's
`upload_and_verify_artifact` is reused directly by app/chunking/pipeline.py.
"""
from __future__ import annotations


def build_chunking_artifact_storage_path(
    *,
    organization_id: str,
    source_document_id: str,
    pipeline_version: str,
    tokenizer_name: str,
    tokenizer_version: str,
    artifact_sha256: str,
) -> str:
    return (
        f"{organization_id}/guideline-chunking/{source_document_id}/"
        f"{pipeline_version}/{tokenizer_name}-{tokenizer_version}/{artifact_sha256}.json"
    )
