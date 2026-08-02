"""
End-to-end processor tests (Sprint 1-E1, ADR 0015) against a fake
in-memory OrchestrationClient (DB layer) and a mocked Storage HTTP layer
(httpx.MockTransport) — no real network, no real Supabase project, no
real Postgres. Real RLS/lifecycle correctness for the four new Worker-only
SQL functions is proven separately in
supabase/tests/rls/013_retrieval_evaluation.sql; this file proves the
Worker's own orchestration of those calls (context read, candidate fetch,
finalize, fail-on-error) against a controllable fake.
"""
from __future__ import annotations

import uuid

import httpx

from app.orchestration_client import ClaimedJob, OrchestrationError
from app.retrieval.processor import make_retrieval_evaluation_processor

DATASET_ID = str(uuid.uuid4())
RUN_ID = str(uuid.uuid4())


def make_claimed_job() -> ClaimedJob:
    return ClaimedJob(
        job_id=uuid.uuid4(),
        organization_id=uuid.uuid4(),
        source_document_id=None,
        job_type="retrieval_evaluation",
        pipeline_version="v1",
        correlation_id=uuid.uuid4(),
        attempt_number=1,
        lease_token="a" * 64,
        lease_expires_at="2026-01-01T00:00:00Z",
    )


CONTEXT_ROW = {
    "out_dataset_id": DATASET_ID,
    "out_dataset_sha256": "a" * 64,
    "out_run_id": RUN_ID,
    "out_retriever_name": "noor-lexical-baseline",
    "out_retriever_version": "1",
    "out_retrieval_configuration_version": "1",
    "out_query_normalization_version": "retrieval_text_normalization_v1",
    "out_metric_definition_version": "1",
    "out_top_k_values": [1, 3, 5, 10],
    "out_relevance_threshold": 2,
    "out_query_id": "q-en",
    "out_query_key": "q-en-exact",
    "out_normalized_query_text": "blood pressure measurement",
    "out_language": "en",
    "out_category": "english_exact",
    "out_difficulty": "basic",
    "out_is_negative_control": False,
}

CANDIDATE_ROW = {
    "out_corpus_item_id": "ci-1",
    "out_full_text_rank": 0.6,
    "out_normalized_search_text": "blood pressure measurement technique",
    "out_token_count": 5,
    "out_display_order": 1,
    "out_chunk_checksum": "chk-1",
}


class FakeRetrievalOrchestrationClient:
    """A minimal fake covering exactly the methods
    app/retrieval/processor.py calls — mirrors
    FakeExtractionOrchestrationClient in test_pdf_extraction_processor.py."""

    def __init__(self, context_rows=None, candidate_rows=None, judgment_rows=None) -> None:
        self.context_rows = context_rows if context_rows is not None else [CONTEXT_ROW]
        self.candidate_rows = candidate_rows if candidate_rows is not None else [CANDIDATE_ROW]
        self.judgment_rows = judgment_rows if judgment_rows is not None else [{"query_id": "q-en", "corpus_item_id": "ci-1", "relevance_grade": 3}]
        self.calls: list[str] = []
        self.raise_on: dict[str, Exception] = {}

    def _maybe_raise(self, name: str):
        if name in self.raise_on:
            raise self.raise_on[name]

    def get_retrieval_evaluation_job_context(self, job_id, worker_instance_id, lease_token):
        self.calls.append("get_retrieval_evaluation_job_context")
        self._maybe_raise("get_retrieval_evaluation_job_context")
        return self.context_rows

    def get_relevance_judgments(self, dataset_id):
        self.calls.append("get_relevance_judgments")
        self._maybe_raise("get_relevance_judgments")
        return self.judgment_rows

    def get_retrieval_candidates(self, job_id, worker_instance_id, lease_token, dataset_id, normalized_query_text):
        self.calls.append("get_retrieval_candidates")
        self._maybe_raise("get_retrieval_candidates")
        return self.candidate_rows

    def finalize_retrieval_evaluation_run(self, run_id, job_id, worker_instance_id, lease_token, results, metrics, failures, artifact_bucket, artifact_path, artifact_sha256, artifact_size_bytes, artifact_media_type, correlation_id=None):
        self.calls.append("finalize_retrieval_evaluation_run")
        self._maybe_raise("finalize_retrieval_evaluation_run")
        return {"out_run_id": str(run_id), "out_status": "succeeded", "out_result_count": len(results)}

    def fail_retrieval_evaluation_run(self, run_id, job_id, worker_instance_id, lease_token, error_code, error_class, error_message_safe, correlation_id=None):
        self.calls.append("fail_retrieval_evaluation_run")
        self._maybe_raise("fail_retrieval_evaluation_run")
        return {"out_run_id": str(run_id), "out_status": "failed"}


