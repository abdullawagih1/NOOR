-- ============================================================================
-- Noor V1 Test Suite — Durable Processing Orchestration (migration 0007)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 006_processing_orchestration.sql
-- Depends on 001-005 already having run in this database.
--
-- The six Worker-only functions (claim/start/heartbeat/complete/fail/
-- recover) are never granted to `authenticated` (ADR 0009) — only a
-- trusted execution context (service_role on hosted; the connecting
-- superuser/table-owner role here, which is the correct local analogue,
-- since both bypass grants/RLS entirely) can call them. This file calls
-- them as the plain connecting role, with NO `set local role
-- authenticated`, exactly mirroring how the real Worker reaches them on
-- hosted. `cancel_processing_job` is the one `authenticated`-gated
-- exception and is called under `set local role authenticated`.
--
-- `set local role`/`set local request.jwt.*` only ever appear as TOP-LEVEL
-- statements in this file (never inside a `DO $$...$$` block) — the only
-- pattern proven safe across every prior RLS test file in this repo.
--
-- Genuine concurrent (two-OS-process) proof that two workers cannot claim
-- the same job is run separately via bash, not in this single-connection
-- SQL file — see
-- docs/verification/sprint-1.2a-processing-orchestration-verification.md.
-- ============================================================================

\set ON_ERROR_STOP on

grant execute on function
  create_clinical_domain(uuid, text, text, text),
  create_guideline_authority(uuid, text, text, text, text, text, boolean, text),
  create_guideline(uuid, uuid, uuid, text, text, text, text, text, text),
  create_guideline_version(uuid, text, text, date, date, date, date, text, text, text, text, text, text, text, text),
  create_guideline_upload_session(uuid, text, text, bigint, text, text, uuid),
  complete_guideline_upload(uuid, text, bigint, text, text, uuid),
  cancel_processing_job(uuid, text, uuid)
  to authenticated;

create temporary table test_fixtures (key text primary key, value uuid not null);
create temporary table test_text_fixtures (key text primary key, value text not null);

