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
    source_document_id: uuid.UUID
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
            source_document_id=uuid.UUID(row["out_source_document_id"]),
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


def _jsonable(payload: dict[str, Any]) -> dict[str, Any]:
    return {k: (str(v) if isinstance(v, uuid.UUID) else v) for k, v in payload.items()}
