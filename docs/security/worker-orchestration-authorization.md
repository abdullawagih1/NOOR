# Worker Orchestration — Authorization Model (Sprint 1.2A)

Source: `supabase/migrations/0007_durable_processing_orchestration.sql`,
`apps/worker/app/{orchestration_client,worker_loop,settings}.py`. See ADR
0009 for the full architecture decision.

## A different trust boundary than every prior migration

Migrations 0005/0006's functions are `authenticated`-callable, gated by an
organization permission the caller must hold. This migration's six new
functions (`claim_next_document_processing_job`,
`start_document_processing_job`, `heartbeat_document_processing_job`,
`complete_document_processing_job`, `fail_document_processing_job`,
`recover_expired_document_processing_jobs`) are **never granted to
`authenticated` at all** — no signed-in user's session, regardless of
permissions their role holds, can call them. Only Supabase's
`service_role` — which has default broad access these functions simply
never revoke — can reach them, and only the Worker holds that credential
(`SUPABASE_SERVICE_ROLE_KEY`, server-only, same narrow pattern as
`apps/web/lib/supabase/service-role.ts`). This is a stronger boundary than
"permission-gated": there is no permission a browser session could ever be
granted that would let it call these six functions.

`cancel_processing_job` is the one function unchanged in this respect —
still `authenticated`-callable, still gated by
`guideline_processing_jobs.cancel`, its allowed source statuses widened to
include `retry_scheduled`.

## Defense in depth for the six Worker-only functions

1. **No `authenticated` grant** — see above; this is the primary control,
   not a backstop.
2. **`revoke all ... from public`** on every one of the six, explicit in
   the migration, not relying on Postgres defaults.
3. **Lease-token hash verification** (`assert_lease_owner`) — even holding
   `service_role` (i.e., being the Worker process itself), a caller cannot
   act on a job it did not itself claim, or whose lease it has lost to
   recovery, without presenting the correct plaintext token. This matters
   because multiple Worker instances all share the same `service_role`
   credential — the lease token, not the database role, is what
   distinguishes "the worker that legitimately owns this job" from "some
   other worker process."
4. **Composite foreign keys** tie every new column back to
   `(organization_id, id)` pairs exactly as migrations 0005/0006
   established — a cross-tenant reference remains structurally impossible
   to insert.

## What the Worker can never do, structurally

* Read or write any table gated by a permission it doesn't need — it only
  ever calls the six RPC functions plus, in a future sprint, direct reads
  needed for real extraction. It has no reason to and no code path
  attempts to bypass RLS on tables outside this scope.
* Learn a lease token it didn't itself just receive — tokens are generated
  server-side inside `claim_next_document_processing_job()` and returned
  once; no function returns a previously-issued token, and the column
  storing it (`lease_token_hash`) is a hash, unrecoverable even by a
  direct table read.
* Act on a job across organizations differently than within one — the
  claim function has no organization filter (Workers process cross-tenant
  by design, since there is one shared Worker fleet), but every write is
  still scoped by the job's own `organization_id`, and RLS still applies
  identically regardless of which organization a job belongs to.

## Error messages never leak internals

`fail_document_processing_job()`'s `p_error_message_safe` parameter name
is not a suggestion — `apps/worker/app/worker_loop.py::_run_processor_safely`
catches any unexpected exception from a processor and reports only
`"the processor raised an unexpected exception"` plus the exception
*class* name as `error_class`, never `str(exception)` (which could contain
file paths, partial content, or other internals). Verified in
`apps/worker/tests/test_worker_loop.py::test_processor_exception_is_caught_and_reported_as_retryable_with_a_safe_message`
— asserts the literal exception message text (`"boom — this text must
never reach fail_job's error_message_safe"`) does not appear anywhere in
what gets reported.

`OrchestrationClient`'s error handling
(`apps/worker/app/orchestration_client.py::_rpc`) passes through only
PostgREST's structured `message` field (itself already a
`raise exception '...'` string the SQL functions authored deliberately) —
never raw response bodies, headers, or the lease token that was part of
the outgoing request. Verified in
`test_error_response_raises_orchestration_error_with_safe_message`.

## Lease tokens never appear in the UI

`apps/web/lib/documents/queries.ts` selects an explicit column list (not
`*`) for `document_processing_jobs`/`document_processing_attempts`
specifically because those tables carry `lease_token_hash`,
`lease_acquired_at`, `lease_expires_at`, `claimed_by`, `heartbeat_at` —
internal orchestration state with no reason to ever reach a Client
Component, even as an unused prop. Selecting only the typed, UI-relevant
columns means that data cannot leak by accident (see
`docs/database/document-processing-orchestration-schema.md`).

## Remaining risks

* `service_role` is shared by every Worker instance — there is no
  per-instance database credential. Lease-token verification (above) is
  what prevents one instance from interfering with another's job, not the
  database role itself.
* No rate limiting on the six RPC functions — acceptable while the only
  caller is the Worker's own controlled poll loop; would need revisiting
  if `service_role` credentials were ever exposed more broadly.
* `WORKER_INSTANCE_ID`, if pinned explicitly rather than auto-generated,
  is operator-supplied and not validated for uniqueness across a fleet —
  two Worker processes sharing the same pinned instance ID could each
  believe they own the other's lease. Document this operational
  requirement; not otherwise enforced by this sprint's code.
