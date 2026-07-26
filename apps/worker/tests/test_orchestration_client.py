"""
Tests for the PostgREST RPC wrapper (app/orchestration_client.py) using
httpx.MockTransport — no real network, no real Supabase project. Verifies
request shape (correct function names, correct payload keys) and response
parsing (empty claim -> None, error status -> OrchestrationError with a
safe message, no lease token ever appearing in a raised exception's text).
"""
from __future__ import annotations

import json
import uuid

import httpx
import pytest

from app.orchestration_client import OrchestrationClient, OrchestrationError

SUPABASE_URL = "https://example.supabase.co"
SERVICE_ROLE_KEY = "test-service-role-key"


def make_client(handler) -> OrchestrationClient:
    transport = httpx.MockTransport(handler)
    http_client = httpx.Client(transport=transport)
    return OrchestrationClient(SUPABASE_URL, SERVICE_ROLE_KEY, http_client=http_client)


def test_claim_sends_expected_function_and_headers_and_returns_none_for_empty_array():
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = dict(request.headers)
        captured["body"] = json.loads(request.content)
        return httpx.Response(200, json=[])

    client = make_client(handler)
    result = client.claim_next_job("noor-worker-test-1")

    assert result is None
    assert captured["url"] == f"{SUPABASE_URL}/rest/v1/rpc/claim_next_document_processing_job"
    assert captured["headers"]["apikey"] == SERVICE_ROLE_KEY
    assert captured["headers"]["authorization"] == f"Bearer {SERVICE_ROLE_KEY}"
    assert captured["body"]["p_worker_instance_id"] == "noor-worker-test-1"
    assert captured["body"]["p_job_types"] == ["document_parsing"]
    assert "p_correlation_id" not in captured["body"]  # None fields are omitted, not sent as null


def test_claim_parses_a_real_row_into_a_claimed_job():
    job_id = str(uuid.uuid4())
    org_id = str(uuid.uuid4())
    doc_id = str(uuid.uuid4())
    corr_id = str(uuid.uuid4())

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json=[
                {
                    "out_job_id": job_id,
                    "out_organization_id": org_id,
                    "out_source_document_id": doc_id,
                    "out_job_type": "document_parsing",
                    "out_pipeline_version": "v1",
                    "out_correlation_id": corr_id,
                    "out_attempt_number": 1,
                    "out_lease_token": "a" * 64,
                    "out_lease_expires_at": "2026-01-01T00:00:00Z",
                }
            ],
        )

    client = make_client(handler)
    result = client.claim_next_job("noor-worker-test-1")

    assert result is not None
    assert str(result.job_id) == job_id
    assert result.lease_token == "a" * 64
    assert result.attempt_number == 1


def test_error_response_raises_orchestration_error_with_safe_message():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"message": "lease not held by this worker", "code": "P0001"})

    client = make_client(handler)
    with pytest.raises(OrchestrationError) as excinfo:
        client.heartbeat_job(uuid.uuid4(), "noor-worker-test-1", "the-secret-lease-token")

    assert "lease not held" in str(excinfo.value)
    assert "the-secret-lease-token" not in str(excinfo.value)


def test_transport_failure_raises_orchestration_error():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused", request=request)

    client = make_client(handler)
    with pytest.raises(OrchestrationError):
        client.claim_next_job("noor-worker-test-1")


def test_complete_job_sends_result_summary_and_idempotency_key():
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["body"] = json.loads(request.content)
        return httpx.Response(200, json=[{"out_job_id": str(uuid.uuid4()), "out_status": "succeeded", "out_completed_at": "2026-01-01T00:00:00Z"}])

    client = make_client(handler)
    job_id = uuid.uuid4()
    client.complete_job(
        job_id, "noor-worker-test-1", "lease-token-xyz",
        result_summary={"processor": "orchestration-noop"}, idempotency_key="k1",
    )

    assert captured["body"]["p_result_summary"] == {"processor": "orchestration-noop"}
    assert captured["body"]["p_idempotency_key"] == "k1"
    assert captured["body"]["p_lease_token"] == "lease-token-xyz"


def test_fail_job_sends_retryable_flag_and_error_fields():
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["body"] = json.loads(request.content)
        return httpx.Response(
            200,
            json=[
                {
                    "out_job_id": str(uuid.uuid4()),
                    "out_status": "retry_scheduled",
                    "out_next_attempt_at": "2026-01-01T00:00:30Z",
                    "out_attempt_count": 1,
                    "out_max_attempts": 3,
                }
            ],
        )

    client = make_client(handler)
    client.fail_job(
        uuid.uuid4(), "noor-worker-test-1", "lease-token-xyz",
        error_code="transient_error", error_class="transient", error_message_safe="simulated",
        retryable=True,
    )

    assert captured["body"]["p_retryable"] is True
    assert captured["body"]["p_error_code"] == "transient_error"


def test_recover_expired_jobs_returns_list_of_rows():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[{"out_job_id": str(uuid.uuid4()), "out_new_status": "retry_scheduled"}])

    client = make_client(handler)
    rows = client.recover_expired_jobs()
    assert len(rows) == 1
    assert rows[0]["out_new_status"] == "retry_scheduled"
