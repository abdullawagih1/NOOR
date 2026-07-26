-- ============================================================================
-- Noor V1 — Migration 0007: Durable Processing Orchestration
-- Council: Processing Architecture Agent + Database Agent + Security Agent
-- ============================================================================
-- Sprint 1.2A. A reliable execution control plane for verified
-- document_processing_jobs (created 'queued' by migration 0006):
--
--   Queued Job -> Atomic Claim -> Lease -> Processing Attempt -> Heartbeats
--   -> Succeeded | Retry-Scheduled -> Queued (due) | Dead-Lettered
--
-- Plus crash recovery (lease-expiry reclaim) and user cancellation.
-- Does NOT implement PDF parsing/OCR/chunking/embeddings — the Worker's
-- handler for a claimed job remains a controlled no-op this sprint.
--
-- See ADR 0009 for two decisions this migration depends on:
--   1. document_processing_jobs remains the durable source of truth; no
--      queue is introduced this sprint (database-polling Worker instead).
--   2. Every RETURNS TABLE function's output columns are prefixed `out_`
--      to eliminate (not just avoid) the column-shadowing bug class found
--      twice in Sprint 1.1's migration 0006.
--
-- Reuses migration 0005/0006 conventions throughout: assert_permission()
-- and record_audit_event() are called directly, not redefined; tenant
-- integrity via the composite FKs 0006 already established (unchanged
-- here); grants remain the SECURITY DEFINER-only write model — the six new
-- Worker-only functions are additionally NEVER granted to `authenticated`
-- at all (see ADR 0009's trust-boundary section) — only `service_role`,
-- which the Worker alone holds, can reach them.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SCHEMA EXTENSIONS — document_processing_jobs
-- ----------------------------------------------------------------------------

alter table document_processing_jobs
  add column if not exists next_attempt_at timestamptz,
  add column if not exists lease_token_hash text,
  add column if not exists lease_acquired_at timestamptz,
  add column if not exists lease_expires_at timestamptz,
  add column if not exists dead_lettered_at timestamptz,
  add column if not exists error_class text,
  add column if not exists result_summary jsonb not null default '{}'::jsonb;

-- Widen the status set to add 'retry_scheduled' (migration 0006's original
-- CHECK constraint, replaced — not editing 0006's already-hosted DDL, this
-- is a new migration altering the constraint going forward, same as any
-- normal schema evolution).
alter table document_processing_jobs drop constraint if exists document_processing_jobs_status_check;
alter table document_processing_jobs add constraint document_processing_jobs_status_check
  check (status in ('queued', 'claimed', 'processing', 'retry_scheduled', 'succeeded', 'failed', 'cancelled', 'dead_lettered'));

-- Claim eligibility lookup: queued jobs, or retry-scheduled jobs whose
-- next_attempt_at has arrived, ordered by priority then age.
create index if not exists idx_processing_jobs_claim_lookup
  on document_processing_jobs (status, next_attempt_at, priority, created_at);

-- Lease-expiry recovery lookup — partial, since the predicate only
-- references `status` (a stable value list, not now()).
create index if not exists idx_processing_jobs_active_leases
  on document_processing_jobs (lease_expires_at)
  where status in ('claimed', 'processing');

-- ----------------------------------------------------------------------------
-- 2. SCHEMA EXTENSIONS — document_processing_attempts
-- ----------------------------------------------------------------------------

alter table document_processing_attempts
  add column if not exists lease_acquired_at timestamptz,
  add column if not exists lease_expires_at timestamptz,
  add column if not exists last_heartbeat_at timestamptz,
  add column if not exists error_class text;

alter table document_processing_attempts drop constraint if exists document_processing_attempts_status_check;
alter table document_processing_attempts add constraint document_processing_attempts_status_check
  check (status in ('started', 'succeeded', 'retryable_failure', 'terminal_failure', 'lease_expired', 'cancelled', 'abandoned'));

-- Deliberately NOT append-only (unlike every other history table in this
-- repo): an attempt's own status/heartbeat legitimately mutates in place
-- as the SAME attempt progresses (started -> succeeded, or started ->
-- retryable_failure, etc.) — mission §14 explicitly carves this out. Still
-- only mutable via the SECURITY DEFINER functions below (no INSERT/UPDATE/
-- DELETE grant to `authenticated` exists on this table — see migration
-- 0006 section 9, unchanged here).

-- ============================================================================
-- 3. INTERNAL HELPERS
-- ============================================================================

-- Verifies the caller genuinely holds the lease on an already-locked job
-- row (the caller must have done `select ... for update` first). Checked
-- via a hashed-token comparison — the plaintext lease token is never
-- stored, only compared. See ADR 0009.
create or replace function assert_lease_owner(
  p_job document_processing_jobs,
  p_worker_instance_id text,
  p_lease_token text
) returns void
-- search_path includes `extensions`: on hosted Supabase, pgcrypto's
-- digest()/gen_random_bytes() live in the `extensions` schema, not
-- `public` (Supabase pre-installs pgcrypto there; migration 0001's
-- `create extension if not exists pgcrypto` is a no-op against an
-- already-installed extension, so it never relocates it). Locally,
-- plain `postgres:16` installs pgcrypto directly into `public` and has
-- no `extensions` schema at all — a nonexistent schema in search_path is
-- silently skipped, so this is safe and correct on both environments.
language plpgsql security definer set search_path = public, extensions as $$
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

revoke all on function assert_lease_owner(document_processing_jobs, text, text) from public;

-- Canonical backoff policy — documented once, used by both
-- fail_document_processing_job() and recover_expired_document_processing_jobs()
-- so retry timing can never diverge between the two call sites. 30s, 60s,
-- 120s, ... capped at 900s (15 minutes). See
-- docs/domain/document-processing-orchestration.md.
create or replace function compute_retry_delay_seconds(p_attempt_count int)
returns int
language sql immutable as $$
  select least(30 * power(2, greatest(p_attempt_count - 1, 0))::int, 900);
$$;

revoke all on function compute_retry_delay_seconds(int) from public;

-- ============================================================================
-- 4. FUNCTIONS — Worker-only (never granted to `authenticated`; see ADR 0009)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 claim_next_document_processing_job
-- ----------------------------------------------------------------------------
-- Atomic claim: FOR UPDATE SKIP LOCKED guarantees two concurrent callers
-- can never claim the same job (the second simply skips the row the first
-- already locked, and once the first commits the row no longer matches
-- the WHERE clause for anyone). Also defends in depth against claiming a
-- job whose source document is no longer registered (structurally
-- shouldn't happen — quarantine already cascades job cancellation — but
-- cheap to check directly here too).

create or replace function claim_next_document_processing_job(
  p_worker_instance_id text,
  p_job_types text[] default array['document_parsing'],
  p_lease_duration_seconds int default 90,
  p_correlation_id uuid default gen_random_uuid()
) returns table (
  out_job_id uuid,
  out_organization_id uuid,
  out_source_document_id uuid,
  out_job_type text,
  out_pipeline_version text,
  out_correlation_id uuid,
  out_attempt_number int,
  out_lease_token text,
  out_lease_expires_at timestamptz
)
-- search_path includes `extensions` — see assert_lease_owner() above for
-- why (this function calls gen_random_bytes()/digest() directly).
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_job_id uuid;
  v_lease_token text;
  v_lease_token_hash text;
  v_now timestamptz := now();
  v_expires timestamptz;
  v_row document_processing_jobs%rowtype;
begin
  if p_worker_instance_id is null or btrim(p_worker_instance_id) = '' then
    raise exception 'worker_instance_id is required';
  end if;

  select j.id into v_job_id
  from document_processing_jobs j
  where j.job_type = any(p_job_types)
    and (
      j.status = 'queued'
      or (j.status = 'retry_scheduled' and j.next_attempt_at <= v_now)
    )
    and exists (
      select 1 from guideline_source_documents gsd
      where gsd.id = j.source_document_id and gsd.status = 'registered'
    )
  order by j.priority asc, j.created_at asc
  for update of j skip locked
  limit 1;

  if v_job_id is null then
    return;
  end if;

  v_lease_token := encode(gen_random_bytes(32), 'hex');
  v_lease_token_hash := encode(digest(v_lease_token, 'sha256'), 'hex');
  v_expires := v_now + make_interval(secs => p_lease_duration_seconds);

  update document_processing_jobs set
    status = 'claimed',
    attempt_count = attempt_count + 1,
    claimed_by = p_worker_instance_id,
    claimed_at = v_now,
    heartbeat_at = v_now,
    lease_token_hash = v_lease_token_hash,
    lease_acquired_at = v_now,
    lease_expires_at = v_expires,
    next_attempt_at = null,
    updated_at = v_now
  where id = v_job_id
  returning * into v_row;

  insert into document_processing_attempts (
    organization_id, processing_job_id, attempt_number, worker_id, status,
    started_at, last_heartbeat_at, lease_acquired_at, lease_expires_at
  ) values (
    v_row.organization_id, v_job_id, v_row.attempt_count, p_worker_instance_id, 'started',
    v_now, v_now, v_now, v_expires
  );

  insert into document_intake_events (organization_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_row.organization_id, v_job_id, 'document_processing_job.claimed', null, p_correlation_id,
      jsonb_build_object('worker_instance_id', p_worker_instance_id, 'attempt_number', v_row.attempt_count));

  return query select
    v_row.id, v_row.organization_id, v_row.source_document_id, v_row.job_type, v_row.pipeline_version,
    p_correlation_id, v_row.attempt_count, v_lease_token, v_expires;
end;
$$;

revoke all on function claim_next_document_processing_job(text, text[], int, uuid) from public;

-- ----------------------------------------------------------------------------
-- 4.2 start_document_processing_job
-- ----------------------------------------------------------------------------

create or replace function start_document_processing_job(
  p_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_job_id uuid, out_status text, out_started_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_row document_processing_jobs%rowtype;
begin
  select * into v_row from document_processing_jobs where id = p_job_id for update;
  if not found then
    raise exception 'job not found: %', p_job_id;
  end if;

  -- Idempotent replay: already processing under this same worker's lease.
  if v_row.status = 'processing' and v_row.claimed_by = p_worker_instance_id then
    perform assert_lease_owner(v_row, p_worker_instance_id, p_lease_token);
    return query select v_row.id, v_row.status, v_row.started_at;
    return;
  end if;

  perform assert_lease_owner(v_row, p_worker_instance_id, p_lease_token);
  if v_row.status <> 'claimed' then
    raise exception 'only a claimed job can start processing (current status: %)', v_row.status;
  end if;

  update document_processing_jobs set status = 'processing', started_at = now(), updated_at = now()
    where id = p_job_id
    returning * into v_row;

  insert into document_intake_events (organization_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_row.organization_id, p_job_id, 'document_processing_job.started', null, p_correlation_id,
      jsonb_build_object('worker_instance_id', p_worker_instance_id));

  return query select v_row.id, v_row.status, v_row.started_at;
end;
$$;

revoke all on function start_document_processing_job(uuid, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 4.3 heartbeat_document_processing_job
-- ----------------------------------------------------------------------------
-- Deliberately writes no domain/audit event (mission §15/§31 — heartbeats
-- would flood the event history for no operational benefit).

create or replace function heartbeat_document_processing_job(
  p_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_lease_duration_seconds int default 90
) returns table (out_job_id uuid, out_lease_expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_row document_processing_jobs%rowtype;
  v_expires timestamptz;
begin
  select * into v_row from document_processing_jobs where id = p_job_id for update;
  if not found then
    raise exception 'job not found: %', p_job_id;
  end if;

  perform assert_lease_owner(v_row, p_worker_instance_id, p_lease_token);

  v_expires := now() + make_interval(secs => p_lease_duration_seconds);

  update document_processing_jobs set lease_expires_at = v_expires, heartbeat_at = now(), updated_at = now()
    where id = p_job_id;

  update document_processing_attempts set last_heartbeat_at = now(), lease_expires_at = v_expires
    where processing_job_id = p_job_id and attempt_number = v_row.attempt_count;

  return query select p_job_id, v_expires;
end;
$$;

revoke all on function heartbeat_document_processing_job(uuid, text, text, int) from public;

-- ----------------------------------------------------------------------------
-- 4.4 complete_document_processing_job
-- ----------------------------------------------------------------------------
-- result_summary must describe a controlled no-op this sprint (see ADR
-- 0009) — this function does not validate its shape beyond "is jsonb",
-- trusting the Worker (a server-only, trusted caller) not to fabricate
-- extracted clinical content, matching mission §17's instruction not to
-- create fake extracted pages or text.

create or replace function complete_document_processing_job(
  p_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_result_summary jsonb default '{}'::jsonb,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_job_id uuid, out_status text, out_completed_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_row document_processing_jobs%rowtype;
begin
  select * into v_row from document_processing_jobs where id = p_job_id for update;
  if not found then
    raise exception 'job not found: %', p_job_id;
  end if;

  -- Idempotent replay: already succeeded — return the existing outcome
  -- rather than re-validating lease ownership (a stale-but-formerly-valid
  -- worker replaying its own successful completion must not error).
  if v_row.status = 'succeeded' then
    return query select v_row.id, v_row.status, v_row.completed_at;
    return;
  end if;

  perform assert_lease_owner(v_row, p_worker_instance_id, p_lease_token);
  if v_row.status <> 'processing' then
    raise exception 'only a processing job can be completed (current status: %)', v_row.status;
  end if;

  update document_processing_jobs set
    status = 'succeeded', completed_at = now(), result_summary = coalesce(p_result_summary, '{}'::jsonb),
    lease_token_hash = null, lease_expires_at = null, updated_at = now()
    where id = p_job_id
    returning * into v_row;

  update document_processing_attempts set status = 'succeeded', completed_at = now()
    where processing_job_id = p_job_id and attempt_number = v_row.attempt_count;

  insert into document_intake_events (organization_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_row.organization_id, p_job_id, 'document_processing_job.succeeded', null, p_correlation_id,
      jsonb_build_object('worker_instance_id', p_worker_instance_id, 'idempotency_key', p_idempotency_key));

  return query select v_row.id, v_row.status, v_row.completed_at;
end;
$$;

revoke all on function complete_document_processing_job(uuid, text, text, jsonb, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 4.5 fail_document_processing_job
-- ----------------------------------------------------------------------------
-- Retry timing is entirely database-controlled (compute_retry_delay_seconds)
-- — a Worker-reported failure never supplies its own delay.

create or replace function fail_document_processing_job(
  p_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_error_code text,
  p_error_class text,
  p_error_message_safe text,
  p_retryable boolean default true,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_job_id uuid, out_status text, out_next_attempt_at timestamptz, out_attempt_count int, out_max_attempts int)
language plpgsql security definer set search_path = public as $$
declare
  v_row document_processing_jobs%rowtype;
  v_new_status text;
  v_next_attempt timestamptz;
begin
  select * into v_row from document_processing_jobs where id = p_job_id for update;
  if not found then
    raise exception 'job not found: %', p_job_id;
  end if;

  -- Idempotent replay: a terminal-ish outcome was already recorded.
  if v_row.status in ('failed', 'dead_lettered', 'retry_scheduled') then
    return query select v_row.id, v_row.status, v_row.next_attempt_at, v_row.attempt_count, v_row.max_attempts;
    return;
  end if;

  perform assert_lease_owner(v_row, p_worker_instance_id, p_lease_token);
  if v_row.status not in ('claimed', 'processing') then
    raise exception 'only a claimed or processing job can report failure (current status: %)', v_row.status;
  end if;

  update document_processing_attempts set
    status = case when p_retryable then 'retryable_failure' else 'terminal_failure' end,
    completed_at = now(), error_code = p_error_code, error_class = p_error_class, error_message_safe = p_error_message_safe
    where processing_job_id = p_job_id and attempt_number = v_row.attempt_count;

  if p_retryable and v_row.attempt_count < v_row.max_attempts then
    v_new_status := 'retry_scheduled';
    v_next_attempt := now() + make_interval(secs => compute_retry_delay_seconds(v_row.attempt_count));
  elsif p_retryable then
    v_new_status := 'dead_lettered';
    v_next_attempt := null;
  else
    v_new_status := 'failed';
    v_next_attempt := null;
  end if;

  update document_processing_jobs set
    status = v_new_status,
    next_attempt_at = v_next_attempt,
    lease_token_hash = null, lease_expires_at = null,
    error_code = p_error_code, error_class = p_error_class, error_message_safe = p_error_message_safe,
    failed_at = case when v_new_status = 'failed' then now() else failed_at end,
    dead_lettered_at = case when v_new_status = 'dead_lettered' then now() else dead_lettered_at end,
    updated_at = now()
    where id = p_job_id
    returning * into v_row;

  insert into document_intake_events (organization_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_row.organization_id, p_job_id,
      case v_new_status
        when 'retry_scheduled' then 'document_processing_job.retry_scheduled'
        when 'dead_lettered' then 'document_processing_job.dead_lettered'
        else 'document_processing_job.failed'
      end,
      null, p_correlation_id,
      jsonb_build_object('worker_instance_id', p_worker_instance_id, 'attempt_count', v_row.attempt_count,
        'error_code', p_error_code, 'error_class', p_error_class, 'retryable', p_retryable));

  return query select v_row.id, v_row.status, v_row.next_attempt_at, v_row.attempt_count, v_row.max_attempts;
end;
$$;

revoke all on function fail_document_processing_job(uuid, text, text, text, text, text, boolean, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 4.6 recover_expired_document_processing_jobs
-- ----------------------------------------------------------------------------
-- Safe under concurrent recovery calls: FOR UPDATE SKIP LOCKED means two
-- concurrent invocations never both reclaim the same expired job.

create or replace function recover_expired_document_processing_jobs(
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_job_id uuid, out_new_status text)
language plpgsql security definer set search_path = public as $$
declare
  v_job record;
  v_new_status text;
  v_next_attempt timestamptz;
begin
  for v_job in
    select j.* from document_processing_jobs j
    where j.status in ('claimed', 'processing')
      and j.lease_expires_at is not null and j.lease_expires_at < now()
    for update of j skip locked
  loop
    update document_processing_attempts set status = 'lease_expired', completed_at = now()
      where processing_job_id = v_job.id and attempt_number = v_job.attempt_count
        and status not in ('succeeded', 'retryable_failure', 'terminal_failure');

    if v_job.attempt_count < v_job.max_attempts then
      v_new_status := 'retry_scheduled';
      v_next_attempt := now() + make_interval(secs => compute_retry_delay_seconds(v_job.attempt_count));
    else
      v_new_status := 'dead_lettered';
      v_next_attempt := null;
    end if;

    update document_processing_jobs set
      status = v_new_status,
      next_attempt_at = v_next_attempt,
      lease_token_hash = null, lease_expires_at = null,
      error_code = coalesce(error_code, 'lease_expired'), error_class = 'lease_lost',
      error_message_safe = 'the worker lease expired before the job completed',
      dead_lettered_at = case when v_new_status = 'dead_lettered' then now() else dead_lettered_at end,
      updated_at = now()
      where id = v_job.id;

    insert into document_intake_events (organization_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
      values (v_job.organization_id, v_job.id, 'document_processing_job.recovered', null, p_correlation_id,
        jsonb_build_object('previous_worker', v_job.claimed_by, 'new_status', v_new_status));

    out_job_id := v_job.id;
    out_new_status := v_new_status;
    return next;
  end loop;
end;
$$;

revoke all on function recover_expired_document_processing_jobs(uuid) from public;

-- ============================================================================
-- 5. FUNCTION — cancel_document_processing_job (user-facing, replaces the
-- migration 0006 version to widen allowed source statuses)
-- ============================================================================
-- CREATE OR REPLACE preserves the existing grant to `authenticated` from
-- migration 0006 (same name, same argument types) — no re-grant needed.

create or replace function cancel_processing_job(
  p_processing_job_id uuid,
  p_reason text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_processing_jobs
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_job document_processing_jobs%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;

  perform assert_permission(v_job.organization_id, 'guideline_processing_jobs.cancel');

  if v_job.status = 'cancelled' then
    return v_job;
  end if;

  if v_job.status not in ('queued', 'retry_scheduled') then
    raise exception 'only a queued or retry-scheduled job can be cancelled (current status: %)', v_job.status;
  end if;

  update document_processing_jobs set
    status = 'cancelled', cancelled_at = now(), next_attempt_at = null, updated_at = now()
    where id = p_processing_job_id
    returning * into v_job;

  insert into document_intake_events (organization_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_job.organization_id, p_processing_job_id, 'document_processing_job.cancelled', v_actor, p_correlation_id, jsonb_build_object('reason', p_reason));
  perform record_audit_event(v_job.organization_id, 'document_processing_job.cancelled', 'document_processing_job', p_processing_job_id, p_correlation_id, jsonb_build_object('reason', p_reason));

  return v_job;
end;
$$;

-- ============================================================================
-- 5. GRANTS — explicit revoke from `authenticated`/`anon` on every
-- Worker-only function (found necessary by hosted verification, not by
-- reading the SQL: Supabase's hosted projects run `ALTER DEFAULT
-- PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon, authenticated,
-- service_role` at the database level, so EVERY new function created in
-- `public` — including these six — is automatically EXECUTE-granted
-- directly to `authenticated`/`anon` at creation time, independent of
-- `revoke all on function ... from public` above. Revoking from the
-- PUBLIC pseudo-role does not touch a grant made directly to a named
-- role. Plain local Postgres has no such default-privilege rule (and no
-- `authenticated`/`anon` roles at all), which is exactly why this was
-- invisible in every local Docker run and caught only against real
-- hosted infrastructure. Guarded exactly like every other
-- `authenticated`-touching statement in this codebase.
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke execute on function
      assert_lease_owner(document_processing_jobs, text, text),
      compute_retry_delay_seconds(int),
      claim_next_document_processing_job(text, text[], int, uuid),
      start_document_processing_job(uuid, text, text, uuid),
      heartbeat_document_processing_job(uuid, text, text, int),
      complete_document_processing_job(uuid, text, text, jsonb, text, uuid),
      fail_document_processing_job(uuid, text, text, text, text, text, boolean, text, uuid),
      recover_expired_document_processing_jobs(uuid)
      from authenticated;
  end if;
  -- Guarded independently: local plain Postgres has an `authenticated`
  -- role (created for `set local role authenticated` in the RLS test
  -- suite) but no `anon` role at all — a single combined REVOKE naming
  -- both roles would error locally the moment either one is missing.
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke execute on function
      assert_lease_owner(document_processing_jobs, text, text),
      compute_retry_delay_seconds(int),
      claim_next_document_processing_job(text, text[], int, uuid),
      start_document_processing_job(uuid, text, text, uuid),
      heartbeat_document_processing_job(uuid, text, text, int),
      complete_document_processing_job(uuid, text, text, jsonb, text, uuid),
      fail_document_processing_job(uuid, text, text, text, text, text, boolean, text, uuid),
      recover_expired_document_processing_jobs(uuid)
      from anon;
  end if;
end
$$;

-- ============================================================================
-- End of migration 0007
-- ============================================================================