def _storage_mock_transport():
    uploaded: dict[str, bytes] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if request.method == "POST" and "/guideline-processed/" in path:
            uploaded[path] = request.content
            return httpx.Response(200, json={"Key": path})
        if request.method == "GET" and "/guideline-processed/" in path:
            if path not in uploaded:
                return httpx.Response(404)
            return httpx.Response(200, content=uploaded[path])
        return httpx.Response(404)

    return httpx.MockTransport(handler), uploaded


def _make_processor(monkeypatch, client):
    import app.retrieval.processor as processor_module

    transport, uploaded = _storage_mock_transport()
    mock_http_client = httpx.Client(transport=transport)

    original_upload = processor_module.upload_evaluation_artifact

    def patched_upload(**kwargs):
        kwargs["http_client"] = mock_http_client
        return original_upload(**kwargs)

    monkeypatch.setattr(processor_module, "upload_evaluation_artifact", patched_upload)

    processor = make_retrieval_evaluation_processor(
        client,
        worker_instance_id="noor-worker-retrieval-test",
        supabase_url="https://example.supabase.co",
        service_role_key="test-service-role-key",
    )
    return processor, uploaded


def test_successful_evaluation_run_finalizes_with_results(monkeypatch):
    client = FakeRetrievalOrchestrationClient()
    processor, uploaded = _make_processor(monkeypatch, client)

    outcome = processor(make_claimed_job(), lambda: None)

    assert outcome.kind == "succeeded"
    assert outcome.result_summary["evaluation_run_id"] == RUN_ID
    assert "finalize_retrieval_evaluation_run" in client.calls
    assert len(uploaded) == 1  # exactly one artifact uploaded


def test_dataset_no_longer_frozen_is_a_terminal_failure(monkeypatch):
    client = FakeRetrievalOrchestrationClient()
    client.raise_on["get_retrieval_evaluation_job_context"] = OrchestrationError("dataset x is no longer frozen (status: archived)")
    processor, _ = _make_processor(monkeypatch, client)

    outcome = processor(make_claimed_job(), lambda: None)

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "dataset_not_frozen"


def test_no_active_queries_is_a_terminal_failure(monkeypatch):
    client = FakeRetrievalOrchestrationClient(context_rows=[])
    processor, _ = _make_processor(monkeypatch, client)

    outcome = processor(make_claimed_job(), lambda: None)

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "evaluation_job_context_not_found"


def test_candidate_fetch_error_reports_a_retryable_failure_and_fails_the_run(monkeypatch):
    client = FakeRetrievalOrchestrationClient()
    client.raise_on["get_retrieval_candidates"] = RuntimeError("transport exploded")
    processor, _ = _make_processor(monkeypatch, client)

    outcome = processor(make_claimed_job(), lambda: None)

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "candidate_fetch_failed"
    assert "fail_retrieval_evaluation_run" in client.calls


def test_finalize_failure_reports_database_finalization_failed(monkeypatch):
    client = FakeRetrievalOrchestrationClient()
    client.raise_on["finalize_retrieval_evaluation_run"] = OrchestrationError("finalize failed (500)")
    processor, _ = _make_processor(monkeypatch, client)

    outcome = processor(make_claimed_job(), lambda: None)

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "database_finalization_failed"
    assert "fail_retrieval_evaluation_run" in client.calls
