# Sprint Current: Sprint 1.2A — Durable Processing Orchestration

**Status:** Complete and Hosted-Verified. See
`docs/verification/sprint-1.2a-processing-orchestration-verification.md`.
Two real, hosted-only bugs were found and fixed during hosted
verification (neither reproducible against local plain Postgres) — see
"Real bugs found on hosted" below.

Workstreams `S1-A` and `S1-B` closed in prior sessions. This sprint is
workstream `S1-C1` — see `MASTER_BACKLOG.md` for the reconciled
`S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D`/`S1-E` breakdown (`S1-C` was split
into `S1-C1`, this sprint's orchestration control plane, and `S1-C2`,
next sprint's real PDF extraction — see below).

## Mandatory review completed first

- [x] **Streaming file verification** — Sprint 1.1's
      `completeGuidelineUploadAction` fully buffered the uploaded file
      into memory (`.download().arrayBuffer()`) before computing
      size/PDF-signature/SHA-256. Refactored to genuine incremental
      streaming (`apps/web/lib/documents/streamVerification.ts`, a raw
      authenticated `fetch()` against the Storage REST endpoint +
      `ReadableStream` processing) — same trust model, same 50 MB limit,
      provably early-aborts on an oversized stream (5 new unit tests,
      including an explicit pull-count proof of early abort).

## Objectives

- [x] Atomic claim (`FOR UPDATE SKIP LOCKED`), worker identity
      (`WORKER_INSTANCE_ID`, stable per process), hashed lease-token
      ownership with heartbeat-based renewal
      (`supabase/migrations/0007_durable_processing_orchestration.sql`)
- [x] `document_processing_attempts` history: one row per claim, statuses
      `started → succeeded | retryable_failure | terminal_failure |
      lease_expired | cancelled | abandoned`
- [x] Exponential-backoff retry (30s/60s/120s/.../900s cap,
      `max_attempts=3`), a single canonical `compute_retry_delay_seconds()`
      shared by both the failure-reporting and crash-recovery paths
- [x] Lease-expiry crash recovery
      (`recover_expired_document_processing_jobs()`), safe under
      concurrent recovery calls
- [x] User cancellation widened to `queued`/`retry_scheduled`
- [x] Six new orchestration functions never granted to `authenticated` —
      only `service_role` (the Worker) can call them; `cancel_processing_job`
      remains the one `authenticated`-callable, permission-gated exception
- [x] Worker polling loop (Mode A, ADR 0009) running a **controlled no-op
      processor** — claim → start → heartbeat → complete/fail, graceful
      shutdown, `WORKER_PROCESSING_MODE=disabled` by default so no
      existing deployment or test run is affected until opted in
      (`apps/worker/app/{orchestration_client,worker_loop,processing}.py`)
- [x] Application layer + minimal UI: `listDocumentProcessingAttempts`,
      Job Status Card, permission-gated Attempt History — no lease
      tokens/secrets/stack traces/signed URLs, no fabricated progress
      percentages
- [x] Local Postgres 16 verification — 27/27 real orchestration
      assertions, plus the pre-existing 001–005 suites unmodified and
      still 100% green on top of migration 0007
- [x] Genuine dual-OS-process concurrency proof — 80 real jobs, two
      independent `psql` connections, zero double-claims, zero lost jobs
      (`supabase/tests/concurrency/verify_concurrent_claim.sh`)
- [x] Worker verification — 27/27 pytest assertions (9 pre-existing +
      18 new), `python -m compileall` clean
- [x] Hosted Development verification — migration applied, 30/30 real
      concurrent/lease/retry/recovery/cancellation checks with real JWTs
      and real `service_role` calls (including a 20-parallel-request real
      HTTP concurrency race), synthetic data cleaned up and confirmed
      zero-residue
- [x] Vercel Preview redeployed and confirmed healthy, Deployment
      Protection still correctly enforced

## Real bugs found on hosted (neither reproducible locally)

1. **`gen_random_bytes`/`digest` not found under `search_path=public`.**
   Hosted Supabase pre-installs pgcrypto in an `extensions` schema, not
   `public` — invisible locally, where a fresh `postgres:16` container
   installs it directly into `public`. Fixed by adding `extensions` to
   the two affected functions' `search_path` (safe on both environments —
   a nonexistent schema in `search_path` is silently skipped).
2. **`authenticated`/`anon` could call all six Worker-only functions** —
   this migration's core trust-boundary claim was false on hosted until
   this was found and fixed. Hosted Supabase's default privileges grant
   EXECUTE directly to `authenticated`/`anon`/`service_role` at function
   creation time, a grant `revoke ... from public` never touches. Fixed
   with an explicit, guarded revoke from `authenticated` and `anon` on
   every function in this migration. See ADR 0009's addendum and the
   verification record for the full account.

## Explicitly out of scope this task (per the mission)

Real PDF/OCR/chunking/embedding/retrieval/LLM logic — the Worker's
processor is a controlled no-op only, never labeled as real extraction.
Kubernetes, Celery/Temporal, a second parallel job-state system, and
mandatory Supabase Queues integration were all explicitly excluded; Mode A
(direct database polling) was chosen instead (ADR 0009).

## Next sprint

```text
Begin Sprint 1.2B — Deterministic PDF Page and Text Extraction
```

See `MASTER_BACKLOG.md` (S1-C2).
