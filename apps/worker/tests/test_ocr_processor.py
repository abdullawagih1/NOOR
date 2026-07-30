"""
Worker-orchestration tests for the OCR processor (Sprint 1-D2, ADR 0012) —
mirrors test_pdf_extraction_processor.py's philosophy exactly, one layer
deeper: a fake in-memory OrchestrationClient plus monkeypatched
render_source_page/recognize_and_build_artifact prove the Worker's own
claim -> render -> create-run(-with-the-now-known-checksum) ->
reuse-skip-or-recognize -> finalize/fail orchestration and error
classification. Real page rendering (pypdfium2) and real Tesseract
recognition are proven elsewhere: supabase/tests/rls/011_controlled_ocr.sql
(DB-side identity/lifecycle correctness) and a real Docker-image
render+OCR smoke test against the synthetic English/Arabic fixtures (see
docs/verification/sprint-1-d2-controlled-ocr-verification.md) — re-mocking
Tesseract here would only prove the mock, not the real engine.
"""
from __future__ import annotations

import uuid
from pathlib import Path

import pytest

from app.ocr.errors import OcrError
from app.ocr.models import OcrPageResult, RenderedPage
from app.ocr.pipeline import OcrPipelineOutcome
from app.ocr.processor import make_ocr_processor
from app.orchestration_client import ClaimedJob, OrchestrationError


def make_claimed_job(source_document_id=None) -> ClaimedJob:
    return ClaimedJob(
        job_id=uuid.uuid4(),
        organization_id=uuid.uuid4(),
        source_document_id=source_document_id or uuid.uuid4(),
        job_type="document_ocr",
        pipeline_version="controlled-page-ocr-v1",
        correlation_id=uuid.uuid4(),
        attempt_number=1,
        lease_token="a" * 64,
        lease_expires_at="2026-01-01T00:00:00Z",
    )


def make_source_document(sha256: str = "a" * 64, size_bytes: int = 1000, status: str = "registered") -> dict:
    return {
        "id": str(uuid.uuid4()),
        "organization_id": str(uuid.uuid4()),
        "status": status,
        "storage_bucket": "guideline-originals",
        "storage_path": "org/doc.pdf",
        "sha256": sha256,
        "size_bytes": size_bytes,
    }


def make_ocr_context(**overrides) -> dict:
    context = {
        "extraction_run_id": str(uuid.uuid4()),
        "page_number": 1,
        "native_page_checksum": "b" * 64,
        "renderer_name": "pypdfium2",
        "render_configuration_version": "1",
        "provider_name": "tesseract",
        "model_identifier": "tessdata_fast/eng",
        "model_version": "7d4322bd",
        "ocr_configuration_version": "1",
        "language_hints": ["eng"],
    }
    context.update(overrides)
    return context


class FakeOcrOrchestrationClient:
    """A minimal fake covering exactly the methods app/ocr/processor.py
    calls — mirrors FakeExtractionOrchestrationClient's shape one layer
    deeper (an extra get_ocr_job_context lookup, and create_ocr_run's
    identity now includes the rendered page-image checksum/size)."""

    def __init__(self, source_document: dict, ocr_context: dict, existing_succeeded_run_id: str | None = None) -> None:
        self.source_document = source_document
        self.ocr_context = ocr_context
        self.calls: list[tuple[str, dict]] = []
        self.raise_on: dict[str, Exception] = {}
        self._existing_succeeded_run_id = existing_succeeded_run_id
        self._created_run_id = str(uuid.uuid4())

    def _maybe_raise(self, name: str):
        if name in self.raise_on:
            raise self.raise_on[name]

    def get_ocr_job_context(self, job_id):
        self.calls.append(("get_ocr_job_context", {}))
        self._maybe_raise("get_ocr_job_context")
        return self.ocr_context

    def get_source_document(self, source_document_id):
        self.calls.append(("get_source_document", {}))
        self._maybe_raise("get_source_document")
        return self.source_document

    def create_ocr_run(self, job_id, worker_instance_id, lease_token, source_sha256, native_page_checksum,
                        renderer_name, renderer_version, render_configuration_version, render_dpi, render_color_mode,
                        render_image_format, page_image_sha256, page_image_size_bytes, provider_name, provider_version,
                        model_identifier, model_version, ocr_configuration_version, language_hints, correlation_id=None):
        self.calls.append(("create_ocr_run", {
            "page_image_sha256": page_image_sha256,
            "page_image_size_bytes": page_image_size_bytes,
        }))
        self._maybe_raise("create_ocr_run")
        if self._existing_succeeded_run_id is not None:
            return {"out_ocr_run_id": self._existing_succeeded_run_id, "out_status": "succeeded", "out_reused": True}
        return {"out_ocr_run_id": self._created_run_id, "out_status": "running", "out_reused": False}

    def finalize_ocr_page(self, ocr_run_id, job_id, worker_instance_id, lease_token, raw_text, normalized_text,
                           character_count, word_count, text_checksum, confidence_summary, warnings,
                           provider_metadata_safe, artifact_bucket, artifact_path, artifact_sha256,
                           artifact_size_bytes, artifact_media_type, correlation_id=None):
        self.calls.append(("finalize_ocr_page", {"artifact_sha256": artifact_sha256}))
        self._maybe_raise("finalize_ocr_page")
        return {"out_ocr_run_id": str(ocr_run_id), "out_status": "succeeded", "out_completed_at": "2026-01-01T00:00:00Z"}

    def fail_ocr_run(self, ocr_run_id, job_id, worker_instance_id, lease_token, error_code, error_class,
                      error_message_safe, correlation_id=None):
        self.calls.append(("fail_ocr_run", {"error_code": error_code}))
        self._maybe_raise("fail_ocr_run")
        return {"out_ocr_run_id": str(ocr_run_id), "out_status": "failed"}


