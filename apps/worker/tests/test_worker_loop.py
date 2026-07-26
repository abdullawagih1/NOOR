"""
Tests for the claim -> start -> heartbeat -> complete/fail cycle
(app/worker_loop.py) against a fake, in-memory OrchestrationClient — no
real network, no real Supabase project, no real sleeping (the heartbeat
interval is set to a tiny value in tests that need to observe more than
one heartbeat tick).

Test-only processor modes (retryable failure, terminal failure, lease-loss
simulation) are defined here as plain functions matching the `Processor`
contract — never inside app/processing.py itself (ADR 0009: no production
code path may select a failure-injecting processor).
"""
from __future__ import annotations

import threading
import time
import uuid
from typing import Callable

import pytest

from app.orchestration_client import ClaimedJob, OrchestrationError
from app.processing import ProcessingOutcome, noop_processor
from app.worker_loop import WorkerLoop


def make_claimed_job(**overrides) -> ClaimedJob:
    defaults = dict(
        job_id=uuid.uuid4(),
        organization_id=uuid.uuid4(),
        source_document_id=uuid.uuid4(),
        job_type="document_parsing",
        pipeline_version="v1",
        correlation_id=uuid.uuid4(),
        attempt_number=1,
        lease_token="a" * 64,
        lease_expires_at="2026-01-01T00:00:00Z",
    )
    defaults.update(overrides)
    return ClaimedJob(**defaults)


class FakeOrchestrationClient:
    """Records every call; queues claimable jobs; can be told to fail specific calls."""

    def __init__(self, jobs_to_claim: list[ClaimedJob] | None = None) -> None:
        self._jobs = list(jobs_to_claim or [])
        self.calls: list[tuple[str, dict]] = []
        self.raise_on: dict[str, Exception] = {}

    def _maybe_raise(self, name: str) -> None:
        if name in self.raise_on:
            raise self.raise_on[name]

    def recover_expired_jobs(self, correlation_id=None):
        self.calls.append(("recover_expired_jobs", {}))
        self._maybe_raise("recover_expired_jobs")
        return []

    def claim_next_job(self, worker_instance_id, job_types=None, lease_duration_seconds=90, correlation_id=None):
        self.calls.append(("claim_next_job", {"worker_instance_id": worker_instance_id}))
        self._maybe_raise("claim_next_job")
        if self._jobs:
            return self._jobs.pop(0)
        return None

    def start_job(self, job_id, worker_instance_id, lease_token, correlation_id=None):
        self.calls.append(("start_job", {"job_id": job_id, "lease_token": lease_token}))
        self._maybe_raise("start_job")
        return {"out_job_id": str(job_id), "out_status": "processing"}

    def heartbeat_job(self, job_id, worker_instance_id, lease_token, lease_duration_seconds=90):
        self.calls.append(("heartbeat_job", {"job_id": job_id}))
        self._maybe_raise("heartbeat_job")
        return {"out_job_id": str(job_id)}

    def complete_job(self, job_id, worker_instance_id, lease_token, result_summary, idempotency_key=None, correlation_id=None):
        self.calls.append(("complete_job", {"job_id": job_id, "result_summary": result_summary}))
        self._maybe_raise("complete_job")
        return {"out_job_id": str(job_id), "out_status": "succeeded"}

    def fail_job(self, job_id, worker_instance_id, lease_token, error_code, error_class, error_message_safe, retryable=True, idempotency_key=None, correlation_id=None):
        self.calls.append((
            "fail_job",
            {"job_id": job_id, "error_code": error_code, "retryable": retryable, "error_message_safe": error_message_safe},
        ))
        self._maybe_raise("fail_job")
        return {"out_job_id": str(job_id), "out_status": "retry_scheduled" if retryable else "dead_lettered"}


def call_names(client: FakeOrchestrationClient) -> list[str]:
    return [name for name, _ in client.calls]


# ---------------------------------------------------------------------------
# Basic cycle
# ---------------------------------------------------------------------------

def test_run_claim_cycle_returns_false_when_no_job_available():
    client = FakeOrchestrationClient(jobs_to_claim=[])
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=60)
    assert loop.run_claim_cycle() is False
    assert call_names(client) == ["recover_expired_jobs", "claim_next_job"]


def test_run_claim_cycle_success_path_calls_start_then_complete():
    job = make_claimed_job()
    client = FakeOrchestrationClient(jobs_to_claim=[job])
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=60, processor=noop_processor)

    found = loop.run_claim_cycle()

    assert found is True
    names = call_names(client)
    assert names == ["recover_expired_jobs", "claim_next_job", "start_job", "complete_job"]
    complete_call = client.calls[-1][1]
    assert complete_call["result_summary"]["processor"] == "orchestration-noop"


def test_start_failure_does_not_call_complete_or_fail():
    job = make_claimed_job()
    client = FakeOrchestrationClient(jobs_to_claim=[job])
    client.raise_on["start_job"] = OrchestrationError("lease already claimed by someone else")
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=60)

    found = loop.run_claim_cycle()

    assert found is True  # a job WAS claimed, even though starting it failed
    assert call_names(client) == ["recover_expired_jobs", "claim_next_job", "start_job"]


# ---------------------------------------------------------------------------
# Processor outcomes
# ---------------------------------------------------------------------------

