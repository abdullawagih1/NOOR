# ADR 0009: The database is the durable orchestration source of truth; a queue message, if one ever exists, is only a wake-up

**Status:** Accepted
**Source:** Sprint 1.2A mission — Durable Processing Orchestration

## Decision

```text
document_processing_jobs (+ document_processing_attempts)
  = durable business source of truth for job state, retries, ownership, and history

a queue message (not implemented this sprint)
  = a delivery/wake-up mechanism only, never authoritative
```

No job's state, retry count, attempt history, error history, ownership, or
lease state may ever depend on a queue message existing, arriving exactly
once, or arriving at all. A job must remain fully inspectable and
recoverable even if every queue message that ever referenced it vanished.

## Why database polling, not a queue, this sprint

Supabase Queues/`pgmq` availability wasn't already enabled and stable in
this project, and the mission explicitly said not to make queue
integration mandatory. **Mode A (Worker Polling Loop)** was chosen: the
Worker periodically calls `claim_next_document_processing_job()`
directly. This has a real advantage beyond "less new infrastructure": it
forces the atomic-claim function to be correct entirely on its own
merits — `FOR UPDATE SKIP LOCKED` inside one Postgres transaction — rather
than leaning on a queue's own delivery guarantees to paper over a weaker
claim implementation. A future queue integration only needs to call the
same claim function on a wake-up signal; it changes nothing about
correctness.

## Lease design: hashed tokens, worker-instance ownership

A claimed job gets a random lease token (`gen_random_bytes(32)`, hex
encoded); only its SHA-256 hash (`lease_token_hash`) is ever stored. The
plaintext token exists in exactly two places: briefly inside the
`claim_next_document_processing_job()` function's return value (handed to
the calling Worker process) and in that Worker process's own memory for
the lifetime of the job. It is never logged, never returned by any other
function, and never appears in the UI.

`start`/`heartbeat`/`complete`/`fail` all require the caller to present
the plaintext token; each function hashes it and compares against
`lease_token_hash` (never a plaintext comparison) before honoring the
call. A worker that loses its lease (expired and reclaimed by
`recover_expired_document_processing_jobs()`, or completed/failed by
`fail_document_processing_job` for some other reason) cannot subsequently
complete or heartbeat that job — the hash comparison fails, and the
function raises rather than silently succeeding. This is what makes
"Worker crash → lease expires → job safely reclaimed → stale Worker
completion later fails" hold structurally, not just by convention.

## Trust boundary: Worker functions are not `authenticated`-callable

Unlike every function added in migrations 0005/0006 (deliberately callable
by ordinary signed-in users, gated by an organization permission), the six
new orchestration functions
(`claim_next_document_processing_job`/`start_document_processing_job`/
`heartbeat_document_processing_job`/`complete_document_processing_job`/
`fail_document_processing_job`/`recover_expired_document_processing_jobs`)
are **never granted to `authenticated`** — no ordinary browser session, no
matter what permissions the signed-in user holds, can call them. Only the
Worker's `service_role` credential (server-only, the same narrow,
long-established pattern as `apps/web/lib/supabase/service-role.ts`) can
reach them, because Supabase's `service_role` has default broad access
that these functions simply never revoke. `cancel_document_processing_job`
remains the one exception — a user-facing action, `authenticated`-callable
and `guideline_processing_jobs.cancel`-gated, unchanged from migration
0006 except its allowed source statuses widened to include
`retry_scheduled`.

**This claim was false against real hosted infrastructure until hosted
verification caught it.** `revoke all on function ... from public` alone
was not enough: hosted Supabase projects run `ALTER DEFAULT PRIVILEGES
... GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role` at
the database level, so every function created in `public` — including
these six — is EXECUTE-granted **directly** to `authenticated`/`anon` at
creation time, a grant revoking from the `PUBLIC` pseudo-role never
touches. A real authenticated-JWT call to
`claim_next_document_processing_job` returned `200` before the fix. Local
plain Postgres has no such default-privilege rule (and no `anon` role at
all), so this was invisible in every local run. Fixed with an explicit,
guarded `revoke execute ... from authenticated` / `from anon` for every
function in this migration — see the trust-boundary re-verification in
`docs/verification/sprint-1.2a-processing-orchestration-verification.md`.
**Lesson for future migrations**: `revoke all on function X from public`
is necessary but not sufficient on hosted Supabase for a function meant
to be unreachable by `authenticated`/`anon` — revoke from those named
roles explicitly too.

## Output-column shadowing: a bug found twice already, designed away this time

Both Sprint 1.1 bugs came from `RETURNS TABLE` functions whose output
column names collided with real table columns referenced elsewhere in the
same function body (`status`, `source_document_id`). Rather than relying on
remembering to table-qualify every reference, every new `RETURNS TABLE`
function in migration 0007 prefixes every output column with `out_`
(`out_job_id`, `out_status`, `out_lease_expires_at`, ...) — a name that can
never collide with a real table column, eliminating the bug class rather
than defending against it case by case.

## What stays a controlled no-op this sprint

The Worker's processing handler for a claimed job does not parse, OCR,
chunk, or embed anything — it runs a fixed no-op that reports
`{"processor": "orchestration-noop", "pipeline_version": "orchestration-v1",
"status": "completed_without_extraction"}` as its result. Test-only
processor modes (`retryable_failure`, `terminal_failure`,
`sleep_until_lease_expiry`) exist solely as direct Python function
parameters injected by `pytest` — never a runtime-configurable value, so
there is no production code path that could accidentally select one.