FAKE_RENDERED = RenderedPage(image_bytes=b"fake-png-bytes", width_px=2481, height_px=3508, checksum="c" * 64)
FAKE_RESULT = OcrPageResult(
    raw_text="Noor synthetic fixture",
    normalized_text="Noor synthetic fixture",
    character_count=22,
    word_count=3,
    text_checksum="d" * 64,
    confidence_summary={"average_confidence": 95.0},
    warnings=[],
    provider_metadata_safe={"language_hints": ["eng"], "oem": 3, "psm": 3},
)


def _make_processor(monkeypatch, client, *, render_side_effect=None, recognize_side_effect=None, max_seconds=30.0):
    import app.ocr.processor as processor_module

    def fake_render_source_page(**kwargs):
        if render_side_effect is not None:
            raise render_side_effect
        return FAKE_RENDERED

    def fake_recognize_and_build_artifact(**kwargs):
        if recognize_side_effect is not None:
            raise recognize_side_effect
        return OcrPipelineOutcome(
            rendered=kwargs["rendered"],
            result=FAKE_RESULT,
            artifact_bytes=b'{"schema_version":"1.0"}',
            artifact_sha256="e" * 64,
            storage_path="org/guideline-ocr/doc/page-1/controlled-page-ocr-v1/tesseract-5.5.0/e" * 1 + ".json",
        )

    # Patch the names as imported INTO app.ocr.processor (`from
    # app.ocr.pipeline import ...` binds separate references there —
    # patching app.ocr.pipeline itself would not affect processor.py's
    # already-bound names), exactly the technique
    # test_pdf_extraction_processor.py already established one layer up.
    monkeypatch.setattr(processor_module, "render_source_page", fake_render_source_page)
    monkeypatch.setattr(processor_module, "recognize_and_build_artifact", fake_recognize_and_build_artifact)

    processor = make_ocr_processor(
        client,
        worker_instance_id="noor-worker-ocr-test",
        supabase_url="https://example.supabase.co",
        service_role_key="test-service-role-key",
        pipeline_version="controlled-page-ocr-v1",
        render_dpi=300,
        render_color_mode="rgb",
        render_image_format="png",
        render_configuration_version="1",
        ocr_configuration_version="1",
        tessdata_dir=Path("/nonexistent/tessdata"),
        max_seconds=max_seconds,
    )
    return processor


