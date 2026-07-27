"""
Processed-artifact upload and verification (mission §13, §36). The
artifact is never marked as the extraction run's result until it has been
independently re-downloaded and re-hashed — an upload response alone
(HTTP 200) is not trusted as proof the stored bytes match what was sent.

Path generation (mission §13): a shorter immutable path than the mission's
suggested example, deliberately not requiring an extra guideline/version
lookup the Worker doesn't otherwise need — tenant-scoped (first segment is
`organization_id`, matching the same Storage RLS convention as
`guideline-originals`), and content-addressed (the last segment is the
artifact's own SHA-256), so re-uploading identical content is naturally
idempotent (upsert to the same path) and two different extraction results
can never collide on the same path.
"""
from __future__ import annotations

import hashlib

import httpx

from app.pdf_extraction.errors import ExtractionError


def build_artifact_storage_path(
    *,
    organization_id: str,
    source_document_id: str,
    pipeline_version: str,
    extractor_name: str,
    extractor_version: str,
    artifact_sha256: str,
) -> str:
    return (
        f"{organization_id}/guideline-extractions/{source_document_id}/"
        f"{pipeline_version}/{extractor_name}-{extractor_version}/{artifact_sha256}.json"
    )


def upload_and_verify_artifact(
    *,
    supabase_url: str,
    service_role_key: str,
    storage_bucket: str,
    storage_path: str,
    content_bytes: bytes,
    media_type: str,
    http_client: httpx.Client | None = None,
) -> None:
    client = http_client or httpx.Client(timeout=60.0)
    owns_client = http_client is None
    try:
        url = f"{supabase_url.rstrip('/')}/storage/v1/object/{storage_bucket}/{storage_path}"
        upload_headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": media_type,
            "x-upsert": "true",
        }
        upload_response = client.post(url, headers=upload_headers, content=content_bytes)
        if upload_response.status_code >= 400:
            raise ExtractionError(
                "artifact_upload_failed", f"could not upload the extraction artifact (status {upload_response.status_code})"
            )

        # Verify by independent re-download + re-hash — never trust the
        # upload response alone (mission §36).
        verify_headers = {"apikey": service_role_key, "Authorization": f"Bearer {service_role_key}"}
        verify_response = client.get(url, headers=verify_headers)
        if verify_response.status_code >= 400:
            raise ExtractionError("artifact_upload_failed", "could not verify the uploaded extraction artifact")

        downloaded = verify_response.content
        if len(downloaded) != len(content_bytes):
            raise ExtractionError(
                "artifact_checksum_mismatch", "the uploaded artifact's size does not match what was sent"
            )
        if hashlib.sha256(downloaded).hexdigest() != hashlib.sha256(content_bytes).hexdigest():
            raise ExtractionError(
                "artifact_checksum_mismatch", "the uploaded artifact's checksum does not match what was sent"
            )
    finally:
        if owns_client:
            client.close()
