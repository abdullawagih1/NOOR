import uuid

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_ready():
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_accept_job_valid_contract():
    payload = {
        "job_id": str(uuid.uuid4()),
        "organization_id": str(uuid.uuid4()),
        "document_id": str(uuid.uuid4()),
        "operation": "document_parsing",
        "requested_by": str(uuid.uuid4()),
        "correlation_id": str(uuid.uuid4()),
        "idempotency_key": "doc-parse-abc123",
    }
    r = client.post("/jobs", json=payload)
    assert r.status_code == 200
    body = r.json()
    assert body["job_id"] == payload["job_id"]
    assert body["status"] == "accepted"


def test_accept_job_rejects_unknown_operation():
    payload = {
        "job_id": str(uuid.uuid4()),
        "organization_id": str(uuid.uuid4()),
        "operation": "delete_everything",
        "requested_by": str(uuid.uuid4()),
        "correlation_id": str(uuid.uuid4()),
        "idempotency_key": "bad-op",
    }
    r = client.post("/jobs", json=payload)
    assert r.status_code == 422


def test_accept_job_rejects_missing_idempotency_key():
    payload = {
        "job_id": str(uuid.uuid4()),
        "organization_id": str(uuid.uuid4()),
        "operation": "document_parsing",
        "requested_by": str(uuid.uuid4()),
        "correlation_id": str(uuid.uuid4()),
        "idempotency_key": "",
    }
    r = client.post("/jobs", json=payload)
    assert r.status_code == 422