def test_successful_ocr_calls_render_create_run_and_finalize_in_order(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    processor = _make_processor(monkeypatch, client)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "succeeded"
    call_names = [c[0] for c in client.calls]
    assert call_names == ["get_ocr_job_context", "get_source_document", "create_ocr_run", "finalize_ocr_page"]
    assert outcome.result_summary["artifact_sha256"] == "e" * 64


def test_create_ocr_run_receives_the_real_rendered_checksum_not_a_placeholder(monkeypatch):
    """The historical bug this guards against: create_ocr_run must be
    called AFTER rendering, with the real page-image checksum/size — never
    an empty-string placeholder filled in later (there is no "later"; the
    checksum is part of the identity create_ocr_run itself keys on)."""
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    processor = _make_processor(monkeypatch, client)

    job = make_claimed_job()
    processor(job, lambda: None)

    create_run_call = next(c for c in client.calls if c[0] == "create_ocr_run")
    assert create_run_call[1]["page_image_sha256"] == FAKE_RENDERED.checksum
    assert create_run_call[1]["page_image_sha256"] != ""
    assert create_run_call[1]["page_image_size_bytes"] == len(FAKE_RENDERED.image_bytes)
    assert create_run_call[1]["page_image_size_bytes"] != 0


def test_reused_identity_skips_recognition_entirely(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    existing_run_id = str(uuid.uuid4())
    client = FakeOcrOrchestrationClient(source_doc, context, existing_succeeded_run_id=existing_run_id)
    processor = _make_processor(monkeypatch, client, recognize_side_effect=AssertionError("must not be called on reuse"))

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "succeeded"
    assert outcome.result_summary["reused"] is True
    assert outcome.result_summary["ocr_run_id"] == existing_run_id
    call_names = [c[0] for c in client.calls]
    assert "finalize_ocr_page" not in call_names
    # create_ocr_run is still called even on reuse — it IS what detects reuse.
    assert "create_ocr_run" in call_names


def test_render_failure_reports_terminal_failure_without_fail_ocr_run(monkeypatch):
    """A render failure happens before any document_ocr_runs row exists
    (create_document_ocr_run has not been called yet), so there is no run
    to report failure against — fail_ocr_run must not be called."""
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    processor = _make_processor(monkeypatch, client, render_side_effect=OcrError("page_render_failed", "page could not be rendered"))

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "page_render_failed"
    call_names = [c[0] for c in client.calls]
    assert "create_ocr_run" not in call_names
    assert "fail_ocr_run" not in call_names


def test_recognition_failure_reports_failure_and_calls_fail_ocr_run(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    processor = _make_processor(monkeypatch, client, recognize_side_effect=OcrError("ocr_provider_error", "provider failed"))

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "ocr_provider_error"
    fail_calls = [c for c in client.calls if c[0] == "fail_ocr_run"]
    assert len(fail_calls) == 1
    assert fail_calls[0][1]["error_code"] == "ocr_provider_error"


def test_ocr_request_page_not_found_is_retryable(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    client.raise_on["get_ocr_job_context"] = OrchestrationError("job is not linked to an OCR request page")
    processor = _make_processor(monkeypatch, client)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "ocr_request_page_not_found"


def test_source_object_missing_is_retryable(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    client.raise_on["get_source_document"] = OrchestrationError("no matching row")
    processor = _make_processor(monkeypatch, client)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "source_object_missing"


def test_create_ocr_run_checksum_mismatch_is_classified_correctly(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    client.raise_on["create_ocr_run"] = OrchestrationError("source checksum does not match the registered document")
    processor = _make_processor(monkeypatch, client)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "source_checksum_mismatch"


def test_create_ocr_run_not_eligible_is_classified_correctly(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    client.raise_on["create_ocr_run"] = OrchestrationError("this OCR request is invalidated and no longer eligible for processing")
    processor = _make_processor(monkeypatch, client)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "terminal_failure"
    assert outcome.error_code == "ocr_request_not_eligible"


def test_finalize_lease_loss_is_reported_gracefully_not_crashed(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    client.raise_on["finalize_ocr_page"] = OrchestrationError("lease not held by this worker")
    processor = _make_processor(monkeypatch, client)

    job = make_claimed_job()
    outcome = processor(job, lambda: None)  # must not raise

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "database_finalization_failed"


def test_fail_ocr_run_failure_is_swallowed_not_crashed(monkeypatch):
    """If even reporting the failure fails (lease already lost — expected
    under crash-recovery races), the processor must not raise."""
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)
    client.raise_on["fail_ocr_run"] = OrchestrationError("lease not held by this worker")
    processor = _make_processor(monkeypatch, client, recognize_side_effect=OcrError("ocr_provider_error", "provider failed"))

    job = make_claimed_job()
    outcome = processor(job, lambda: None)  # must not raise

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "ocr_provider_error"


def test_render_timeout_is_reported_as_ocr_timeout(monkeypatch):
    source_doc = make_source_document()
    context = make_ocr_context()
    client = FakeOcrOrchestrationClient(source_doc, context)

    import app.ocr.processor as processor_module
    import time

    def slow_render(**kwargs):
        time.sleep(0.2)
        return FAKE_RENDERED

    monkeypatch.setattr(processor_module, "render_source_page", slow_render)
    monkeypatch.setattr(processor_module, "recognize_and_build_artifact", lambda **kwargs: pytest.fail("must not reach recognition"))

    processor = make_ocr_processor(
        client,
        worker_instance_id="noor-worker-ocr-test",
        supabase_url="https://example.supabase.co",
        service_role_key="test-service-role-key",
        pipeline_version="controlled-page-ocr-v1",
        render_dpi=300,
        render_color_mode="rgb",
        render_image_format="png",
        render_configuration_version="1",
        ocr_configuration_version="1",
        tessdata_dir=Path("/nonexistent/tessdata"),
        max_seconds=0.05,
    )

    job = make_claimed_job()
    outcome = processor(job, lambda: None)

    assert outcome.kind == "retryable_failure"
    assert outcome.error_code == "ocr_timeout"
    assert "create_ocr_run" not in [c[0] for c in client.calls]
