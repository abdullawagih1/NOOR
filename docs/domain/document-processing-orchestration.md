# Document Processing Orchestration (Sprint 1.2A)

Source: `supabase/migrations/0007_durable_processing_orchestration.sql`,
`apps/worker/app/{orchestration_client,worker_loop,processing}.py`. See
ADR 0009 for the architecture decision this document assumes.

## What this sprint proves

That a `document_processing_jobs` row (created by Sprint 1.1's intake flow)
can be **claimed exactly once, executed, retried with backoff, recovered
after a crash, cancelled, and completed exactly once** — all without any
real PDF/OCR/chunking/embedding logic existing yet. The Worker's processor
is a controlled no-op (`apps/worker/app/processing.py::noop_processor`)
that reports `{"processor": "orchestration-noop", "pipeline_version":
"orchestration-v1", "status": "completed_without_extraction"}` and touches
no document content. Real extraction is Sprint 1.2B.

## The six orchestration functions

| Function | Caller | Purpose |
|---|---|---|
| `claim_next_document_processing_job` | Worker only | Atomically claims one eligible job (`FOR UPDATE SKIP LOCKED`), issues a lease token |
| `start_document_processing_job` | Worker only | `claimed → processing`; idempotent replay for the same worker's own lease |
| `heartbeat_document_processing_job` | Worker only | Extends `lease_expires_at`; requires the caller's token to hash-match |
| `complete_document_processing_job` | Worker only | `processing → succeeded`; idempotent on replay (same `idempotency_key`) |
| `fail_document_processing_job` | Worker only | Retryable → `retry_scheduled` (backoff-scheduled) or exhausted → `dead_lettered`; terminal → `failed` |
| `recover_expired_document_processing_jobs` | Worker only (called from its own poll loop) | Reclaims jobs whose lease expired without a heartbeat; schedules a retry |

`cancel_processing_job` (from migration 0006) is the one user-facing
exception — `authenticated`-callable, gated by
`guideline_processing_jobs.cancel`, its allowed source statuses widened
this sprint to include `retry_scheduled` alongside `queued`.

## Worker identity and leases

Each Worker process generates a stable `worker_instance_id` once at
startup (`noor-worker-<env>-<6 hex chars>`, e.g. `noor-worker-dev-7f3a9b`,
or pinned via `WORKER_INSTANCE_ID`) — fixed for the process's lifetime via
`Settings`' `lru_cache`. A claim issues a random 32-byte lease token; only
its SHA-256 hash is ever persisted (`lease_token_hash`). Every subsequent
call that needs to prove lease ownership (`start`/`heartbeat`/
`complete`/`fail`) re-hashes the caller-supplied token and compares —
never a plaintext comparison, never a second place the plaintext is
stored. Default lease duration 90s, default heartbeat interval 30s (both
configurable; `WORKER_HEARTBEAT_INTERVAL_SECONDS` must stay below
`WORKER_LEASE_DURATION_SECONDS` — enforced by a `Settings` validator, not
just documentation).

## Retry policy

`compute_retry_delay_seconds(attempt_count)` — one canonical SQL function,
called from both `fail_document_processing_job()` and
`recover_expired_document_processing_jobs()` so retry timing can never
diverge between the two call sites:

```
30s, 60s, 120s, 240s, ... capped at 900s (15 minutes)
```

`max_attempts` defaults to 3 (per job). Exhausting attempts on a retryable
failure moves the job to `dead_lettered` rather than scheduling a retry
that would never be claimed again productively — verified in
`supabase/tests/rls/006_processing_orchestration.sql` TEST 8 (three
retryable failures in a row exhaust `max_attempts=3` and dead-letter the
job).

## Crash recovery

`recover_expired_document_processing_jobs()` reclaims any `claimed`/
`processing` job whose `lease_expires_at` has passed — the Worker's own
crash, a network partition, or a killed process all look identical from
the database's point of view: a lease that stopped being renewed. The
function is safe under concurrent invocation (`FOR UPDATE SKIP LOCKED`,
verified in TEST 10: a second recovery pass immediately after the first
finds nothing left to recover). The Worker's poll loop calls it once per
cycle, before attempting a claim — no separate scheduler process exists;
this is a deliberate simplification for this sprint's scale (see
`docs/operations/job-recovery-and-dead-letter.md`).

## Queue strategy: none yet, and none required for correctness

See ADR 0009. Mode A (Worker polling loop, `apps/worker/app/worker_loop.py`)
was chosen over introducing a queue this sprint — the atomic claim
function's correctness does not depend on it, proven under real
dual-process concurrency (`supabase/tests/concurrency/verify_concurrent_claim.sh`,
80 real jobs, two independent OS processes, zero double-claims). A future
queue integration would only need to call the same claim function on a
wake-up signal.

## Idempotency

Both `complete_document_processing_job()` and `fail_document_processing_job()`
accept an `idempotency_key` (the Worker sends `"<job_id>:<attempt_number>"`).
Replaying either call against a job already in the resulting terminal-ish
state returns the existing outcome rather than raising or double-recording
— verified in TEST 6c (replayed completion returns the same
`completed_at`, no duplicate attempt row, no duplicate domain event) and
TEST 7b (replayed retryable failure on an already-`retry_scheduled` job).

## Known limitations (honest, not deferred silently)

* The processing handler remains a controlled no-op — no real PDF
  extraction exists yet (Sprint 1.2B).
* Recovery runs on every poll tick rather than a dedicated scheduled
  interval — acceptable at this sprint's scale; worth decoupling if the
  job volume or Worker-fleet size grows.
* `WORKER_MAX_CONCURRENT_JOBS` is declared but not yet enforced — the
  current loop always processes one job at a time regardless of its value.
* Manual retry of a `dead_lettered` job is not implemented — dead-lettered
  jobs are visible (via `listDocumentProcessingJobs`/UI) but reactivating
  one requires a direct database action today.
* Retry timing (30s/60s/120s.../900s cap, `max_attempts=3`) is a baseline
  policy, not production-tuned against real extraction failure modes.
