"""
The controlled no-op processor (Sprint 1.2A scope boundary — see ADR 0009
and the mission's explicit out-of-scope list). This module intentionally
contains no PDF parsing, OCR, chunking, or embedding logic: it proves the
claim -> start -> heartbeat -> complete/fail lifecycle end-to-end without
touching real document content. Real extraction is Sprint 1.2B.

`ProcessingOutcome` is the only contract a processor function must satisfy:
`(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome`.
Test-only outcome-injecting processors (retryable failure, terminal
failure, sleep-until-lease-expiry) live in the test suite only — never
here, and never selectable via `WORKER_PROCESSING_MODE` — so there is no
production code path that could accidentally choose one (ADR 0009).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Literal

from app.orchestration_client import ClaimedJob

ProcessingOutcomeKind = Literal["succeeded", "retryable_failure", "terminal_failure"]


@dataclass(frozen=True)
class ProcessingOutcome:
    kind: ProcessingOutcomeKind
    result_summary: dict[str, Any] | None = None
    error_code: str | None = None
    error_class: str | None = None
    error_message_safe: str | None = None


Processor = Callable[[ClaimedJob, Callable[[], None]], ProcessingOutcome]


def noop_processor(job: ClaimedJob, heartbeat: Callable[[], None]) -> ProcessingOutcome:
    """
    Reports success without extracting anything. `heartbeat` is accepted
    (and unused here) purely so the processor contract matches what a real,
    long-running Sprint 1.2B processor will need to call periodically.
    """
    return ProcessingOutcome(
        kind="succeeded",
        result_summary={
            "processor": "orchestration-noop",
            "pipeline_version": "orchestration-v1",
            "status": "completed_without_extraction",
        },
    )