def retryable_failure_processor(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
    return ProcessingOutcome(
        kind="retryable_failure",
        error_code="simulated_retryable",
        error_class="test_simulated",
        error_message_safe="simulated retryable failure for testing",
    )


def terminal_failure_processor(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
    return ProcessingOutcome(
        kind="terminal_failure",
        error_code="simulated_terminal",
        error_class="test_simulated",
        error_message_safe="simulated terminal failure for testing",
    )


def raising_processor(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
    raise RuntimeError("boom — this text must never reach fail_job's error_message_safe")


def test_retryable_failure_outcome_calls_fail_job_with_retryable_true():
    job = make_claimed_job()
    client = FakeOrchestrationClient(jobs_to_claim=[job])
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=60, processor=retryable_failure_processor)

    loop.run_claim_cycle()

    assert call_names(client) == ["recover_expired_jobs", "claim_next_job", "start_job", "fail_job"]
    fail_call = client.calls[-1][1]
    assert fail_call["retryable"] is True
    assert fail_call["error_code"] == "simulated_retryable"


def test_terminal_failure_outcome_calls_fail_job_with_retryable_false():
    job = make_claimed_job()
    client = FakeOrchestrationClient(jobs_to_claim=[job])
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=60, processor=terminal_failure_processor)

    loop.run_claim_cycle()

    fail_call = client.calls[-1][1]
    assert fail_call["retryable"] is False
    assert fail_call["error_code"] == "simulated_terminal"


def test_processor_exception_is_caught_and_reported_as_retryable_with_a_safe_message():
    job = make_claimed_job()
    client = FakeOrchestrationClient(jobs_to_claim=[job])
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=60, processor=raising_processor)

    loop.run_claim_cycle()  # must not raise — the exception is caught internally

    fail_call = client.calls[-1][1]
    assert fail_call["retryable"] is True
    assert "boom" not in fail_call["error_message_safe"]
    assert fail_call["error_message_safe"] == "the processor raised an unexpected exception"


# ---------------------------------------------------------------------------
# Heartbeat during processing
# ---------------------------------------------------------------------------

def test_long_running_processor_receives_periodic_heartbeats():
    """Simulates a processor that runs long enough for the background
    heartbeat thread to fire at least once (heartbeat_interval_seconds is
    set very small for the test; no real lease-duration wait is needed)."""
    heartbeats_seen = threading.Event()

    def slow_processor(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        time.sleep(0.3)
        return ProcessingOutcome(kind="succeeded", result_summary={"processor": "test-slow"})

    job = make_claimed_job()
    client = FakeOrchestrationClient(jobs_to_claim=[job])
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=0.05, processor=slow_processor)  # type: ignore[arg-type]

    loop.run_claim_cycle()

    heartbeat_calls = [c for c in client.calls if c[0] == "heartbeat_job"]
    assert len(heartbeat_calls) >= 1, "expected at least one background heartbeat during a 0.3s job with a 0.05s interval"


def test_heartbeat_failure_during_processing_does_not_crash_the_cycle():
    def slow_processor(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        time.sleep(0.15)
        return ProcessingOutcome(kind="succeeded", result_summary={})

    job = make_claimed_job()
    client = FakeOrchestrationClient(jobs_to_claim=[job])
    client.raise_on["heartbeat_job"] = OrchestrationError("lease lost — reclaimed by recovery")
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=0.05, processor=slow_processor)  # type: ignore[arg-type]

    found = loop.run_claim_cycle()  # must not raise despite every heartbeat failing

    assert found is True
    assert call_names(client)[-1] == "complete_job"


def test_report_outcome_swallows_orchestration_error_when_lease_already_lost():
    job = make_claimed_job()
    client = FakeOrchestrationClient(jobs_to_claim=[job])
    client.raise_on["complete_job"] = OrchestrationError("lease not held by this worker")
    loop = WorkerLoop(client, "noor-worker-test", heartbeat_interval_seconds=60, processor=noop_processor)

    loop.run_claim_cycle()  # must not raise


# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------

def test_run_forever_stops_promptly_when_stop_is_called():
    client = FakeOrchestrationClient(jobs_to_claim=[])
    loop = WorkerLoop(client, "noor-worker-test", poll_interval_seconds=60, heartbeat_interval_seconds=60)

    thread = threading.Thread(target=loop.run_forever, daemon=True)
    thread.start()
    time.sleep(0.05)  # let the loop enter its idle wait
    loop.stop()
    thread.join(timeout=2)

    assert not thread.is_alive(), "run_forever should exit promptly once stop() is called, not wait out the full poll interval"


def test_run_forever_drains_multiple_queued_jobs_without_waiting_between_them():
    jobs = [make_claimed_job() for _ in range(3)]
    client = FakeOrchestrationClient(jobs_to_claim=jobs)
    loop = WorkerLoop(client, "noor-worker-test", poll_interval_seconds=60, heartbeat_interval_seconds=60, processor=noop_processor)

    thread = threading.Thread(target=loop.run_forever, daemon=True)
    thread.start()
    time.sleep(0.3)
    loop.stop()
    thread.join(timeout=2)

    complete_calls = [c for c in client.calls if c[0] == "complete_job"]
    assert len(complete_calls) == 3, "all 3 queued jobs should have been drained without waiting the full 60s poll interval between them"
