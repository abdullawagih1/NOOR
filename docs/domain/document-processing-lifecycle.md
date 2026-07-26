# Document Processing Job — State Machine (Sprint 1.2A)

Source: `supabase/migrations/0007_durable_processing_orchestration.sql`.
Supersedes the "this sprint only ever produces `queued`" note in
`docs/domain/document-intake-lifecycle.md` — that note described Sprint
1.1; this document describes what Sprint 1.2A actually implements.

## State machine

```
queued ──claim──▶ claimed ──start──▶ processing ──complete──▶ succeeded
  ▲                                       │
  │                                       ├──fail(retryable, attempts left)──▶ retry_scheduled ──due──▶ (claim again)
  │                                       │
  │                                       ├──fail(retryable, attempts exhausted)──▶ dead_lettered
  │                                       │
  │                                       └──fail(terminal)──▶ failed
  │
  └──cancel (from queued or retry_scheduled)──▶ cancelled

claimed/processing ──lease expires, no heartbeat──▶ retry_scheduled (via recover_expired_document_processing_jobs)
```

`retry_scheduled → claimed` is the same `claim_next_document_processing_job()`
call as `queued → claimed` — the claim function's `WHERE` clause matches
`status = 'queued' OR (status = 'retry_scheduled' AND next_attempt_at <=
now())`, so a due retry is indistinguishable from a fresh job at claim
time. `attempt_count` increments on every claim regardless of which of
the two source statuses it came from.

## Forbidden transitions (structurally rejected, not just undocumented)

* `succeeded`/`failed`/`cancelled`/`dead_lettered` → anything. All four are
  terminal; every write function checks the job's current status before
  acting and raises rather than silently no-op'ing on an unexpected one
  (except the specific idempotent-replay cases below).
* `queued`/`retry_scheduled` → `succeeded`/`failed` directly, bypassing
  `claim`/`start`. Verified in TEST 12c
  (`supabase/tests/rls/006_processing_orchestration.sql`): calling
  `complete_document_processing_job()` on a still-`queued` job is
  rejected.
* `succeeded` → `processing` (a second `start` after completion) or a
  further heartbeat. Verified in TEST 12/12b.
* `dead_lettered` → `cancelled`. Verified in TEST 11d — cancellation is
  only for jobs that haven't started real work yet (`queued`/
  `retry_scheduled`); a dead-lettered job already exhausted its retries
  and needs an explicit reactivation decision, not a cancellation.
* `claimed`/`processing` by a lease token or worker name that doesn't
  match the current lease owner → any transition. Verified in TEST 3
  (wrong-worker and wrong-token heartbeats denied), TEST 4 (start denied
  for a non-owner), TEST 6 (completion denied for a non-owner).

## Idempotent replays (the two intentional non-errors)

* `start_document_processing_job()` called twice with the same worker and
  a still-valid lease on an already-`processing` job returns the existing
  row rather than raising — a Worker that retries its own `start` call
  after a transient network blip must not be punished for it.
* `complete_document_processing_job()` / `fail_document_processing_job()`
  called again with the same `idempotency_key` against a job already in
  the resulting state return the existing outcome. See
  `docs/domain/document-processing-orchestration.md`'s Idempotency
  section.

## Attempt history (`document_processing_attempts`)

One row per claim, `unique (processing_job_id, attempt_number)`. Statuses:
`started → succeeded | retryable_failure | terminal_failure | lease_expired
| cancelled | abandoned`. Unlike every other new table this sprint,
`document_processing_attempts` is **not** append-only-by-trigger — a
`started` row is legitimately updated in place (its own `status`,
`completed_at`, `error_*`, `lease_*` columns) as that attempt progresses,
by design (ADR 0009 notes this explicitly as the one exception to the
append-only convention otherwise used for
`audit_events`/`guideline_lifecycle_events`/`document_intake_events`).

## Permission matrix (unchanged from Sprint 1.1, one addition)

| Permission | Grants ability to | Roles |
|---|---|---|
| `guideline_processing_jobs.read` | Read job status and attempt history | `knowledge_manager`, `organization_admin`, `clinical_reviewer`, `quality_manager`, `safety_officer`, `auditor` |
| `guideline_processing_jobs.cancel` | Cancel a `queued` or `retry_scheduled` job | `quality_manager` |

No new permission was introduced for attempt-history reads — folded into
the existing `.read` permission (both tables share the identical RLS
predicate) — and no `.retry` permission exists, since manual retry of a
dead-lettered job is explicitly deferred (see Known Limitations in
`docs/domain/document-processing-orchestration.md`).

## Domain events vs. audit events

Eight domain event types are recorded to `document_intake_events`:
`document_processing_job.{claimed, started, succeeded, retry_scheduled,
dead_lettered, failed, recovered, cancelled}` — one row per claim/start/
complete/fail-outcome/recovery/cancellation. **Not one row per heartbeat
call** — `heartbeat_document_processing_job()` writes no event at all,
deliberately, since a routine lease renewal is operational noise, not a
fact worth an audit trail. Only `cancel_processing_job` additionally
writes to `audit_events`, matching the mission's instruction to audit
security-sensitive actions (cancellation, a future manual retry, a future
dead-letter override) and not routine job-lifecycle events.
