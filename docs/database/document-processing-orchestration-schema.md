# Database Schema — Durable Processing Orchestration (Sprint 1.2A)

Source: `supabase/migrations/0007_durable_processing_orchestration.sql`.
Builds on `docs/database/secure-document-intake-schema.md`'s
`document_processing_jobs`/`document_processing_attempts` tables — this
document only covers what migration 0007 adds or changes.

## Schema changes

`document_processing_jobs` gained:

| Column | Type | Purpose |
|---|---|---|
| `next_attempt_at` | `timestamptz` | When a `retry_scheduled` job becomes claimable again |
| `lease_token_hash` | `text` | SHA-256 of the current lease token; never the plaintext |
| `lease_acquired_at` | `timestamptz` | When the current lease started |
| `lease_expires_at` | `timestamptz` | When the current lease becomes eligible for recovery |
| `dead_lettered_at` | `timestamptz` | When `max_attempts` was exhausted |
| `error_class` | `text` | Structured error category (never a raw exception message) |
| `result_summary` | `jsonb not null default '{}'` | The processor's safe, structured outcome |

`status` CHECK widened to add `'retry_scheduled'`. Two new indexes:
`idx_processing_jobs_claim_lookup (status, next_attempt_at, priority,
created_at)` (the claim function's hot path) and
`idx_processing_jobs_active_leases (lease_expires_at) WHERE status IN
('claimed', 'processing')` (the recovery function's hot path, a partial
index so it stays small regardless of total job volume).

`document_processing_attempts` gained `lease_acquired_at`,
`lease_expires_at`, `last_heartbeat_at`, `error_class`. `status` CHECK
widened from empty (Sprint 1.1 never wrote a row) to `('started',
'succeeded', 'retryable_failure', 'terminal_failure', 'lease_expired',
'cancelled', 'abandoned')`.

## Trust boundary: six functions, zero grants to `authenticated`

Every function in this migration except `cancel_processing_job` (a
`CREATE OR REPLACE` of the existing Sprint 1.1 function) ends with:

```sql
revoke all on function <name>(...) from public;
```

and — unlike every function in migrations 0005/0006 — **no corresponding
grant to `authenticated`**. Supabase's `service_role` has default broad
access these functions never revoke, so the Worker's `service_role`
credential (server-only, `SUPABASE_SERVICE_ROLE_KEY`) can call them; an
ordinary signed-in user's session, regardless of permissions held, cannot.
See ADR 0009 and `docs/security/worker-orchestration-authorization.md`.

## Output-column naming: `out_` prefix, adopted after two prior bugs

`docs/database/secure-document-intake-schema.md` documents a real bug hit
twice in migration 0006: a `RETURNS TABLE` function's implicit output
variable shadowing a real table column referenced later in the same
function body. Rather than relying on remembering to table-qualify every
reference, every `RETURNS TABLE` function in this migration prefixes every
output column with `out_` (`out_job_id`, `out_status`,
`out_lease_expires_at`, ...) — a name that structurally cannot collide
with any real table column. No instance of the bug recurred this sprint
(confirmed by running every new function against real Postgres 16 — see
the verification record).

## The atomic claim: `FOR UPDATE SKIP LOCKED`

```sql
select j.id into v_job_id
from document_processing_jobs j
where j.job_type = any(p_job_types)
  and (j.status = 'queued' or (j.status = 'retry_scheduled' and j.next_attempt_at <= v_now))
  and exists (select 1 from guideline_source_documents gsd where gsd.id = j.source_document_id and gsd.status = 'registered')
order by j.priority asc, j.created_at asc
for update of j skip locked
limit 1;
```

A second concurrent caller against the same row set simply skips any row
already locked by a still-in-flight first caller; once the first commits
(moving the row to `status = 'claimed'`), the row no longer matches the
`WHERE` clause for anyone. This is provably correct under real concurrency
— not just sequential-session inference — via
`supabase/tests/concurrency/verify_concurrent_claim.sh`: two independent
OS processes (separate `docker exec ... psql` connections, i.e. separate
Postgres backends) raced against 80 shared queued jobs; result: exactly
80 claimed, zero overlap, zero lost jobs.

## Retry backoff: one canonical function, two call sites

```sql
create or replace function compute_retry_delay_seconds(p_attempt_count int)
returns int language sql immutable as $$
  select least(30 * power(2, greatest(p_attempt_count - 1, 0))::int, 900);
$$;
```

Called from both `fail_document_processing_job()` (a Worker-reported
retryable failure) and `recover_expired_document_processing_jobs()` (a
silently-expired lease) — a single source of truth means retry timing
cannot diverge depending on *why* a job needs another attempt.

## Lease-ownership assertion: one helper, reused everywhere ownership matters

```sql
create or replace function assert_lease_owner(
  p_job document_processing_jobs, p_worker_instance_id text, p_lease_token text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_job.status not in ('claimed', 'processing') then
    raise exception 'job is not currently leased (status: %)', p_job.status using errcode = '42501';
  end if;
  if p_job.lease_expires_at is null or p_job.lease_expires_at < now() then
    raise exception 'lease has expired' using errcode = '42501';
  end if;
  if p_job.claimed_by is distinct from p_worker_instance_id then
    raise exception 'lease is owned by a different worker' using errcode = '42501';
  end if;
  if p_job.lease_token_hash is distinct from encode(digest(p_lease_token, 'sha256'), 'hex') then
    raise exception 'invalid lease token' using errcode = '42501';
  end if;
end;
$$;
```

Called from `start`/`heartbeat`/`complete`/`fail` before honoring any
state change. Four independent checks, each with its own message
(status/expiry/worker-name/token-hash) — a wrong-worker heartbeat and an
expired-lease heartbeat fail for different, diagnosable reasons rather
than one generic "denied". The hash comparison, not a plaintext one,
means the lease token itself never needs to be readable from the database
to be verified.

## Migration safety

Guarded exactly like 0004–0006: `authenticated`-role grants (only
`cancel_processing_job`'s, this migration) are wrapped in `if exists
(select 1 from pg_roles where rolname = 'authenticated')` — a documented
no-op at CI plain-Postgres migration-apply time, real on hosted. Applied
to a fresh Postgres 16 container with zero errors, immediately followed
by the pre-existing RLS suite (001–005, unmodified, still 100% green on
top of this migration's schema changes) and the new orchestration suite
(006) — see the verification record.
