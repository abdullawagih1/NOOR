"""
End-to-end processor tests (mission §34, §23) against a fake in-memory
OrchestrationClient (DB layer) and a mocked Storage HTTP layer
(httpx.MockTransport) — no real network, no real Supabase project, no
real Postgres. Real RLS/lifecycle correctness for the three new SQL
functions is proven separately in
supabase/tests/rls/008_pdf_extraction.sql; this file proves the Worker's
own orchestration of those calls (reuse, failure reporting, idempotent
replay, lease-loss tolerance) against a controllable fake.
"""
from __future__ import annotations

import uuid
from pathlib import Path

import httpx
import pytest

from app.orchestration_client import ClaimedJob, OrchestrationError
from app.pdf_extraction.processor import make_extraction_processor

FIXTURES_DIR = Path(__file__).parent / "fixtures" / "pdf"


def make_claimed_job(source_document_id=None) -> ClaimedJob:
    return ClaimedJob(
        job_id=uuid.uuid4(),
        organization_id=uuid.uuid4(),
        source_document_id=source_document_id or uuid.uuid4(),
        job_type="document_parsing",
        pipeline_version="v1",
        correlation_id=uuid.uuid4(),
        attempt_number=1,
        lease_token="a" * 64,
        lease_expires_at="2026-01-01T00:00:00Z",
    )


class FakeExtractionOrchestrationClient:
    """A minimal fake covering exactly the methods
    app/pdf_extraction/processor.py calls — mirrors the
    FakeOrchestrationClient pattern in test_worker_loop.py."""

    def __init__(self, source_document: dict, existing_succeeded_run: dict | None = None) -> None:
        self.source_document = source_document
        self.calls: list[tuple[str, dict]] = []
        self.raise_on: dict[str, Exception] = {}
        self._existing_succeeded_run = existing_succeeded_run
        self._created_run_id = str(uuid.uuid4())
        self.inserted_pages: list[dict] = []

    def _maybe_raise(self, name: str):
        if name in self.raise_on:
            raise self.raise_on[name]

    def get_source_document(self, source_document_id):
        self.calls.append(("get_source_document", {}))
        self._maybe_raise("get_source_document")
        return self.source_document

    def create_extraction_run(self, job_id, worker_instance_id, lease_token, source_sha256, source_size_bytes, pipeline_version, configuration_version, extractor_name, extractor_version, correlation_id=None):
        self.calls.append(("create_extraction_run", {}))
        self._maybe_raise("create_extraction_run")
        if self._existing_succeeded_run is not None:
            return {"out_extraction_run_id": self._existing_succeeded_run["id"], "out_status": "succeeded", "out_reused": True}
        return {"out_extraction_run_id": self._created_run_id, "out_status": "running", "out_reused": False}

    def insert_extraction_pages(self, pages):
        self.calls.append(("insert_extraction_pages", {"count": len(pages)}))
        self._maybe_raise("insert_extraction_pages")
        self.inserted_pages.extend(pages)

    def finalize_extraction_run(self, extraction_run_id, job_id, worker_instance_id, lease_token, expected_page_count, artifact_bucket, artifact_path, artifact_sha256, artifact_size_bytes, artifact_media_type, **kwargs):
        self.calls.append(("finalize_extraction_run", {"expected_page_count": expected_page_count}))
        self._maybe_raise("finalize_extraction_run")
        return {"out_extraction_run_id": str(extraction_run_id), "out_status": "succeeded", "out_completed_at": "2026-01-01T00:00:00Z"}

    def fail_extraction_run(self, extraction_run_id, job_id, worker_instance_id, lease_token, error_code, error_class, error_message_safe, correlation_id=None):
        self.calls.append(("fail_extraction_run", {"error_code": error_code}))
        self._maybe_raise("fail_extraction_run")
        return {"out_extraction_run_id": str(extraction_run_id), "out_status": "failed"}


def _storage_mock_transport(source_pdf_bytes: bytes):
    uploaded: dict[str, bytes] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if request.method == "GET" and "/guideline-originals/" in path:
            return httpx.Response(200, content=source_pdf_bytes)
        if request.method == "POST" and "/guideline-processed/" in path:
            uploaded[path] = request.content
            return httpx.Response(200, json={"Key": path})
        if request.method == "GET" and "/guideline-processed/" in path:
            if path not in uploaded:
                return httpx.Response(404)
            return httpx.Response(200, content=uploaded[path])
        return httpx.Response(404)

    return httpx.MockTransport(handler), uploaded


def _make_processor(monkeypatch, client, source_pdf_bytes: bytes):
    import app.pdf_extraction.processor as processor_module

    transport, uploaded = _storage_mock_transport(source_pdf_bytes)
    mock_http_client = httpx.Client(transport=transport)

    original_run = processor_module.run_extraction_pipeline

    def patched_run_extraction_pipeline(**kwargs):
        kwargs["http_client"] = mock_http_client
        return original_run(**kwargs)

    # Patch the name as imported INTO app.pdf_extraction.processor
    # (`from app.pdf_extraction.pipeline import run_extraction_pipeline`
    # binds a separate reference there — patching the pipeline module
    # itself would not affect processor.py's already-bound name).
    monkeypatch.setattr(processor_module, "run_extraction_pipeline", patched_run_extraction_pipeline)

    processor = make_extraction_processor(
        client,
        worker_instance_id="noor-worker-extract-test",
        supabase_url="https://example.supabase.co",
        service_role_key="test-service-role-key",
        pipeline_version="pdf-text-v1",
        configuration_version="1",
        extractor_name="pypdf",
        extractor_version="6.14.2",
        max_seconds=30.0,
    )
    return processor, uploaded


