"""
Noor V1 — External Python Worker
Council: AI/RAG Agent + DevOps/SRE Agent

Owns long-running, resource-intensive work that must never execute inside a
Vercel request: PDF parsing, OCR, chunking, embedding batches, reranking,
evaluation runs (Execution Plan §7.3 / Architecture Report §15).

Sprint 0 scope: service scaffold, health/readiness endpoints, and the typed
job contract used by every queue (document_ingestion, document_parsing,
chunk_generation, embedding_generation, ...). Parsing/chunking/embedding
logic itself is Sprint 1+ scope (see MASTER_BACKLOG.md, E-07/E-08/E-10).
"""
from __future__ import annotations

import time
import uuid
from typing import Literal, Optional

from fastapi import FastAPI
from pydantic import BaseModel, Field

APP_START_TIME = time.time()

app = FastAPI(
    title="Noor Worker",
    description="External processing worker for Noor V1 — Clinical Evidence Assistant.",
    version="0.1.0",
)


# ---------------------------------------------------------------------------
# Job contract (Execution Plan §15 / Master Prompt §14)
# ---------------------------------------------------------------------------

JobOperation = Literal[
    "document_ingestion",
    "document_parsing",
    "document_ocr",
    "chunk_generation",
    "embedding_generation",
    "index_update",
    "evaluation_run",
    "notification_delivery",
]


class JobMessage(BaseModel):
    """
    The only payload shape accepted from Supabase Queues. Deliberately
    carries identifiers and control metadata only — never full document or
    patient content (Master Prompt §14: "Do not place full document contents
    in queue messages.").
    """

    job_id: uuid.UUID
    organization_id: uuid.UUID
    document_id: Optional[uuid.UUID] = None
    operation: JobOperation
    requested_by: uuid.UUID
    correlation_id: uuid.UUID
    idempotency_key: str = Field(min_length=1, max_length=200)
    attempt: int = Field(default=1, ge=1)


class JobAcceptedResponse(BaseModel):
    job_id: uuid.UUID
    correlation_id: uuid.UUID
    status: Literal["accepted"]


# ---------------------------------------------------------------------------
# Health / readiness (DevOps/SRE Agent requirement — Architecture Report §15.3)
# ---------------------------------------------------------------------------

@app.get("/health")
def health() -> dict:
    """Liveness probe: process is up."""
    return {"status": "ok", "uptime_seconds": round(time.time() - APP_START_TIME, 2)}


@app.get("/ready")
def ready() -> dict:
    """
    Readiness probe. Sprint 0: no external dependency (Supabase, model
    providers) is wired yet, so readiness mirrors liveness and is labeled
    accordingly rather than fabricating a dependency check that doesn't exist.
    """
    return {"status": "ready", "dependencies_checked": []}


# ---------------------------------------------------------------------------
# Job intake stub (Sprint 1 will connect this to Supabase Queues; Sprint 0
# exposes and validates the contract so downstream services can integrate
# against a stable schema immediately).
# ---------------------------------------------------------------------------

@app.post("/jobs", response_model=JobAcceptedResponse)
def accept_job(job: JobMessage) -> JobAcceptedResponse:
    """
    Validates an incoming job message against the approved contract and
    acknowledges it. Sprint 0 does not execute any processing — this
    endpoint exists to prove the contract, request validation, and
    correlation-ID propagation work end-to-end before real parsing logic
    (E-07) is implemented.
    """
    return JobAcceptedResponse(
        job_id=job.job_id,
        correlation_id=job.correlation_id,
        status="accepted",
    )
