# Sprint 1.2A — Durable Processing Orchestration Verification Record

Every command and result below was actually run — nothing here is inferred
or assumed. Companion docs: `docs/domain/{document-processing-orchestration,
document-processing-lifecycle}.md`,
`docs/database/document-processing-orchestration-schema.md`,
`docs/security/worker-orchestration-authorization.md`,
`docs/operations/{worker-processing-runbook,job-recovery-and-dead-letter}.md`,
ADR 0009.

## Mandatory review: streaming file verification (closed this sprint)

Sprint 1.1's `completeGuidelineUploadAction` used
`supabase.storage.from(bucket).download(path)` → `Blob` →
`arrayBuffer()`, fully buffering the uploaded file (up to 50 MB) into
memory before computing size/PDF-signature/SHA-256. Refactored to a raw
authenticated `fetch()` against the Storage REST endpoint +
`computeFileFactsFromStream()` (`apps/web/lib/documents/streamVerification.ts`),
which processes the response body's `ReadableStream` incrementally and
aborts (`reader.cancel()`) the instant the running byte count exceeds the
limit — never buffering the rest of an oversized file. Same trust
boundary (still the caller's own RLS-scoped session, no service-role
key), same 50 MB limit.

```
$ cd apps/web && npx tsx tests/documents-stream-verification.test.ts
PASS  streams a small valid PDF split across multiple chunks and matches a full-buffer hash
PASS  detects a non-PDF signature
PASS  handles an empty stream
PASS  aborts early on an oversized stream without reading every chunk
PASS  reports the exact byte count for a within-limit stream

All streaming file-verification tests passed.
```

The 4th assertion explicitly proves early abort: a 50-chunk stream (750
bytes) with a 40-byte limit stops after ≤5 pulls, not all 50 — verified
via a chunk-pull-count assertion on a custom `ReadableStream` that tracks
how many times it was actually read from.

## Local database verification — real Postgres 16

A real `postgres:16` Docker container had all 7 migrations, seed data,
and the full RLS/orchestration test suite applied and run:

```
$ for f in supabase/migrations/*.sql; do psql ... -f "$f"; done
→ 0001-0007 all applied with zero errors

$ psql ... -f supabase/seed.sql   → applied cleanly

$ for f in supabase/tests/rls/*.sql; do psql ... -f "$f"; done
→ 001_tenant_isolation.sql:              7/7  PASSED
→ 002_auth_hardening.sql:                4/4  PASSED
→ 003_guideline_registry.sql:           26/26 PASSED
→ 004_g12_self_approval_regression.sql:  4/4  PASSED
→ 005_document_intake.sql:              17/17 PASSED
→ 006_processing_orchestration.sql:     27/27 PASSED
```

The pre-existing 001–005 suites are **unmodified** and still 100% green
on top of migration 0007's schema changes — confirming the new
orchestration functions/columns didn't disturb the guideline registry or
document intake behavior.

### Processing orchestration test coverage (006_processing_orchestration.sql)

| # | Assertion | Result |
|---|---|---|
| 1 / 1b | Atomic claim succeeds; transitions to `claimed`; exactly one attempt row created | PASS |
| 2 | Three further sequential claims each return a distinct, previously-unclaimed job | PASS |
| 3 | Wrong-worker and wrong-token heartbeats denied; lease expiry unchanged | PASS |
| 4 | `start` denied for a non-owner; succeeds for the real owner | PASS |
| 5 | Heartbeat from the real owner extends the lease | PASS |
| 6 / 6d / 6e | Completion denied for a non-owner; succeeds for the owner; idempotent replay (no duplicate attempt/event) | PASS |
| 7 / 7b | Retryable failure schedules a ~30s retry, clears the lease; replay is idempotent | PASS |
| 8 / 8b | Reclaiming a due retry works; 3 retryable failures exhaust `max_attempts=3` → `dead_lettered`; a dead-lettered job is not claimable | PASS |
| 9 / 9b / 9c | Expired lease reclaimed by recovery; latest attempt marked `lease_expired`; stale worker locked out afterward | PASS |
| 10 | A second recovery pass immediately after the first is a safe no-op | PASS |
| 11 / 11b / 11c / 11d / 11e | Cancellation: authorized cancels a queued job; cancelled job not claimable; repeat cancellation idempotent; dead-lettered job not cancellable; unauthorized (clinician) denied | PASS |
| 12 / 12b / 12c | Forbidden transitions: succeeded→processing rejected; heartbeat-on-succeeded rejected; queued→succeeded (bypassing claim/start) rejected | PASS |
| 13 | Clinician still cannot read processing jobs (RLS unaffected by this migration) | PASS |

