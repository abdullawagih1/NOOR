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

import logging
import threading
import time
import uuid
from contextlib import asynccontextmanager
from typing import Literal, Optional

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from app.auth import verify_internal_token
from app.orchestration_client import OrchestrationClient
from app.settings import get_settings
from app.worker_loop import WorkerLoop

APP_START_TIME = time.time()
logger = logging.getLogger("noor.worker")

# Eager, not lazy: a missing/weak WORKER_INTERNAL_TOKEN must crash the
# process at startup, not surface as a confusing 401/403 the first time
# something calls /jobs.
settings = get_settings()

_orchestration_client: OrchestrationClient | None = None
_worker_loop: WorkerLoop | None = None
_worker_thread: threading.Thread | None = None


@asynccontextmanager
async def lifespan(_: FastAPI):
    global _orchestration_client, _worker_loop, _worker_thread

    if settings.worker_processing_mode == "noop":
        if settings.supabase_url and settings.supabase_service_role_key:
            _orchestration_client = OrchestrationClient(
                str(settings.supabase_url), settings.supabase_service_role_key.get_secret_value()
            )
            _worker_loop = WorkerLoop(
                client=_orchestration_client,
                worker_instance_id=settings.worker_instance_id,  # type: ignore[arg-type]
                poll_interval_seconds=settings.worker_poll_interval_seconds,
                lease_duration_seconds=settings.worker_lease_duration_seconds,
                heartbeat_interval_seconds=settings.worker_heartbeat_interval_seconds,
            )
            _worker_thread = threading.Thread(target=_worker_loop.run_forever, daemon=True)
            _worker_thread.start()
            logger.info("orchestration polling loop started worker_instance_id=%s", settings.worker_instance_id)
        else:
            logger.warning(
                "WORKER_PROCESSING_MODE=noop but SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY are not set; "
                "the orchestration polling loop will not start"
            )

    yield

    if _worker_loop is not None:
        _worker_loop.stop()
    if _worker_thread is not None:
        _worker_thread.join(timeout=settings.worker_poll_interval_seconds + 10)
    if _orchestration_client is not None:
        _orchestration_client.close()


app = FastAPI(
    title="Noor Worker",
    description="External processing worker for Noor V1 — Clinical Evidence Assistant.",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
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
    Readiness probe. `orchestration_loop_running` reflects real, observable
    thread state (WORKER_PROCESSING_MODE=noop and the background poll
    thread is alive) — never a fabricated dependency check. Model-provider
    dependencies remain unwired (Sprint 1.2B+).
    """
    return {
        "status": "ready",
        "dependencies_checked": [],
        "orchestration_processing_mode": settings.worker_processing_mode,
        "orchestration_loop_running": _worker_thread is not None and _worker_thread.is_alive(),
    }


# ---------------------------------------------------------------------------
# Job intake stub (Sprint 1 will connect this to Supabase Queues; Sprint 0
# exposes and validates the contract so downstream services can integrate
# against a stable schema immediately).
# ---------------------------------------------------------------------------

@app.post("/jobs", response_model=JobAcceptedResponse, dependencies=[Depends(verify_internal_token)])
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
