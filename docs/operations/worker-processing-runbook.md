# Worker Processing Runbook (Sprint 1.2A)

Operational reference for running the durable-orchestration polling loop.
See `docs/operations/worker-deployment.md` for base Worker deployment
(hosting platform, `WORKER_INTERNAL_TOKEN`, Docker) — this document covers
only what's new: `WORKER_PROCESSING_MODE=noop` and the claim/heartbeat/
complete lifecycle.

## Turning the loop on

The loop does **not** start unless both are true:

1. `WORKER_PROCESSING_MODE=noop` (default `disabled` — every existing
   deployment and test run is unaffected until this is set explicitly).
2. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are both set.

If (1) is true but (2) is missing, the process still starts normally (does
not crash) and logs a warning:

```
WORKER_PROCESSING_MODE=noop but SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY are
not set; the orchestration polling loop will not start
```

Check `GET /ready` — `orchestration_processing_mode` and
`orchestration_loop_running` reflect real, observable state (not a
fabricated dependency check).

## Configuration reference

See `apps/worker/.env.example` for the authoritative list. Defaults:

| Variable | Default | Notes |
|---|---|---|
| `WORKER_INSTANCE_ID` | auto-generated (`noor-worker-<env>-<6 hex>`) | Stable for the process's lifetime; pin explicitly for a predictable name across restarts of the same deployment slot |
| `WORKER_POLL_INTERVAL_SECONDS` | 5 | Idle-loop delay between claim attempts when no job was found |
| `WORKER_LEASE_DURATION_SECONDS` | 90 | Must exceed `WORKER_HEARTBEAT_INTERVAL_SECONDS` (enforced by a startup validator, not just documented) |
| `WORKER_HEARTBEAT_INTERVAL_SECONDS` | 30 | Roughly 1/3 of the lease duration |
| `WORKER_MAX_CONCURRENT_JOBS` | 1 | Reserved; not yet enforced — the loop only ever processes one job at a time regardless |
| `WORKER_PROCESSING_MODE` | `disabled` | `disabled` or `noop` only |

## What actually runs (`noop` mode)

Each poll cycle (`app/worker_loop.py::run_claim_cycle`):

1. Calls `recover_expired_document_processing_jobs()` — reclaims any job
   whose lease silently expired (crash recovery). Runs every cycle rather
   than on a separate schedule; a documented simplification at this
   sprint's scale (see `docs/operations/job-recovery-and-dead-letter.md`).
2. Calls `claim_next_document_processing_job()`. No job available → sleep
   `WORKER_POLL_INTERVAL_SECONDS`, try again. A job claimed → continue
   immediately to step 3 without waiting, then loop back to step 1
   immediately after (drains backlog without idle delay between jobs).
3. Calls `start_document_processing_job()`.
4. Starts a background heartbeat thread
   (`WORKER_HEARTBEAT_INTERVAL_SECONDS` cadence) and runs the configured
   processor (`noop_processor` in production — see
   `docs/domain/document-processing-orchestration.md`).
5. Reports the outcome: `complete_document_processing_job()` on success,
   `fail_document_processing_job()` (retryable or terminal) otherwise. A
   processor that raises an unexpected exception is caught and reported as
   a retryable failure with a generic, safe message — never crashes the
   loop (see `docs/security/worker-orchestration-authorization.md`).

## Graceful shutdown

`WorkerLoop.stop()` sets an internal `threading.Event`; `run_forever()`
exits its idle wait promptly (does not wait out a full poll interval) and
does not start a new claim cycle. The FastAPI `lifespan` handler
(`app/main.py`) calls `stop()` on shutdown and joins the background thread
with a timeout before closing the `OrchestrationClient`'s HTTP connection.
**A job already mid-processing when shutdown begins is allowed to finish
and report its outcome** — it is not abandoned mid-flight. If the process
is killed hard (`SIGKILL`, out-of-memory, host failure) rather than given
a chance to run its `lifespan` shutdown, the in-flight job's lease simply
expires on schedule and is reclaimed by the next recovery pass — this is
the same mechanism, not a special case.

## Observing job activity

There is no dedicated metrics/logging pipeline yet (Sprint 1.2A scope).
Operational visibility today is:

* Worker process logs (`logging.getLogger("noor.worker.orchestration")`)
  — claim/start/complete/fail/heartbeat-failure events, one line each.
* Direct database query against `document_processing_jobs`/
  `document_processing_attempts` (or the Web UI's Job Status Card /
  Attempt History — permission-gated, `guideline_processing_jobs.read`).
* `document_intake_events` for a full, timestamped history of every
  claim/start/succeeded/retry_scheduled/dead_lettered/failed/recovered/
  cancelled transition per job.

## Local run (with the orchestration loop active)

```bash
cd apps/worker
cp .env.example .env
# edit .env:
#   WORKER_INTERNAL_TOKEN=<openssl rand -hex 32>
#   SUPABASE_URL=<local or hosted Supabase URL>
#   SUPABASE_SERVICE_ROLE_KEY=<matching service role key>
#   WORKER_PROCESSING_MODE=noop
uvicorn app.main:app --reload --port 8080
```

Note: the local Docker Postgres container used for
`supabase/tests/rls/*.sql` and
`supabase/tests/concurrency/verify_concurrent_claim.sh` does **not** run
PostgREST — pointing a local Worker at it will not work. Point
`SUPABASE_URL` at a real Supabase project (hosted Development, or a local
`supabase start` stack that includes PostgREST) to actually exercise the
Worker's HTTP-level claim loop end-to-end.

## Verification (reproducible)

```bash
python -m compileall apps/worker
cd apps/worker && pytest tests/ -v
```

27 assertions total this sprint: 9 pre-existing (`test_main.py`, `/jobs`
contract, unaffected) + 7 new (`test_orchestration_client.py`, PostgREST
RPC shape/error-handling via `httpx.MockTransport` — no real network) + 11
new (`test_worker_loop.py`, the claim/start/heartbeat/complete/fail cycle
against a fake in-memory `OrchestrationClient` — deterministic
failure-injection processors defined only in the test file, never in
production code; see ADR 0009).