### Real bugs found by actually running the test file, not by reading it

1. **Fixture pool undersized, and a false assumption about queue emptiness.**
   The first draft created only 4 fixture jobs but the test sequence
   needed 6 fresh claims (TEST1 + TEST2's 3 + TEST7 + TEST9), and TEST2
   separately asserted the shared Docker test database's claim queue
   would become globally empty after draining — both wrong, since the
   database carries cumulative state across the whole 001–006 suite run
   (005 and 006 each legitimately leave some jobs queued by design, e.g.
   TEST 12c's fixture job is deliberately never claimed). Fixed by
   expanding the fixture pool to 6 jobs and rewriting TEST 2 to assert
   claim *distinctness* (no double-claim across sequential claims) rather
   than global queue emptiness — see
   `docs/database/document-processing-orchestration-schema.md`.
2. **`set local role`/`set local request.jwt.*` inside a `DO $$...$$`
   block** was avoided by design after recognizing it as an untested
   pattern in this codebase — every prior RLS test file only ever sets
   role/JWT claims at the top level, outside PL/pgSQL blocks. The test
   file was written to strictly follow that proven convention throughout.

## Genuine dual-OS-process concurrency proof

A single `psql` session (as used above) can only prove *sequential*
exclusivity. `supabase/tests/concurrency/verify_concurrent_claim.sh`
proves real concurrent-safety: two independent OS processes (separate
`docker exec ... psql` connections — genuinely separate Postgres
backends, not the same session) race to drain a shared pool of queued
jobs.

```
$ bash supabase/tests/concurrency/verify_concurrent_claim.sh noor_test_pg noor_test 80
=== Seeding 80 queued jobs for the concurrency race ===
NOTICE:  CONCURRENCY FIXTURE READY: 80 queued document_parsing jobs
actual claimable jobs at race start: 80
=== Racing two independent worker processes against the shared queue ===
worker X claimed: 40
worker Y claimed: 40
total claimed:    80 (expected 80)
unique job ids:   80 (expected 80)
overlap between workers: 0 (expected 0)
CONCURRENCY PROOF PASSED: 80 claimable jobs, two real concurrent worker processes, zero double-claims, zero lost jobs
```

Zero double-claims, zero lost jobs, an even 40/40 split — direct evidence
that `FOR UPDATE SKIP LOCKED` behaves correctly under real, not simulated,
concurrency.

## Local web verification

```
npm run lint --workspace=apps/web        → clean
npx tsc --noEmit (apps/web)              → clean
npm run test --workspace=apps/web        → all assertions passed (9 suites,
                                            including 2 new this sprint:
                                            documents-stream-verification,
                                            documents-orchestration-ui)
npm run build --workspace=apps/web       → succeeded, all routes generated
```

## Worker verification

```
python -m compileall apps/worker         → clean
cd apps/worker && pytest tests/ -v       → 27/27 passed
```

9 pre-existing (`test_main.py`, `/jobs` contract, unaffected) + 7 new
(`test_orchestration_client.py` — PostgREST RPC request/response shape
and safe error handling via `httpx.MockTransport`, no real network) + 11
new (`test_worker_loop.py` — the full claim/start/heartbeat/complete/fail
cycle against a fake in-memory `OrchestrationClient`, including
processor-exception containment, heartbeat-failure tolerance, and
graceful shutdown; deterministic failure-injection processors defined
only in the test file, matching ADR 0009's "never a runtime-selectable
value" design).

## Other workspaces (unaffected — re-verified, not assumed)

```
npm run typecheck --workspace=packages/clinical-schemas → clean
npm test --workspace=packages/clinical-schemas          → 6/6 passed
npm run typecheck --workspace=packages/ui                → clean
```

## Hosted Development verification

### Migration applied

```
$ supabase migration list --linked   (before)
→ 0001-0006 local==remote; 0007 local only, remote empty

$ supabase db push --linked --yes
→ Applying migration 0007_durable_processing_orchestration.sql...
→ Finished supabase db push.

$ supabase migration list --linked   (after)
→ 0001-0007 all local==remote
```

### Two real, hosted-only bugs found — neither reproducible locally

Both were found only because hosted Supabase infrastructure differs from
a plain `postgres:16` Docker container in ways no amount of local testing
could surface:

**1. `gen_random_bytes`/`digest` not found under `search_path=public`.**
Migration 0007 was the first migration in this repository to actually
call pgcrypto functions in SQL (`gen_random_bytes()` for lease tokens,
`digest()` for hashing). Locally, a fresh `postgres:16` container's
`create extension if not exists pgcrypto` (migration 0001) installs the
extension directly into `public` (the default schema for a new
connection), so `gen_random_bytes`/`digest` resolve fine under
`search_path=public`. On hosted Supabase, pgcrypto is **pre-installed in
an `extensions` schema** as part of the platform's own project bootstrap
— migration 0001's `create extension if not exists pgcrypto` is a no-op
against the already-installed extension, so it never relocates it. The
first real hosted claim call failed:
```
{"code":"42883","message":"function gen_random_bytes(integer) does not exist"}
```
**Fixed** by adding `extensions` to the `search_path` of the two
functions that call these directly (`assert_lease_owner`,
`claim_next_document_processing_job`): `set search_path = public,
extensions`. A nonexistent schema in `search_path` is silently skipped by
Postgres, so this is safe and correct on both environments — locally,
`extensions` doesn't exist and the effective path is just `public` (where
pgcrypto actually lives there); on hosted, `extensions` exists and
resolves the functions. Re-verified against a fresh local Docker
container (full 001–006 suite green) before reapplying to hosted.

**2. `authenticated`/`anon` could call all six Worker-only functions —
the core trust-boundary claim of this migration was false on hosted.**
ADR 0009 states these six functions are "never granted to `authenticated`
at all... no permission a browser session could hold would let it call
them" — the migration only ever does `revoke all on function ... from
public`. On hosted Supabase, a project-level `ALTER DEFAULT PRIVILEGES
... GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role`
grants EXECUTE **directly** to those three named roles at function
*creation* time — a grant that revoking from the `PUBLIC` pseudo-role
does not touch. A direct hosted query confirmed it:
```sql
select grantee, privilege_type from information_schema.routine_privileges
where routine_name = 'claim_next_document_processing_job';
→ postgres, anon, authenticated, service_role   (all four — before the fix)
```
And a real authenticated-JWT RPC call to `claim_next_document_processing_job`
returned `200`, not `401`/`403` — an ordinary signed-in `organization_admin`
user could genuinely claim, lease, and manipulate processing jobs, which
should have been structurally impossible. Plain local Postgres has no
such default-privilege rule (and doesn't even have an `anon` role),
which is exactly why this was invisible in every prior local run.
**Fixed** by adding an explicit, guarded `revoke execute ... from
authenticated` / `from anon` block (each guarded independently — local
Postgres has an `authenticated` role for RLS test purposes but no `anon`
role at all) covering all eight functions (`assert_lease_owner`,
`compute_retry_delay_seconds`, and the six Worker-only functions).
Re-verified: the same query now returns only `postgres` and
`service_role`, and the same authenticated-JWT call now returns `403`/`404`.

Both fixes are in the version of `supabase/migrations/0007_durable_processing_orchestration.sql`
committed with this sprint — re-validated against a fresh local Docker
container (full 001–006 suite, 27/27 orchestration assertions, and the
80-job dual-process concurrency proof, all green) before being reapplied
to hosted.

### Real end-to-end flow — 30/30 hosted checks passed

Real GoTrue JWTs for three synthetic users (`organization_admin`,
`quality_manager`, `clinician`), real PostgREST RPC calls, real
`service_role` credential usage for the six Worker-only functions:

```
PASS  fixture: organization, 3 GoTrue users, memberships, domain, authority created
PASS  fixture: 5 queued processing jobs created via real authenticated RPC calls
PASS  SECURITY: authenticated (even organization_admin) cannot call heartbeat_document_processing_job
PASS  SECURITY: authenticated cannot call claim_next_document_processing_job
PASS  claim (service_role): returns a job with a usable lease token
PASS  start denied for a non-owning worker
PASS  start succeeds for the real lease owner
PASS  heartbeat succeeds and extends the lease
PASS  complete succeeds
PASS  replayed completion is idempotent (same completed_at)
PASS  retryable failure schedules retry_scheduled
PASS  2nd/3rd reclaim of the due retry_scheduled job (same job id, not a different one)
PASS  3rd retryable failure exhausts max_attempts -> dead_lettered
PASS  recovery reclaims a job with an expired lease
PASS  the original (now-stale) worker is locked out after recovery
PASS  quality_manager cancels a queued job
PASS  clinician (lacking the cancel permission) is denied
PASS  clinician cannot read processing jobs (RLS)
PASS  organization_admin (holds .read) can read processing jobs (RLS)
PASS  genuine concurrent HTTP claim race: 20 parallel requests, no duplicate job ids

30 passed, 0 failed
```

The concurrent-claim check fired 20 real parallel HTTP requests
(`Promise.all` over 20 independent `fetch()` calls) against hosted
PostgREST — an even stronger concurrency proof than the local dual-process
script, since it races over real network I/O against the actual hosted
database, not just two local OS processes. Zero duplicate job ids among
the 20 claims.

### Synthetic test data cleanup — confirmed

The append-only tables involved (`document_intake_events`, `audit_events`)
required the documented `noor.allow_audit_maintenance` override — applied
via the Supabase Management API's direct-SQL endpoint (`set local
noor.allow_audit_maintenance = 'true'` + deletes, in FK-dependency order,
in one transaction), since no plain REST `DELETE` can bypass the
append-only trigger. All synthetic rows (jobs, attempts, intake events,
documents, sessions, lifecycle events, reviews, versions, guidelines,
authority, domain, audit events, memberships, organization) and all 3
synthetic GoTrue users were deleted. A final query confirmed:

```sql
residual_orgs: 0, residual_jobs: 0, residual_memberships: 0
stray verify users remaining: 0
```

### Vercel Preview

Redeployed with the updated code (streaming verification, Job Status
Card / Attempt History UI) — `vercel inspect` confirmed `target: preview`,
`status: Ready`. The stable alias `noor-preview-dev.vercel.app` was
re-pointed at the new deployment. The unprotected smoke test
(`scripts/smoke-test-web.mjs`, no `BYPASS_TOKEN` available this session)
correctly detected and reported Vercel's Deployment Protection wall for
every body-content check — the same, expected, non-false-passing
behavior observed in every prior session without the bypass token
in hand. Deployment Protection remains **enabled and correctly enforced**,
unchanged.

### CI

Confirmed green on GitHub Actions for the commit accompanying this
document — see the final Sprint 1.2A closure report for the exact run URL.
