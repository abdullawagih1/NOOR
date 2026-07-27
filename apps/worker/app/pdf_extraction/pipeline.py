"""
Ties source download/revalidation, extraction, normalization, checksums,
artifact construction, and artifact upload/verification into one
synchronous call. Runs inside the existing WorkerLoop's heartbeat-thread
window (app/worker_loop.py) — no manual heartbeat calls are needed here;
see docs/operations/pdf-extraction-worker-runbook.md for why that's
sufficient, and why losing the lease mid-pipeline is safely caught by the
database's own lease check at finalization time regardless.
"""
from __future__ import annotations

from pathlib import Path

import httpx

from app.pdf_extraction.artifact import build_canonical_artifact
from app.pdf_extraction.artifact_storage import build_artifact_storage_path, upload_and_verify_artifact
from app.pdf_extraction.checksums import canonical_artifact_bytes, compute_artifact_checksum
from app.pdf_extraction.config import ARTIFACT_MEDIA_TYPE, ARTIFACT_STORAGE_BUCKET, ExtractionConfiguration
from app.pdf_extraction.errors import ExtractionError
from app.pdf_extraction.extractor import PdfExtractor
from app.pdf_extraction.models import ExtractionResult
from app.pdf_extraction.source_download import download_source_to_temp_file


class ExtractionPipelineOutcome:
    def __init__(self, result: ExtractionResult, artifact_bytes: bytes, artifact_sha256: str, storage_path: str) -> None:
        self.result = result
        self.artifact_bytes = artifact_bytes
        self.artifact_sha256 = artifact_sha256
        self.storage_path = storage_path
        self.storage_bucket = ARTIFACT_STORAGE_BUCKET
        self.media_type = ARTIFACT_MEDIA_TYPE


def run_extraction_pipeline(
    *,
    supabase_url: str,
    service_role_key: str,
    source_storage_bucket: str,
    source_storage_path: str,
    source_sha256: str,
    source_size_bytes: int,
    source_document_id: str,
    organization_id: str,
    pipeline_version: str,
    configuration_version: str,
    extractor: PdfExtractor,
    configuration: ExtractionConfiguration,
    http_client: httpx.Client | None = None,
    temp_directory: str | None = None,
) -> ExtractionPipelineOutcome:
    with download_source_to_temp_file(
        supabase_url=supabase_url,
        service_role_key=service_role_key,
        storage_bucket=source_storage_bucket,
        storage_path=source_storage_path,
        expected_sha256=source_sha256,
        expected_size_bytes=source_size_bytes,
        http_client=http_client,
        temp_directory=temp_directory,
    ) as temp_path:
        result = extractor.extract(Path(temp_path), configuration=configuration)

    try:
        artifact = build_canonical_artifact(
            source_document_id=source_document_id,
            source_sha256=source_sha256,
            source_size_bytes=source_size_bytes,
            pipeline_version=pipeline_version,
            configuration_version=configuration_version,
            extractor_name=extractor.name,
            extractor_version=extractor.version,
            result=result,
        )
        artifact_bytes = canonical_artifact_bytes(artifact)
        artifact_sha256 = compute_artifact_checksum(artifact)
    except ExtractionError:
        raise
    except Exception as exc:
        raise ExtractionError("artifact_serialization_failed", "the extraction artifact could not be serialized") from exc

    storage_path = build_artifact_storage_path(
        organization_id=organization_id,
        source_document_id=source_document_id,
        pipeline_version=pipeline_version,
        extractor_name=extractor.name,
        extractor_version=extractor.version,
        artifact_sha256=artifact_sha256,
    )

    upload_and_verify_artifact(
        supabase_url=supabase_url,
        service_role_key=service_role_key,
        storage_bucket=ARTIFACT_STORAGE_BUCKET,
        storage_path=storage_path,
        content_bytes=artifact_bytes,
        media_type=ARTIFACT_MEDIA_TYPE,
        http_client=http_client,
    )

    return ExtractionPipelineOutcome(result, artifact_bytes, artifact_sha256, storage_path)
