"""
Trusted source retrieval (mission §14-15). Streams the exact registered
private Storage object to a secure OS-managed temporary file, verifying
size/checksum/signature incrementally — never loading the full object
into memory, and never trusting the Storage response alone (the Worker
independently recomputes SHA-256 over what it actually received).

Temp-file safety: `tempfile.mkdtemp()` (unpredictable name, OS-default
restrictive permissions, never derived from the original filename), and
the `finally` block deletes the file and directory whether extraction
succeeds, fails, or raises before ever reaching the caller's `with` body.
"""
from __future__ import annotations

import hashlib
import os
import shutil
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

import httpx

from app.pdf_extraction.errors import ExtractionError

PDF_SIGNATURE = b"%PDF-"


@contextmanager
def download_source_to_temp_file(
    *,
    supabase_url: str,
    service_role_key: str,
    storage_bucket: str,
    storage_path: str,
    expected_sha256: str,
    expected_size_bytes: int,
    http_client: httpx.Client | None = None,
    temp_directory: str | None = None,
) -> Iterator[Path]:
    client = http_client or httpx.Client(timeout=120.0)
    owns_client = http_client is None
    tmp_dir = tempfile.mkdtemp(prefix="noor-extract-", dir=temp_directory)
    tmp_path = Path(tmp_dir) / "source.pdf"
    try:
        url = f"{supabase_url.rstrip('/')}/storage/v1/object/{storage_bucket}/{storage_path}"
        headers = {"apikey": service_role_key, "Authorization": f"Bearer {service_role_key}"}

        hasher = hashlib.sha256()
        size = 0
        first_bytes = b""

        with client.stream("GET", url, headers=headers) as response:
            if response.status_code == 404:
                raise ExtractionError("source_object_missing", "the registered source object was not found in storage")
            if response.status_code >= 400:
                raise ExtractionError(
                    "source_object_missing", f"could not download the source object (status {response.status_code})"
                )
            with open(tmp_path, "wb") as f:
                for chunk in response.iter_bytes():
                    size += len(chunk)
                    hasher.update(chunk)
                    if len(first_bytes) < len(PDF_SIGNATURE):
                        first_bytes += chunk
                    f.write(chunk)

        if first_bytes[: len(PDF_SIGNATURE)] != PDF_SIGNATURE:
            raise ExtractionError("invalid_pdf_signature", "the downloaded object does not have a valid PDF signature")
        if size != expected_size_bytes:
            raise ExtractionError(
                "source_size_mismatch", "the downloaded object's size does not match the registered document"
            )
        actual_sha256 = hasher.hexdigest()
        if actual_sha256 != expected_sha256:
            raise ExtractionError(
                "source_checksum_mismatch", "the downloaded object's checksum does not match the registered document"
            )

        yield tmp_path
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        if owns_client:
            client.close()