def make_source_document(sha256: str, size_bytes: int, status: str = "registered") -> dict:
    return {
        "id": str(uuid.uuid4()),
        "organization_id": str(uuid.uuid4()),
        "status": status,
        "storage_bucket": "guideline-originals",
        "storage_path": "org/doc.pdf",
        "sha256": sha256,
        "size_bytes": size_bytes,
    }


def test_successful_extraction_calls_pages_and_finalize(monkeypatch):
    import hashlib
    source_bytes = (FIXTURES_DIR / "one_page_english.pdf").read_bytes()
    sha256 = hashlib.sha256(source_bytes).hexdigest()
    source_doc = make_source_document(sha256, len(source_bytes))
    client = FakeExtractionOrchestrationClient(source_doc)
    processor, uploaded = _make_processor(monkeypatch, client, source_bytes)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "succeeded"
    call_names = [c[0] for c in client.calls]
    assert "create_extraction_run" in call_names
    assert "insert_extraction_pages" in call_names
    assert "finalize_extraction_run" in call_names
    assert len(client.inserted_pages) == 1
    assert len(uploaded) == 1


def test_reused_identity_skips_extraction_entirely(monkeypatch):
    source_doc = make_source_document("a" * 64, 1000)
    existing_run = {"id": str(uuid.uuid4())}
    client = FakeExtractionOrchestrationClient(source_doc, existing_succeeded_run=existing_run)
    processor, uploaded = _make_processor(monkeypatch, client, b"unused")

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "succeeded"
    assert outcome.result_summary["reused"] is True
    call_names = [c[0] for c in client.calls]
    assert "insert_extraction_pages" not in call_names
    assert "finalize_extraction_run" not in call_names
    assert len(uploaded) == 0


def test_source_not_verified_is_terminal_failure(monkeypatch):
    source_doc = make_source_document("a" * 64, 1000, status="pending_upload")
    client = FakeExtractionOrchestrationClient(source_doc)
    processor, _ = _make_processor(monkeypatch, client, b"unused")

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "source_document_not_verified"


def test_source_checksum_mismatch_is_terminal_failure_and_reports_fail_extraction_run(monkeypatch):
    import hashlib
    source_bytes = (FIXTURES_DIR / "one_page_english.pdf").read_bytes()
    wrong_sha256 = "f" * 64
    source_doc = make_source_document(wrong_sha256, len(source_bytes))
    client = FakeExtractionOrchestrationClient(source_doc)
    processor, _ = _make_processor(monkeypatch, client, source_bytes)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "terminal_failure"
    # create_extraction_run's DB-side check (mock returns "running" here
    # since our fake doesn't itself validate checksums — the real
    # validation is proven in 008_pdf_extraction.sql TEST 2) — this test
    # instead proves the download-time mismatch (source_download.py) is
    # caught and reported.
    assert outcome.error_code == "source_checksum_mismatch"
    fail_calls = [c for c in client.calls if c[0] == "fail_extraction_run"]
    assert len(fail_calls) == 1
    assert fail_calls[0][1]["error_code"] == "source_checksum_mismatch"


def test_corrupt_source_pdf_is_terminal_failure(monkeypatch):
    import hashlib
    corrupt_bytes = (FIXTURES_DIR / "corrupt.pdf").read_bytes()
    sha256 = hashlib.sha256(corrupt_bytes).hexdigest()
    source_doc = make_source_document(sha256, len(corrupt_bytes))
    client = FakeExtractionOrchestrationClient(source_doc)
    processor, _ = _make_processor(monkeypatch, client, corrupt_bytes)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "corrupt_pdf"


def test_encrypted_source_pdf_is_terminal_failure(monkeypatch):
    import hashlib
    encrypted_bytes = (FIXTURES_DIR / "encrypted.pdf").read_bytes()
    sha256 = hashlib.sha256(encrypted_bytes).hexdigest()
    source_doc = make_source_document(sha256, len(encrypted_bytes))
    client = FakeExtractionOrchestrationClient(source_doc)
    processor, _ = _make_processor(monkeypatch, client, encrypted_bytes)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "password_protected_pdf"


def test_lease_loss_at_finalize_is_reported_gracefully_not_crashed(monkeypatch):
    import hashlib
    source_bytes = (FIXTURES_DIR / "one_page_english.pdf").read_bytes()
    sha256 = hashlib.sha256(source_bytes).hexdigest()
    source_doc = make_source_document(sha256, len(source_bytes))
    client = FakeExtractionOrchestrationClient(source_doc)
    client.raise_on["finalize_extraction_run"] = OrchestrationError("lease not held by this worker")
    processor, _ = _make_processor(monkeypatch, client, source_bytes)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)  # must not raise

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "database_finalization_failed"


def test_fail_extraction_run_failure_is_swallowed_not_crashed(monkeypatch):
    """If even reporting the failure fails (lease already lost — expected
    under crash-recovery races), the processor must not raise."""
    import hashlib
    corrupt_bytes = (FIXTURES_DIR / "corrupt.pdf").read_bytes()
    sha256 = hashlib.sha256(corrupt_bytes).hexdigest()
    source_doc = make_source_document(sha256, len(corrupt_bytes))
    client = FakeExtractionOrchestrationClient(source_doc)
    client.raise_on["fail_extraction_run"] = OrchestrationError("lease not held by this worker")
    processor, _ = _make_processor(monkeypatch, client, corrupt_bytes)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)  # must not raise

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "corrupt_pdf"