create or replace function test_fixture_set(p_key text, p_value uuid) returns uuid
language sql security definer as $$
  insert into test_fixtures (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value
  returning value;
$$;

create or replace function fx(p_key text) returns uuid
language sql stable security definer as $$
  select value from test_fixtures where key = p_key;
$$;

create or replace function test_text_fixture_set(p_key text, p_value text) returns text
language sql security definer as $$
  insert into test_text_fixtures (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value
  returning value;
$$;

create or replace function fxt(p_key text) returns text
language sql stable security definer as $$
  select value from test_text_fixtures where key = p_key;
$$;

-- ----------------------------------------------------------------------------
-- FIXTURE: domain + authority, then four registered documents (four queued
-- jobs), each via the real Sprint 1.1 intake flow — unrolled top-level
-- blocks, not a plpgsql loop, so `set local role`/`set local request.jwt.*`
-- never appear inside a DO block.
-- ----------------------------------------------------------------------------

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('domain_id', id) from create_clinical_domain('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'orch-domain', 'Orchestration Test Domain', null);
  select test_fixture_set('authority_id', id) from create_guideline_authority('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Orchestration Test Authority', null, null, null, null, true, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline1_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'ORCH-001', 'Orchestration Guideline 1');
  select test_fixture_set('version1_id', id) from create_guideline_version(fx('guideline1_id'), 'v1.0');
  select test_fixture_set('session1_id', upload_session_id), test_fixture_set('document1_id', source_document_id)
    from create_guideline_upload_session(fx('version1_id'), 'orch-fixture-1.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('job1_id', processing_job_id) from complete_guideline_upload(fx('session1_id'), 'application/pdf', 1000, repeat('1', 64), null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline2_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'ORCH-002', 'Orchestration Guideline 2');
  select test_fixture_set('version2_id', id) from create_guideline_version(fx('guideline2_id'), 'v1.0');
  select test_fixture_set('session2_id', upload_session_id), test_fixture_set('document2_id', source_document_id)
    from create_guideline_upload_session(fx('version2_id'), 'orch-fixture-2.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('job2_id', processing_job_id) from complete_guideline_upload(fx('session2_id'), 'application/pdf', 1000, repeat('2', 64), null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline3_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'ORCH-003', 'Orchestration Guideline 3');
  select test_fixture_set('version3_id', id) from create_guideline_version(fx('guideline3_id'), 'v1.0');
  select test_fixture_set('session3_id', upload_session_id), test_fixture_set('document3_id', source_document_id)
    from create_guideline_upload_session(fx('version3_id'), 'orch-fixture-3.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('job3_id', processing_job_id) from complete_guideline_upload(fx('session3_id'), 'application/pdf', 1000, repeat('3', 64), null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline4_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'ORCH-004', 'Orchestration Guideline 4');
  select test_fixture_set('version4_id', id) from create_guideline_version(fx('guideline4_id'), 'v1.0');
  select test_fixture_set('session4_id', upload_session_id), test_fixture_set('document4_id', source_document_id)
    from create_guideline_upload_session(fx('version4_id'), 'orch-fixture-4.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('job4_id', processing_job_id) from complete_guideline_upload(fx('session4_id'), 'application/pdf', 1000, repeat('4', 64), null);
commit;

-- Two more pool fixtures (job5/job6) so the pool has 6 jobs total: TEST 1
-- claims 1, TEST 2 claims 3 more, TEST 7 and TEST 9 each need one further
-- fresh claim later. Named "poolguideline5/6" (not "guideline5/6") to avoid
-- colliding with the dedicated fixtures TEST 11 and TEST 12c create later.
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('poolguideline5_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'ORCH-005', 'Orchestration Guideline 5');
  select test_fixture_set('poolversion5_id', id) from create_guideline_version(fx('poolguideline5_id'), 'v1.0');
  select test_fixture_set('poolsession5_id', upload_session_id), test_fixture_set('pooldocument5_id', source_document_id)
    from create_guideline_upload_session(fx('poolversion5_id'), 'orch-fixture-5.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('job5_id', processing_job_id) from complete_guideline_upload(fx('poolsession5_id'), 'application/pdf', 1000, repeat('5', 64), null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('poolguideline6_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'ORCH-006', 'Orchestration Guideline 6');
  select test_fixture_set('poolversion6_id', id) from create_guideline_version(fx('poolguideline6_id'), 'v1.0');
  select test_fixture_set('poolsession6_id', upload_session_id), test_fixture_set('pooldocument6_id', source_document_id)
    from create_guideline_upload_session(fx('poolversion6_id'), 'orch-fixture-6.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('job6_id', processing_job_id) from complete_guideline_upload(fx('poolsession6_id'), 'application/pdf', 1000, repeat('6', 64), null);
commit;

do $$
declare v_count int;
begin
  select count(*) into v_count from document_processing_jobs
    where id in (fx('job1_id'), fx('job2_id'), fx('job3_id'), fx('job4_id'), fx('job5_id'), fx('job6_id')) and status = 'queued';
  if v_count <> 6 then
    raise exception 'FIXTURE FAILED: expected 6 queued jobs, found %', v_count;
  end if;
  raise notice 'FIXTURE READY: 6 registered documents, each with a queued processing job';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: claim succeeds, transitions to claimed, creates one attempt, and
-- returns a usable lease token (captured for later tests). No role switch
-- needed here or below — these six functions are never granted to
-- `authenticated` at all (ADR 0009); calling them as the plain connecting
-- (superuser/table-owner) role is the correct local analogue of the
-- Worker's service_role access on hosted.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_attempt_count int;
begin
  select * into r from claim_next_document_processing_job('test-worker-A', array['document_parsing'], 90, gen_random_uuid());
  if r.out_job_id is null then
    raise exception 'TEST 1 FAILED: claim returned no job when jobs were queued';
  end if;
  if r.out_lease_token is null or length(r.out_lease_token) < 32 then
    raise exception 'TEST 1 FAILED: no usable lease token returned';
  end if;

  perform test_fixture_set('claimed_job_id', r.out_job_id);
  perform test_text_fixture_set('lease_token', r.out_lease_token);

  select attempt_count into v_attempt_count from document_processing_jobs where id = r.out_job_id;
  if v_attempt_count <> 1 then
    raise exception 'TEST 1 FAILED: expected attempt_count=1, got %', v_attempt_count;
  end if;
  raise notice 'TEST 1 PASSED: claim succeeded, job claimed, attempt_count=1, lease token issued';
end
$$;

do $$
declare v_status text; v_attempts int;
begin
  select status into v_status from document_processing_jobs where id = fx('claimed_job_id');
  select count(*) into v_attempts from document_processing_attempts where processing_job_id = fx('claimed_job_id');
  if v_status <> 'claimed' then raise exception 'TEST 1b FAILED: expected claimed, got %', v_status; end if;
  if v_attempts <> 1 then raise exception 'TEST 1b FAILED: expected exactly 1 attempt row, got %', v_attempts; end if;
  raise notice 'TEST 1b PASSED: exactly one attempt record created';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 2: three more sequential claims each return a distinct job, never
-- one already claimed by TEST 1 or by each other. This is a sequential
-- sanity check, not the concurrency proof — true dual-process concurrent
-- claiming is exercised separately in bash (see the file header) because
-- a single psql session cannot demonstrate real concurrency. Note this
-- database is shared cumulative state across the whole 001-006 suite, so
-- other queued jobs may legitimately exist outside this file's own fixture
-- pool (e.g. left behind by 005_document_intake.sql) — this test does not
-- assume or require the queue to become globally empty.
-- ---------------------------------------------------------------------------
do $$
declare
  v_b uuid;
  v_c uuid;
  v_d uuid;
begin
  select out_job_id into v_b from claim_next_document_processing_job('test-worker-B', array['document_parsing'], 90, gen_random_uuid());
  select out_job_id into v_c from claim_next_document_processing_job('test-worker-C', array['document_parsing'], 90, gen_random_uuid());
  select out_job_id into v_d from claim_next_document_processing_job('test-worker-D', array['document_parsing'], 90, gen_random_uuid());

  if v_b is null or v_c is null or v_d is null then
    raise exception 'TEST 2 FAILED: expected three more distinct jobs to be claimable, got b=%, c=%, d=%', v_b, v_c, v_d;
  end if;
  if v_b = v_c or v_b = v_d or v_c = v_d or v_b = fx('claimed_job_id') or v_c = fx('claimed_job_id') or v_d = fx('claimed_job_id') then
    raise exception 'TEST 2 FAILED: two sequential claims returned the same job (double-claim)';
  end if;
  raise notice 'TEST 2 PASSED: three further sequential claims each returned a distinct, previously-unclaimed job';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 3: heartbeat from the wrong worker (or with a wrong token) is
-- denied; the lease expiry is left unchanged.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
declare v_expires_before timestamptz;
declare v_expires_after timestamptz;
begin
  select lease_expires_at into v_expires_before from document_processing_jobs where id = fx('claimed_job_id');

  begin
    perform heartbeat_document_processing_job(fx('claimed_job_id'), 'wrong-worker', 'not-the-real-token', 90);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 3 FAILED: heartbeat from the wrong worker succeeded';
  end if;

  begin
    perform heartbeat_document_processing_job(fx('claimed_job_id'), 'test-worker-A', 'not-the-real-token', 90);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 3b FAILED: heartbeat with a wrong token (right worker name) succeeded';
  end if;

  select lease_expires_at into v_expires_after from document_processing_jobs where id = fx('claimed_job_id');
  if v_expires_after <> v_expires_before then
    raise exception 'TEST 3 FAILED: lease expiry changed despite the denied heartbeats';
  end if;
  raise notice 'TEST 3 PASSED: wrong-worker and wrong-token heartbeats denied, expiry unchanged';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 4: start is denied for a non-owning worker, then succeeds for the
-- real lease owner with the real token.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
declare v_status text;
begin
  begin
    perform start_document_processing_job(fx('claimed_job_id'), 'wrong-worker', 'not-the-real-token');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 4 FAILED: start succeeded for a non-owning worker';
  end if;

  perform start_document_processing_job(fx('claimed_job_id'), 'test-worker-A', fxt('lease_token'));
  select status into v_status from document_processing_jobs where id = fx('claimed_job_id');
  if v_status <> 'processing' then
    raise exception 'TEST 4b FAILED: expected processing after a valid start, got %', v_status;
  end if;
  raise notice 'TEST 4 PASSED: start denied for a non-owner, succeeds for the real owner';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 5: heartbeat succeeds for the real owner and extends the lease.
-- ---------------------------------------------------------------------------
do $$
declare v_expires_before timestamptz;
declare v_expires_after timestamptz;
begin
  select lease_expires_at into v_expires_before from document_processing_jobs where id = fx('claimed_job_id');
  perform pg_sleep(1);
  perform heartbeat_document_processing_job(fx('claimed_job_id'), 'test-worker-A', fxt('lease_token'), 90);
  select lease_expires_at into v_expires_after from document_processing_jobs where id = fx('claimed_job_id');
  if v_expires_after <= v_expires_before then
    raise exception 'TEST 5 FAILED: heartbeat did not extend the lease (before=%, after=%)', v_expires_before, v_expires_after;
  end if;
  raise notice 'TEST 5 PASSED: heartbeat from the real owner extends the lease';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 6: completion is denied for a non-owning worker, succeeds for the
-- real owner, and a replay of the same completion is idempotent.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
declare v_status text;
declare v_completed_at_1 timestamptz;
declare v_completed_at_2 timestamptz;
begin
  begin
    perform complete_document_processing_job(fx('claimed_job_id'), 'wrong-worker', 'not-the-real-token', '{"processor":"orchestration-noop"}'::jsonb, null, gen_random_uuid());
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 6 FAILED: completion succeeded for a non-owning worker';
  end if;

  select out_completed_at into v_completed_at_1 from complete_document_processing_job(
    fx('claimed_job_id'), 'test-worker-A', fxt('lease_token'),
    '{"processor":"orchestration-noop","pipeline_version":"orchestration-v1","status":"completed_without_extraction"}'::jsonb,
    'complete-key-1', gen_random_uuid()
  );
  select status into v_status from document_processing_jobs where id = fx('claimed_job_id');
  if v_status <> 'succeeded' then
    raise exception 'TEST 6b FAILED: expected succeeded, got %', v_status;
  end if;

  select out_completed_at into v_completed_at_2 from complete_document_processing_job(
    fx('claimed_job_id'), 'test-worker-A', fxt('lease_token'), '{}'::jsonb, 'complete-key-1', gen_random_uuid()
  );
  if v_completed_at_2 is distinct from v_completed_at_1 then
    raise exception 'TEST 6c FAILED: replayed completion returned a different completed_at';
  end if;

  raise notice 'TEST 6 PASSED: completion denied for a non-owner, succeeds for the owner, idempotent on replay';
end
$$;

do $$
declare v_attempts int;
declare v_events int;
begin
  select count(*) into v_attempts from document_processing_attempts where processing_job_id = fx('claimed_job_id');
  if v_attempts <> 1 then
    raise exception 'TEST 6d FAILED: expected exactly 1 attempt row after replayed completion, found %', v_attempts;
  end if;
  select count(*) into v_events from document_intake_events
    where processing_job_id = fx('claimed_job_id') and event_type = 'document_processing_job.succeeded';
  if v_events <> 1 then
    raise exception 'TEST 6e FAILED: expected exactly 1 succeeded event, found %', v_events;
  end if;
  raise notice 'TEST 6d/6e PASSED: no duplicate attempt or event from the replayed completion';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 7: retryable failure schedules a retry with the canonical backoff
-- (attempt 1 -> ~30s), clears the lease, and is idempotent on replay.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_lease_token text;
  v_delay_seconds numeric;
begin
  select * into r from claim_next_document_processing_job('test-worker-F', array['document_parsing'], 90, gen_random_uuid());
  if r.out_job_id is null then raise exception 'TEST 7 SETUP FAILED: no job left to claim for the retry test'; end if;
  perform test_fixture_set('retry_job_id', r.out_job_id);
  v_lease_token := r.out_lease_token;
  perform test_text_fixture_set('retry_lease_token', v_lease_token);

  perform start_document_processing_job(r.out_job_id, 'test-worker-F', v_lease_token);

  perform fail_document_processing_job(
    r.out_job_id, 'test-worker-F', v_lease_token,
    'transient_storage_error', 'transient_storage_error', 'simulated transient failure for orchestration testing',
    true, 'fail-key-1', gen_random_uuid()
  );

  select extract(epoch from (next_attempt_at - now())) into v_delay_seconds
    from document_processing_jobs where id = r.out_job_id;

  if (select status from document_processing_jobs where id = r.out_job_id) <> 'retry_scheduled' then
    raise exception 'TEST 7 FAILED: expected retry_scheduled, got %', (select status from document_processing_jobs where id = r.out_job_id);
  end if;
  if (select lease_token_hash from document_processing_jobs where id = r.out_job_id) is not null then
    raise exception 'TEST 7 FAILED: lease was not cleared after the retryable failure';
  end if;
  if v_delay_seconds < 20 or v_delay_seconds > 40 then
    raise exception 'TEST 7 FAILED: expected the first retry delay to be ~30s, got %s', v_delay_seconds;
  end if;

  raise notice 'TEST 7 PASSED: retryable failure schedules a retry at the canonical ~30s backoff and clears the lease';
end
$$;

do $$
declare v_failed boolean := false;
declare v_status_after_replay text;
begin
  begin
    perform fail_document_processing_job(
      fx('retry_job_id'), 'test-worker-F', fxt('retry_lease_token'),
      'transient_storage_error', 'transient_storage_error', 'replayed', true, 'fail-key-1', gen_random_uuid()
    );
  exception when others then
    v_failed := true;
  end;
  if v_failed then
    raise exception 'TEST 7b FAILED: replaying a failure report against an already retry_scheduled job raised instead of returning idempotently';
  end if;
  select status into v_status_after_replay from document_processing_jobs where id = fx('retry_job_id');
  if v_status_after_replay <> 'retry_scheduled' then
    raise exception 'TEST 7b FAILED: replay changed status to %', v_status_after_replay;
  end if;
  raise notice 'TEST 7b PASSED: replayed failure report on a retry_scheduled job is idempotent';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 8: a retry-scheduled job is claimable again once next_attempt_at is
-- due, and repeated retryable failures eventually exhaust max_attempts and
-- dead-letter the job (max_attempts defaults to 3).
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_status text;
  v_attempt_count int;
  v_max_attempts int;
begin
  update document_processing_jobs set next_attempt_at = now() - interval '1 second' where id = fx('retry_job_id');

  select max_attempts into v_max_attempts from document_processing_jobs where id = fx('retry_job_id');

  select * into r from claim_next_document_processing_job('test-worker-G', array['document_parsing'], 90, gen_random_uuid());
  if r.out_job_id <> fx('retry_job_id') then
    raise exception 'TEST 8 SETUP FAILED: claim did not pick up the due retry-scheduled job (got %)', r.out_job_id;
  end if;

  select status, attempt_count into v_status, v_attempt_count from document_processing_jobs where id = fx('retry_job_id');
  if v_status <> 'claimed' then
    raise exception 'TEST 8 FAILED: expected claimed after reclaiming a due retry, got %', v_status;
  end if;
  if v_attempt_count <> 2 then
    raise exception 'TEST 8 FAILED: expected attempt_count=2 on the second claim, got %', v_attempt_count;
  end if;

  perform start_document_processing_job(fx('retry_job_id'), 'test-worker-G', r.out_lease_token);
  perform fail_document_processing_job(fx('retry_job_id'), 'test-worker-G', r.out_lease_token, 'transient_storage_error', 'transient_storage_error', 'attempt 2 failure', true, 'fail-key-2', gen_random_uuid());

  update document_processing_jobs set next_attempt_at = now() - interval '1 second' where id = fx('retry_job_id');
  select * into r from claim_next_document_processing_job('test-worker-H', array['document_parsing'], 90, gen_random_uuid());
  if r.out_job_id <> fx('retry_job_id') then raise exception 'TEST 8 FAILED: third claim did not reclaim the job'; end if;
  perform start_document_processing_job(fx('retry_job_id'), 'test-worker-H', r.out_lease_token);
  perform fail_document_processing_job(fx('retry_job_id'), 'test-worker-H', r.out_lease_token, 'transient_storage_error', 'transient_storage_error', 'attempt 3 (final) failure', true, 'fail-key-3', gen_random_uuid());

  select status, attempt_count into v_status, v_attempt_count from document_processing_jobs where id = fx('retry_job_id');
  if v_attempt_count <> v_max_attempts then
    raise exception 'TEST 8 FAILED: expected attempt_count = max_attempts (%), got %', v_max_attempts, v_attempt_count;
  end if;
  if v_status <> 'dead_lettered' then
    raise exception 'TEST 8 FAILED: expected dead_lettered after exhausting % attempts, got %', v_max_attempts, v_status;
  end if;
  raise notice 'TEST 8 PASSED: max_attempts (%) exhausted -> dead_lettered', v_max_attempts;
end
$$;

do $$
begin
  if exists (select 1 from document_processing_jobs where id = fx('retry_job_id') and status = 'claimed') then
    raise exception 'TEST 8b FAILED: a dead_lettered job was somehow re-claimed';
  end if;
  raise notice 'TEST 8b PASSED: dead_lettered job is not claimable (structurally excluded by the claim WHERE clause)';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 9: lease-expiry recovery reclaims a job whose worker went silent,
-- scheduling a retry (attempts remain) — proven by forcing an expired
-- lease directly (simulating a real timeout without a real wait).
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_status text;
  v_recovered_count int;
begin
  select * into r from claim_next_document_processing_job('test-worker-J', array['document_parsing'], 90, gen_random_uuid());
  if r.out_job_id is null then raise exception 'TEST 9 SETUP FAILED: no job left to claim for the recovery test'; end if;
  perform test_fixture_set('recovery_job_id', r.out_job_id);
  perform start_document_processing_job(r.out_job_id, 'test-worker-J', r.out_lease_token);

  update document_processing_jobs set lease_expires_at = now() - interval '5 minutes' where id = r.out_job_id;

  select count(*) into v_recovered_count from recover_expired_document_processing_jobs(gen_random_uuid())
    where out_job_id = r.out_job_id;
  if v_recovered_count <> 1 then
    raise exception 'TEST 9 FAILED: recovery did not report reclaiming the expired job';
  end if;

  select status into v_status from document_processing_jobs where id = r.out_job_id;
  if v_status <> 'retry_scheduled' then
    raise exception 'TEST 9 FAILED: expected retry_scheduled after recovery, got %', v_status;
  end if;
  raise notice 'TEST 9 PASSED: expired lease reclaimed by recovery, retry scheduled';
end
$$;

do $$
declare v_failed boolean := false;
declare v_attempt_status text;
begin
  select status into v_attempt_status from document_processing_attempts
    where processing_job_id = fx('recovery_job_id') order by attempt_number desc limit 1;
  if v_attempt_status <> 'lease_expired' then
    raise exception 'TEST 9b FAILED: expected the latest attempt to be marked lease_expired, got %', v_attempt_status;
  end if;

  begin
    perform heartbeat_document_processing_job(fx('recovery_job_id'), 'test-worker-J', 'irrelevant-now', 90);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 9c FAILED: the original (now-stale) worker could still heartbeat after recovery reclaimed the job';
  end if;
  raise notice 'TEST 9b/9c PASSED: attempt marked lease_expired; stale worker locked out after recovery';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 10: recovery run twice in a row is safe (nothing left to recover on
-- the second pass) — a simple, real proxy for "safe under concurrent
-- recovery calls" (true dual-process concurrency is exercised in bash).
-- ---------------------------------------------------------------------------
do $$
declare v_count int;
begin
  select count(*) into v_count from recover_expired_document_processing_jobs(gen_random_uuid());
  if v_count <> 0 then
    raise exception 'TEST 10 FAILED: a second recovery pass found % jobs to recover (expected 0)', v_count;
  end if;
  raise notice 'TEST 10 PASSED: a second recovery pass is a safe no-op';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 11: cancellation — queued and retry_scheduled are cancellable;
-- other states are not; repeated cancellation is idempotent; a cancelled
-- job cannot be claimed; unauthorized cancellation is denied.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline5_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'ORCH-CANCEL', 'Orchestration Cancellation Fixture');
  select test_fixture_set('version5_id', id) from create_guideline_version(fx('guideline5_id'), 'v1.0');
  select test_fixture_set('session5_id', upload_session_id), test_fixture_set('document5_id', source_document_id)
    from create_guideline_upload_session(fx('version5_id'), 'orch-cancel.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('cancel_job_id', processing_job_id) from complete_guideline_upload(fx('session5_id'), 'application/pdf', 1000, repeat('5', 64), null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_status text;
  begin
    perform cancel_processing_job(fx('cancel_job_id'), 'orchestration test cancellation');
    select status into v_status from document_processing_jobs where id = fx('cancel_job_id');
    if v_status <> 'cancelled' then
      raise exception 'TEST 11 FAILED: expected cancelled, got %', v_status;
    end if;
    raise notice 'TEST 11 PASSED: quality.alpha cancels a queued job';
  end
  $$;
commit;

do $$
declare v_claim_count int;
begin
  select count(*) into v_claim_count from claim_next_document_processing_job('test-worker-K', array['document_parsing'], 90, gen_random_uuid())
    where out_job_id = fx('cancel_job_id');
  if v_claim_count <> 0 then
    raise exception 'TEST 11b FAILED: a cancelled job was claimable';
  end if;
  raise notice 'TEST 11b PASSED: a cancelled job cannot be claimed';
end
$$;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform cancel_processing_job(fx('cancel_job_id'), 'second cancellation attempt');
    exception when others then
      v_failed := true;
    end;
    if v_failed then
      raise exception 'TEST 11c FAILED: repeated cancellation raised instead of being idempotent';
    end if;
    raise notice 'TEST 11c PASSED: repeated cancellation is idempotent';
  end
  $$;
rollback;

do $$
declare v_failed boolean := false;
begin
  begin
    perform cancel_processing_job(fx('retry_job_id'), 'attempting to cancel a dead-lettered job');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 11d FAILED: a dead_lettered job was cancellable';
  end if;
  raise notice 'TEST 11d PASSED: a dead_lettered job cannot be cancelled';
end
$$;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform cancel_processing_job(fx('claimed_job_id'), 'clinician attempt');
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 11e FAILED: clinician (lacking guideline_processing_jobs.cancel) cancelled a job';
    end if;
    raise notice 'TEST 11e PASSED: unauthorized (clinician) cancellation denied';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 12: forbidden transitions — a succeeded job cannot be started or
-- heartbeat again; a queued job cannot be completed directly (bypassing
-- claim/start).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    perform start_document_processing_job(fx('claimed_job_id'), 'test-worker-A', fxt('lease_token'));
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 12 FAILED: start succeeded on an already-succeeded job';
  end if;
  raise notice 'TEST 12 PASSED: succeeded -> processing (via start) rejected';
end
$$;

do $$
declare v_failed boolean := false;
begin
  begin
    perform heartbeat_document_processing_job(fx('claimed_job_id'), 'test-worker-A', fxt('lease_token'), 90);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 12b FAILED: heartbeat succeeded on an already-succeeded job';
  end if;
  raise notice 'TEST 12b PASSED: heartbeat on a succeeded job rejected';
end
$$;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline6_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'ORCH-QUEUED', 'Orchestration Queued Fixture');
  select test_fixture_set('version6_id', id) from create_guideline_version(fx('guideline6_id'), 'v1.0');
  select test_fixture_set('session6_id', upload_session_id), test_fixture_set('document6_id', source_document_id)
    from create_guideline_upload_session(fx('version6_id'), 'orch-queued.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('queued_job_id', processing_job_id) from complete_guideline_upload(fx('session6_id'), 'application/pdf', 1000, repeat('6', 64), null);
commit;

do $$
declare v_failed boolean := false;
begin
  begin
    perform complete_document_processing_job(fx('queued_job_id'), 'any-worker', 'any-token', '{}'::jsonb, null, gen_random_uuid());
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 12c FAILED: a queued job was completed directly, bypassing claim/start';
  end if;
  raise notice 'TEST 12c PASSED: queued -> succeeded (bypassing claim/start) rejected';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 13: clinician still cannot read processing jobs (RLS unaffected by
-- this migration); a privileged role can.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from document_processing_jobs where id = fx('claimed_job_id');
    if v_count <> 0 then
      raise exception 'TEST 13 FAILED: clinician could read a processing job';
    end if;
    raise notice 'TEST 13 PASSED: clinician still cannot read processing jobs';
  end
  $$;
rollback;

do $$
begin
  raise notice 'ALL PROCESSING ORCHESTRATION TESTS PASSED';
end
$$;

drop function fx(text);
drop function fxt(text);
drop function test_fixture_set(text, uuid);
drop function test_text_fixture_set(text, text);
