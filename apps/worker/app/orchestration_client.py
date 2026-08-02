"""
Typed httpx client for the six Worker-only PostgREST RPC endpoints added by
migration 0007 (`supabase/migrations/0007_durable_processing_orchestration.sql`).

These functions are never granted to the `authenticated` role (ADR 0009) —
only the `service_role` credential this client authenticates with can reach
them, mirroring the same server-only trust boundary already used by
`apps/web/lib/supabase/service-role.ts` on the Web side.

Every call is a `POST {supabase_url}/rest/v1/rpc/<function_name>` with a
JSON body matching the function's named parameters (PostgREST's calling
convention for RPC). `RETURNS TABLE` functions come back as a JSON array of
row objects (empty array when no row was produced, e.g. an empty claim).

The lease token is only ever held in memory here and handed back to the
same six functions that need it — never logged (see `_redact` in
`OrchestrationError.__str__`).
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any, Literal

import httpx

DEFAULT_JOB_TYPES = ["document_parsing"]


class OrchestrationError(Exception):
    """
    Raised for both transport failures and PostgREST-reported errors (e.g.
    a lease-ownership check failing). The message is safe to log — it never
    includes the lease token, which callers pass as a function argument,
    not as part of any string this class builds.
    """


@dataclass(frozen=True)
class ClaimedJob:
    job_id: uuid.UUID
    organization_id: uuid.UUID
    # None for a dataset-scoped job (job_type='retrieval_evaluation',
    # migration 0015) — every other job_type still always sets this.
    source_document_id: uuid.UUID | None
    job_type: str
    pipeline_version: str
    correlation_id: uuid.UUID
    attempt_number: int
    lease_token: str
    lease_expires_at: str


ProcessingOutcomeKind = Literal["succeeded", "retryable_failure", "terminal_failure"]


class OrchestrationClient:
    def __init__(self, supabase_url: str, service_role_key: str, http_client: httpx.Client | None = None) -> None:
        self._base_url = supabase_url.rstrip("/")
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        self._client = http_client or httpx.Client(timeout=10.0)
        self._owns_client = http_client is None

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def __enter__(self) -> "OrchestrationClient":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def _rpc(self, function_name: str, payload: dict[str, Any]) -> list[dict[str, Any]]:
        url = f"{self._base_url}/rest/v1/rpc/{function_name}"
        clean_payload = {k: v for k, v in payload.items() if v is not None}
        try:
            response = self._client.post(url, headers=self._headers, json=_jsonable(clean_payload))
        except httpx.HTTPError as exc:
            raise OrchestrationError(f"{function_name}: transport error: {exc.__class__.__name__}") from exc

        if response.status_code >= 400:
            # PostgREST error bodies are structured JSON ({"message": ...,
            # "code": ...}); pass the message through, never raw response
            # text that might include headers/tokens.
            try:
                detail = response.json().get("message", response.text[:200])
            except ValueError:
                detail = response.text[:200]
            raise OrchestrationError(f"{function_name} failed ({response.status_code}): {detail}")

        body = response.json()
        if body is None:
            return []
        if isinstance(body, list):
            return body
        return [body]

    def claim_next_job(
        self,
        worker_instance_id: str,
        job_types: list[str] | None = None,
        lease_duration_seconds: int = 90,
        correlation_id: uuid.UUID | None = None,
    ) -> ClaimedJob | None:
        rows = self._rpc(
            "claim_next_document_processing_job",
            {
                "p_worker_instance_id": worker_instance_id,
                "p_job_types": job_types or DEFAULT_JOB_TYPES,
                "p_lease_duration_seconds": lease_duration_seconds,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        if not rows or rows[0].get("out_job_id") is None:
            return None
        row = rows[0]
        return ClaimedJob(
            job_id=uuid.UUID(row["out_job_id"]),
            organization_id=uuid.UUID(row["out_organization_id"]),
            source_document_id=uuid.UUID(row["out_source_document_id"]) if row.get("out_source_document_id") else None,
            job_type=row["out_job_type"],
            pipeline_version=row["out_pipeline_version"],
            correlation_id=uuid.UUID(row["out_correlation_id"]),
            attempt_number=row["out_attempt_number"],
            lease_token=row["out_lease_token"],
            lease_expires_at=row["out_lease_expires_at"],
        )

    def start_job(
        self, job_id: uuid.UUID, worker_instance_id: str, lease_token: str, correlation_id: uuid.UUID | None = None
    ) -> dict[str, Any]:
        rows = self._rpc(
            "start_document_processing_job",
            {
                "p_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def heartbeat_job(
        self,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        lease_duration_seconds: int = 90,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "heartbeat_document_processing_job",
            {
                "p_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_lease_duration_seconds": lease_duration_seconds,
            },
        )
        return rows[0] if rows else {}

    def complete_job(
        self,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        result_summary: dict[str, Any],
        idempotency_key: str | None = None,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "complete_document_processing_job",
            {
                "p_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_result_summary": result_summary,
                "p_idempotency_key": idempotency_key,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def fail_job(
        self,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        error_code: str,
        error_class: str,
        error_message_safe: str,
        retryable: bool = True,
        idempotency_key: str | None = None,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "fail_document_processing_job",
            {
                "p_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_error_code": error_code,
                "p_error_class": error_class,
                "p_error_message_safe": error_message_safe,
                "p_retryable": retryable,
                "p_idempotency_key": idempotency_key,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def recover_expired_jobs(self, correlation_id: uuid.UUID | None = None) -> list[dict[str, Any]]:
        return self._rpc(
            "recover_expired_document_processing_jobs",
            {"p_correlation_id": str(correlation_id) if correlation_id else None},
        )

    def get_source_document(self, source_document_id: uuid.UUID) -> dict[str, Any]:
        """Plain trusted table read (service_role bypasses RLS) — the
        Worker needs the registered storage location and checksum to
        download and revalidate the exact object migration 0006 verified
        at intake time."""
        url = f"{self._base_url}/rest/v1/guideline_source_documents"
        params = {
            "id": f"eq.{source_document_id}",
            "select": "id,organization_id,status,storage_bucket,storage_path,sha256,size_bytes",
        }
        try:
            response = self._client.get(url, headers=self._headers, params=params)
        except httpx.HTTPError as exc:
            raise OrchestrationError(f"get_source_document: transport error: {exc.__class__.__name__}") from exc
        if response.status_code >= 400:
            raise OrchestrationError(f"get_source_document failed ({response.status_code})")
        rows = response.json()
        if not rows:
            raise OrchestrationError(f"source document not found: {source_document_id}")
        return rows[0]

    # -- Sprint 1.2B: deterministic PDF extraction (migration 0008) ---------
    # Same trust boundary as the six functions above — never granted to
    # `authenticated`/`anon` (see supabase/tests/rls/007_security_hardening_review.sql
    # and 008_pdf_extraction.sql TEST 16).

    def create_extraction_run(
        self,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        source_sha256: str,
        source_size_bytes: int,
        pipeline_version: str,
        configuration_version: str,
        extractor_name: str,
        extractor_version: str,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "create_document_extraction_run",
            {
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_source_sha256": source_sha256,
                "p_source_size_bytes": source_size_bytes,
                "p_pipeline_version": pipeline_version,
                "p_configuration_version": configuration_version,
                "p_extractor_name": extractor_name,
                "p_extractor_version": extractor_version,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def insert_extraction_pages(self, pages: list[dict[str, Any]]) -> None:
        """Direct trusted table insert (not an RPC) — service_role bypasses
        RLS entirely, and no per-row validation beyond the table's own
        CHECK/UNIQUE constraints is needed. See
        docs/security/pdf-extraction-security.md for why no wrapper
        function exists for this."""
        if not pages:
            return
        url = f"{self._base_url}/rest/v1/document_extraction_pages"
        try:
            response = self._client.post(url, headers=self._headers, json=pages)
        except httpx.HTTPError as exc:
            raise OrchestrationError(f"insert_extraction_pages: transport error: {exc.__class__.__name__}") from exc
        if response.status_code >= 400:
            try:
                detail = response.json().get("message", response.text[:200])
            except ValueError:
                detail = response.text[:200]
            raise OrchestrationError(f"insert_extraction_pages failed ({response.status_code}): {detail}")

    def finalize_extraction_run(
        self,
        extraction_run_id: uuid.UUID,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        expected_page_count: int,
        artifact_bucket: str,
        artifact_path: str,
        artifact_sha256: str,
        artifact_size_bytes: int,
        artifact_media_type: str,
        document_metadata: dict[str, Any] | None = None,
        pages_with_text: int = 0,
        blank_page_count: int = 0,
        suspected_scanned_page_count: int = 0,
        total_character_count: int = 0,
        total_word_count: int = 0,
        warning_count: int = 0,
        warnings: list[str] | None = None,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "finalize_document_extraction_run",
            {
                "p_extraction_run_id": str(extraction_run_id),
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_expected_page_count": expected_page_count,
                "p_artifact_bucket": artifact_bucket,
                "p_artifact_path": artifact_path,
                "p_artifact_sha256": artifact_sha256,
                "p_artifact_size_bytes": artifact_size_bytes,
                "p_artifact_media_type": artifact_media_type,
                "p_document_metadata": document_metadata or {},
                "p_pages_with_text": pages_with_text,
                "p_blank_page_count": blank_page_count,
                "p_suspected_scanned_page_count": suspected_scanned_page_count,
                "p_total_character_count": total_character_count,
                "p_total_word_count": total_word_count,
                "p_warning_count": warning_count,
                "p_warnings": warnings or [],
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def fail_extraction_run(
        self,
        extraction_run_id: uuid.UUID,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        error_code: str,
        error_class: str,
        error_message_safe: str,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "fail_document_extraction_run",
            {
                "p_extraction_run_id": str(extraction_run_id),
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_error_code": error_code,
                "p_error_class": error_class,
                "p_error_message_safe": error_message_safe,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    # -- Sprint 1-D2: controlled page-scoped OCR (migration 0011) -----------
    # Same trust boundary as every method above — never granted to
    # `authenticated`/`anon` (see supabase/tests/rls/011_controlled_ocr.sql
    # TEST 15).

    def get_ocr_job_context(self, job_id: uuid.UUID) -> dict[str, Any]:
        """Joins a claimed `document_ocr` job back to its one eligible page
        and the OCR request's pinned provider/renderer/model identity.
        ClaimedJob itself carries no OCR-specific fields —
        claim_next_document_processing_job (migration 0007, Sprint 1.2A) is
        job-type-agnostic by design, so this supplementary lookup plays the
        same role get_source_document() plays for extraction jobs."""
        url = f"{self._base_url}/rest/v1/document_processing_jobs"
        params = {"id": f"eq.{job_id}", "select": "ocr_request_page_id"}
        job_row = self._get_one(url, params, "get_ocr_job_context")
        ocr_request_page_id = job_row.get("ocr_request_page_id")
        if not ocr_request_page_id:
            raise OrchestrationError(f"job {job_id} is not linked to an OCR request page")

        url = f"{self._base_url}/rest/v1/document_ocr_request_pages"
        params = {
            "id": f"eq.{ocr_request_page_id}",
            "select": "id,organization_id,ocr_request_id,source_document_id,extraction_run_id,extraction_page_id,page_number",
        }
        page_row = self._get_one(url, params, "get_ocr_job_context")

        url = f"{self._base_url}/rest/v1/document_ocr_requests"
        params = {
            "id": f"eq.{page_row['ocr_request_id']}",
            "select": (
                "provider_name,provider_version,model_identifier,model_version,"
                "renderer_name,renderer_version,render_configuration_version,"
                "ocr_configuration_version,language_hints"
            ),
        }
        request_row = self._get_one(url, params, "get_ocr_job_context")

        url = f"{self._base_url}/rest/v1/document_extraction_pages"
        params = {"id": f"eq.{page_row['extraction_page_id']}", "select": "page_checksum"}
        extraction_page_row = self._get_one(url, params, "get_ocr_job_context")

        return {**page_row, **request_row, "native_page_checksum": extraction_page_row["page_checksum"]}

    def _get_one(self, url: str, params: dict[str, Any], caller: str) -> dict[str, Any]:
        try:
            response = self._client.get(url, headers=self._headers, params=params)
        except httpx.HTTPError as exc:
            raise OrchestrationError(f"{caller}: transport error: {exc.__class__.__name__}") from exc
        if response.status_code >= 400:
            raise OrchestrationError(f"{caller} failed ({response.status_code})")
        rows = response.json()
        if not rows:
            raise OrchestrationError(f"{caller}: no matching row for {params}")
        return rows[0]

    def create_ocr_run(
        self,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        source_sha256: str,
        native_page_checksum: str,
        renderer_name: str,
        renderer_version: str,
        render_configuration_version: str,
        render_dpi: int,
        render_color_mode: str,
        render_image_format: str,
        page_image_sha256: str,
        page_image_size_bytes: int,
        provider_name: str,
        provider_version: str,
        model_identifier: str,
        model_version: str,
        ocr_configuration_version: str,
        language_hints: list[str],
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "create_document_ocr_run",
            {
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_source_sha256": source_sha256,
                "p_native_page_checksum": native_page_checksum,
                "p_renderer_name": renderer_name,
                "p_renderer_version": renderer_version,
                "p_render_configuration_version": render_configuration_version,
                "p_render_dpi": render_dpi,
                "p_render_color_mode": render_color_mode,
                "p_render_image_format": render_image_format,
                "p_page_image_sha256": page_image_sha256,
                "p_page_image_size_bytes": page_image_size_bytes,
                "p_provider_name": provider_name,
                "p_provider_version": provider_version,
                "p_model_identifier": model_identifier,
                "p_model_version": model_version,
                "p_ocr_configuration_version": ocr_configuration_version,
                "p_language_hints": list(language_hints),
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def finalize_ocr_page(
        self,
        ocr_run_id: uuid.UUID,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        raw_text: str,
        normalized_text: str,
        character_count: int,
        word_count: int,
        text_checksum: str,
        confidence_summary: dict[str, Any],
        warnings: list[str],
        provider_metadata_safe: dict[str, Any],
        artifact_bucket: str,
        artifact_path: str,
        artifact_sha256: str,
        artifact_size_bytes: int,
        artifact_media_type: str,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "finalize_document_ocr_page",
            {
                "p_ocr_run_id": str(ocr_run_id),
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_raw_text": raw_text,
                "p_normalized_text": normalized_text,
                "p_character_count": character_count,
                "p_word_count": word_count,
                "p_text_checksum": text_checksum,
                "p_confidence_summary": confidence_summary,
                "p_warnings": warnings,
                "p_provider_metadata_safe": provider_metadata_safe,
                "p_artifact_bucket": artifact_bucket,
                "p_artifact_path": artifact_path,
                "p_artifact_sha256": artifact_sha256,
                "p_artifact_size_bytes": artifact_size_bytes,
                "p_artifact_media_type": artifact_media_type,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def fail_ocr_run(
        self,
        ocr_run_id: uuid.UUID,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        error_code: str,
        error_class: str,
        error_message_safe: str,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "fail_document_ocr_run",
            {
                "p_ocr_run_id": str(ocr_run_id),
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_error_code": error_code,
                "p_error_class": error_class,
                "p_error_message_safe": error_message_safe,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    # -- Sprint 1-D3: deterministic page-aware chunking (migration 0012) ----
    # Same trust boundary as every method above — never granted to
    # `authenticated`/`anon`. get_document_chunking_job_context is this
    # Worker's own un-gated equivalent of get_document_page_text_readiness
    # (which cannot be called from here — see the comment on that function
    # in migration 0012 for why).

    def get_chunking_job_context(
        self, job_id: uuid.UUID, worker_instance_id: str, lease_token: str
    ) -> list[dict[str, Any]]:
        return self._rpc(
            "get_document_chunking_job_context",
            {
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
            },
        )

    def create_chunking_run(
        self,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        extraction_run_id: uuid.UUID,
        extraction_review_id: uuid.UUID,
        source_sha256: str,
        input_manifest: dict[str, Any],
        input_manifest_sha256: str,
        pipeline_version: str,
        configuration_version: str,
        normalization_version: str,
        tokenizer_name: str,
        tokenizer_version: str,
        ocr_request_id: uuid.UUID | None = None,
        ocr_review_id: uuid.UUID | None = None,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "create_document_chunking_run",
            {
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_extraction_run_id": str(extraction_run_id),
                "p_extraction_review_id": str(extraction_review_id),
                "p_source_sha256": source_sha256,
                "p_input_manifest": input_manifest,
                "p_input_manifest_sha256": input_manifest_sha256,
                "p_pipeline_version": pipeline_version,
                "p_configuration_version": configuration_version,
                "p_normalization_version": normalization_version,
                "p_tokenizer_name": tokenizer_name,
                "p_tokenizer_version": tokenizer_version,
                "p_ocr_request_id": str(ocr_request_id) if ocr_request_id else None,
                "p_ocr_review_id": str(ocr_review_id) if ocr_review_id else None,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def finalize_chunking_run(
        self,
        chunking_run_id: uuid.UUID,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        chunks: list[dict[str, Any]],
        metrics: dict[str, Any],
        warnings: list[str],
        artifact_bucket: str,
        artifact_path: str,
        artifact_sha256: str,
        artifact_size_bytes: int,
        artifact_media_type: str,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "finalize_document_chunking_run",
            {
                "p_chunking_run_id": str(chunking_run_id),
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_chunks": chunks,
                "p_metrics": metrics,
                "p_warnings": warnings,
                "p_artifact_bucket": artifact_bucket,
                "p_artifact_path": artifact_path,
                "p_artifact_sha256": artifact_sha256,
                "p_artifact_size_bytes": artifact_size_bytes,
                "p_artifact_media_type": artifact_media_type,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def fail_chunking_run(
        self,
        chunking_run_id: uuid.UUID,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        error_code: str,
        error_class: str,
        error_message_safe: str,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "fail_document_chunking_run",
            {
                "p_chunking_run_id": str(chunking_run_id),
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_error_code": error_code,
                "p_error_class": error_class,
                "p_error_message_safe": error_message_safe,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    # -- Sprint 1-E1: retrieval evaluation (migration 0015) ------------------
    # Same trust boundary as every method above — never granted to
    # `authenticated`/`anon`. get_retrieval_evaluation_job_context is this
    # Worker's dataset-scoped equivalent of get_chunking_job_context.

    def get_retrieval_evaluation_job_context(
        self, job_id: uuid.UUID, worker_instance_id: str, lease_token: str
    ) -> list[dict[str, Any]]:
        return self._rpc(
            "get_retrieval_evaluation_job_context",
            {
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
            },
        )

    def get_retrieval_candidates(
        self,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        dataset_id: uuid.UUID,
        normalized_query_text: str,
    ) -> list[dict[str, Any]]:
        return self._rpc(
            "get_retrieval_candidates",
            {
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_dataset_id": str(dataset_id),
                "p_normalized_query_text": normalized_query_text,
            },
        )

    def get_relevance_judgments(self, dataset_id: uuid.UUID) -> list[dict[str, Any]]:
        """Plain trusted table read (service_role bypasses RLS) — the
        Worker needs every judgment for the frozen dataset to compute
        metrics; there is no RPC for this because it is not a mutation and
        no Worker-specific validation is needed beyond the dataset already
        being frozen (enforced by get_retrieval_evaluation_job_context)."""
        url = f"{self._base_url}/rest/v1/retrieval_relevance_judgments"
        params = {"dataset_id": f"eq.{dataset_id}", "select": "query_id,corpus_item_id,relevance_grade"}
        try:
            response = self._client.get(url, headers=self._headers, params=params)
        except httpx.HTTPError as exc:
            raise OrchestrationError(f"get_relevance_judgments: transport error: {exc.__class__.__name__}") from exc
        if response.status_code >= 400:
            raise OrchestrationError(f"get_relevance_judgments failed ({response.status_code})")
        return response.json()

    def finalize_retrieval_evaluation_run(
        self,
        run_id: uuid.UUID,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        results: list[dict[str, Any]],
        metrics: list[dict[str, Any]],
        failures: list[dict[str, Any]],
        artifact_bucket: str,
        artifact_path: str,
        artifact_sha256: str,
        artifact_size_bytes: int,
        artifact_media_type: str,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "finalize_retrieval_evaluation_run",
            {
                "p_run_id": str(run_id),
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_results": results,
                "p_metrics": metrics,
                "p_failures": failures,
                "p_artifact_bucket": artifact_bucket,
                "p_artifact_path": artifact_path,
                "p_artifact_sha256": artifact_sha256,
                "p_artifact_size_bytes": artifact_size_bytes,
                "p_artifact_media_type": artifact_media_type,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}

    def fail_retrieval_evaluation_run(
        self,
        run_id: uuid.UUID,
        job_id: uuid.UUID,
        worker_instance_id: str,
        lease_token: str,
        error_code: str,
        error_class: str,
        error_message_safe: str,
        correlation_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        rows = self._rpc(
            "fail_retrieval_evaluation_run",
            {
                "p_run_id": str(run_id),
                "p_processing_job_id": str(job_id),
                "p_worker_instance_id": worker_instance_id,
                "p_lease_token": lease_token,
                "p_error_code": error_code,
                "p_error_class": error_class,
                "p_error_message_safe": error_message_safe,
                "p_correlation_id": str(correlation_id) if correlation_id else None,
            },
        )
        return rows[0] if rows else {}


def _jsonable(payload: dict[str, Any]) -> dict[str, Any]:
    return {k: (str(v) if isinstance(v, uuid.UUID) else v) for k, v in payload.items()}
