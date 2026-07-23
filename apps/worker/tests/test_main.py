import os
import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

VALID_TOKEN = os.environ["WORKER_INTERNAL_TOKEN"]
AUTH_HEADER = {"Authorization": f"Bearer {VALID_TOKEN}"}


def valid_payload(**overrides):
    payload = {
        "job_id": str(uuid.uuid4()),
        "organization_id": str(uuid.uuid4()),
        "document_id": str(uuid.uuid4()),
        "operation": "document_parsing",
        "requested_by": str(uuid.uuid4()),
        "correlation_id": str(uuid.uuid4()),
        "idempotency_key": "doc-parse-abc123",
    }
    payload.update(overrides)
    return payload


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_ready():
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_accept_job_valid_contract():
    payload = valid_payload()
    r = client.post("/jobs", json=payload, headers=AUTH_HEADER)
    assert r.status_code == 200
    body = r.json()
    assert body["job_id"] == payload["job_id"]
    assert body["status"] == "accepted"


def test_accept_job_rejects_unknown_operation():
    payload = valid_payload(operation="delete_everything")
    r = client.post("/jobs", json=payload, headers=AUTH_HEADER)
    assert r.status_code == 422


def test_accept_job_rejects_missing_idempotency_key():
    payload = valid_payload(idempotency_key="")
    r = client.post("/jobs", json=payload, headers=AUTH_HEADER)
    assert r.status_code == 422


def test_accept_job_rejects_missing_token():
    r = client.post("/jobs", json=valid_payload())
    assert r.status_code == 401


def test_accept_job_rejects_malformed_auth_header():
    r = client.post("/jobs", json=valid_payload(), headers={"Authorization": VALID_TOKEN})
    assert r.status_code == 401


def test_accept_job_rejects_invalid_token():
    r = client.post("/jobs", json=valid_payload(), headers={"Authorization": "Bearer wrong-token"})
    assert r.status_code == 403


def test_accept_job_error_does_not_reveal_expected_token():
    r = client.post("/jobs", json=valid_payload(), headers={"Authorization": "Bearer wrong-token"})
    assert VALID_TOKEN not in r.text
