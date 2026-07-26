# Job Recovery and Dead-Letter Handling (Sprint 1.2A)

Operational reference for what happens when a Worker goes silent
mid-job, and what happens when a job exhausts its retries.

## How a "crashed" job is detected

There is no heartbeat-missed alert or separate watchdog process. Recovery
is purely lease-expiry-based: `recover_expired_document_processing_jobs()`
finds every job in `claimed`/`processing` whose `lease_expires_at` has
already passed, and reclaims it — a Worker crash, an unhandled exception
that skipped cleanup, a killed container, a network partition between the
Worker and Supabase, and a genuinely still-running-but-slow Worker whose
heartbeat thread died all look identical from the database's point of
view: a lease that stopped being renewed. This is intentional — trying to
distinguish "crashed" from "still working but stuck" from inside the
database is not reliable, so the system doesn't try; it just reclaims and
lets the job run again.

## What recovery actually does

For each expired-lease job:

1. Records the current (now-abandoned) `document_processing_attempts` row
   as `status = 'lease_expired'`.
2. Clears the job's lease fields (`lease_token_hash`, `claimed_by`,
   `lease_acquired_at`, `lease_expires_at`) so a stale Worker holding the
   old plaintext token cannot subsequently act on it — `assert_lease_owner`
   will reject it (hash comparison against a now-`null` `lease_token_hash`
   never matches). Verified in
   `supabase/tests/rls/006_processing_orchestration.sql` TEST 9c.
3. If attempts remain (`attempt_count < max_attempts`): schedules a retry
   (`status = 'retry_scheduled'`, `next_attempt_at` via the same
   `compute_retry_delay_seconds()` used for reported failures).
4. If attempts are exhausted: dead-letters the job directly (same
   exhaustion path as a reported failure — recovery doesn't get a free
   extra attempt beyond `max_attempts`).
5. Records a `document_processing_job.recovered` domain event.

Safe under concurrent recovery calls (two Worker instances both happening
to run a recovery pass at the same moment): `FOR UPDATE SKIP LOCKED`
inside the function means the second call simply finds nothing left to
reclaim. Verified in TEST 10 — a second recovery pass immediately after
the first returns zero rows.

## Who triggers recovery

No separate scheduler exists this sprint. Each Worker's own poll loop
calls `recover_expired_document_processing_jobs()` once per cycle, before
attempting a claim (`app/worker_loop.py::run_claim_cycle`). This means
recovery happens roughly every `WORKER_POLL_INTERVAL_SECONDS` per active
Worker instance — acceptable at this sprint's job volume, and safe even
with multiple Workers all doing it simultaneously (see above). **Known
limitation**: if every Worker instance is down, no recovery runs either —
a job whose Worker died still waits until some Worker comes back online
and polls. Worth decoupling into a dedicated scheduled job (e.g. a
`pg_cron` entry or an external scheduler) if Worker uptime patterns ever
make this matter; not needed for this sprint's scope.

## Dead-letter: visible, not auto-reactivated

A job reaches `dead_lettered` when a retryable failure (reported or
recovery-detected) occurs with no attempts left. This is a **terminal**
status — no code path automatically reactivates it. Rationale (mission
§ dead-letter management): exhausting `max_attempts=3` on a *real*
extraction pipeline (Sprint 1.2B+) likely means the document itself has a
problem (corrupt PDF, unsupported encoding, ...) that blind retrying won't
fix — a human decision is more appropriate than an automatic loop.

**Manual retry of a dead-lettered job is not implemented this sprint.**
Dead-lettered jobs are visible today (via `listDocumentProcessingJobs()`
and the guideline detail page's Job Status Card, gated by
`guideline_processing_jobs.read`) but reactivating one currently requires
a direct database action:

```sql
update document_processing_jobs
set status = 'queued', dead_lettered_at = null, attempt_count = 0
where id = '<job-id>' and status = 'dead_lettered';
```

This is intentionally not exposed through the application yet — the
mission explicitly allowed omitting a manual-retry feature this sprint in
favor of documenting it as deferred, rather than building an
undertested reactivation path. A `retryDeadLetteredJob()` application
function and a `guideline_processing_jobs.retry` permission are the
natural next step if this becomes a recurring operational need.

## Cancellation vs. dead-letter

Cancellation (`cancel_processing_job`) is user-initiated and only reaches
`queued`/`retry_scheduled` jobs — a job that hasn't consumed its retries
yet. Dead-lettering is system-initiated and only reaches a job that
*has*. A `dead_lettered` job cannot be cancelled (there is nothing left to
cancel — it already stopped on its own); verified in TEST 11d.
