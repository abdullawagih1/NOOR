"""
Mode A polling loop (ADR 0009): the Worker periodically calls
`claim_next_document_processing_job()` directly rather than waiting on a
queue message — no queue integration exists yet, and none is required for
correctness (the atomic claim function is safe entirely on its own merits,
proven under real dual-process concurrency in
`supabase/tests/concurrency/verify_concurrent_claim.sh`).

Runs on a background thread inside the FastAPI process (see
`app/main.py`'s lifespan) only when `WORKER_PROCESSING_MODE=noop`.
"""
from __future__ import annotations

import logging
import threading
from typing import Callable

from app.orchestration_client import ClaimedJob, OrchestrationClient, OrchestrationError
from app.processing import Processor, ProcessingOutcome, noop_processor

logger = logging.getLogger("noor.worker.orchestration")


class WorkerLoop:
    def __init__(
        self,
        client: OrchestrationClient,
        worker_instance_id: str,
        poll_interval_seconds: int = 5,
        lease_duration_seconds: int = 90,
        heartbeat_interval_seconds: int = 30,
        processor: Processor = noop_processor,
        job_types: list[str] | None = None,
    ) -> None:
        self._client = client
        self._worker_instance_id = worker_instance_id
        self._poll_interval_seconds = poll_interval_seconds
        self._lease_duration_seconds = lease_duration_seconds
        self._heartbeat_interval_seconds = heartbeat_interval_seconds
        self._processor = processor
        self._job_types = job_types
        self._stop_event = threading.Event()

    def stop(self) -> None:
        """Requests graceful shutdown. The current claim cycle (if any) is
        allowed to finish and report its outcome; no new cycle starts."""
        self._stop_event.set()

    def run_forever(self) -> None:
        logger.info("worker orchestration loop starting worker_instance_id=%s", self._worker_instance_id)
        while not self._stop_event.is_set():
            found_job = self.run_claim_cycle()
            if not found_job:
                self._stop_event.wait(self._poll_interval_seconds)
        logger.info("worker orchestration loop stopped worker_instance_id=%s", self._worker_instance_id)

    def run_claim_cycle(self) -> bool:
        """
        Runs one recover -> claim -> process -> complete/fail cycle.
        Returns True iff a job was claimed (so run_forever can skip the
        idle poll delay and immediately try to drain more backlog).
        """
        try:
            self._client.recover_expired_jobs()
        except OrchestrationError:
            logger.exception("recovery pass failed; continuing to attempt a claim")

        try:
            job = self._client.claim_next_job(
                self._worker_instance_id,
                job_types=self._job_types,
                lease_duration_seconds=self._lease_duration_seconds,
            )
        except OrchestrationError:
            logger.exception("claim attempt failed")
            return False

        if job is None:
            return False

        self._process_claimed_job(job)
        return True

    def _process_claimed_job(self, job: ClaimedJob) -> None:
        logger.info(
            "claimed job_id=%s attempt=%s correlation_id=%s", job.job_id, job.attempt_number, job.correlation_id
        )
        try:
            self._client.start_job(
                job.job_id, self._worker_instance_id, job.lease_token, correlation_id=job.correlation_id
            )
        except OrchestrationError:
            logger.exception(
                "failed to start claimed job_id=%s; leaving it for lease-expiry recovery", job.job_id
            )
            return

        stop_heartbeat = threading.Event()
        heartbeat_thread = threading.Thread(
            target=self._heartbeat_until_stopped, args=(job, stop_heartbeat), daemon=True
        )
        heartbeat_thread.start()

        try:
            outcome = self._run_processor_safely(job, lambda: self._safe_heartbeat_once(job))
        finally:
            stop_heartbeat.set()
            heartbeat_thread.join(timeout=self._heartbeat_interval_seconds + 5)

        self._report_outcome(job, outcome)

    def _run_processor_safely(self, job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
        try:
            return self._processor(job, heartbeat)
        except Exception:
            # Never surface the raw exception message — it could contain
            # file paths, stack fragments, or other internals. Only the
            # exception class travels into error_class.
            logger.exception("processor raised an unexpected exception for job_id=%s", job.job_id)
            return ProcessingOutcome(
                kind="retryable_failure",
                error_code="worker_processor_exception",
                error_class="unexpected_exception",
                error_message_safe="the processor raised an unexpected exception",
            )

    def _report_outcome(self, job: ClaimedJob, outcome: ProcessingOutcome) -> None:
        idempotency_key = f"{job.job_id}:{job.attempt_number}"
        try:
            if outcome.kind == "succeeded":
                self._client.complete_job(
                    job.job_id,
                    self._worker_instance_id,
                    job.lease_token,
                    result_summary=outcome.result_summary or {},
                    idempotency_key=idempotency_key,
                    correlation_id=job.correlation_id,
                )
                logger.info("completed job_id=%s", job.job_id)
            else:
                self._client.fail_job(
                    job.job_id,
                    self._worker_instance_id,
                    job.lease_token,
                    error_code=outcome.error_code or "unknown_error",
                    error_class=outcome.error_class or "unknown",
                    error_message_safe=outcome.error_message_safe or "processing failed",
                    retryable=outcome.kind == "retryable_failure",
                    idempotency_key=idempotency_key,
                    correlation_id=job.correlation_id,
                )
                logger.info("reported %s for job_id=%s", outcome.kind, job.job_id)
        except OrchestrationError:
            # The lease may already be gone (reclaimed by
            # recover_expired_document_processing_jobs while we were
            # processing) — expected under crash-recovery races, not an
            # error worth escalating. The job's fate is already decided by
            # whoever holds (or reclaimed) the lease.
            logger.exception(
                "failed to report outcome for job_id=%s (lease likely no longer held)", job.job_id
            )

    def _heartbeat_until_stopped(self, job: ClaimedJob, stop_event: threading.Event) -> None:
        while not stop_event.wait(self._heartbeat_interval_seconds):
            self._safe_heartbeat_once(job)

    def _safe_heartbeat_once(self, job: ClaimedJob) -> None:
        try:
            self._client.heartbeat_job(
                job.job_id,
                self._worker_instance_id,
                job.lease_token,
                lease_duration_seconds=self._lease_duration_seconds,
            )
        except OrchestrationError:
            logger.exception("heartbeat failed for job_id=%s", job.job_id)
