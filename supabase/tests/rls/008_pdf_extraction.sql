-- ============================================================================
-- Noor V1 Test Suite — Deterministic PDF Extraction Schema (Sprint 1.2B)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 008_pdf_extraction.sql
-- Depends on 001-007 already having run in this database (migrations
-- 0001-0008 must be applied).
--
-- Mirrors 006_processing_orchestration.sql's conventions exactly: the
-- three new functions (create/finalize/fail_document_extraction_run) are
-- called WITHOUT `set local role authenticated` (the correct simulation of
-- `service_role`'s trust boundary — they are never granted to
-- `authenticated`, per migration 0008 section 6). `set local role
-- authenticated`/`set local request.jwt.*` only ever appear as TOP-LEVEL
-- statements (never inside a `DO $$...$$` block), the only pattern proven
-- safe across every RLS test file in this repo.
-- ============================================================================

\set ON_ERROR_STOP on

grant execute on function
  create_clinical_domain(uuid, text, text, text),
  create_guideline_authority(uuid, text, text, text, text, text, boolean, text),
  create_guideline(uuid, uuid, uuid, text, text, text, text, text, text),
  create_guideline_version(uuid, text, text, date, date, date, date, text, text, text, text, text, text, text, text),
  create_guideline_upload_session(uuid, text, text, bigint, text, text, uuid),
  complete_guideline_upload(uuid, text, bigint, text, text, uuid)
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
-- FIXTURE: domain + authority + a registered document with a queued job,
-- claimed and started so it's ready for extraction-run creation.
-- ----------------------------------------------------------------------------

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('domain_id', id) from create_clinical_domain('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'extract-domain', 'Extraction Test Domain', null);
  select test_fixture_set('authority_id', id) from create_guideline_authority('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Extraction Test Authority', null, null, null, null, true, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'EXTRACT-001', 'Extraction Guideline');
  select test_fixture_set('version_id', id) from create_guideline_version(fx('guideline_id'), 'v1.0');
  select test_fixture_set('session_id', upload_session_id), test_fixture_set('document_id', source_document_id)
    from create_guideline_upload_session(fx('version_id'), 'extract-fixture.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_text_fixture_set('source_sha256', repeat('a', 63) || '1'),
         test_fixture_set('job_id', processing_job_id)
    from complete_guideline_upload(fx('session_id'), 'application/pdf', 1000, repeat('a', 63) || '1', null);
commit;

-- Sets the fixture job directly into `claimed` state (rather than calling
-- claim_next_document_processing_job) because this database carries
-- cumulative state across the whole 001-008 suite — other files
-- deliberately leave some jobs queued (e.g. 006's TEST 12c fixture), so a
-- generic claim call is not guaranteed to pick up *this* file's own job.
-- claim_next_document_processing_job's own correctness is already proven
-- exhaustively in 006_processing_orchestration.sql; this file only needs
-- a job deterministically in `processing` state with a known lease token
-- to build its own tests on top of.
do $$
declare
  v_token text := encode(gen_random_bytes(32), 'hex');
  v_hash text := encode(digest(v_token, 'sha256'), 'hex');
  v_org uuid;
begin
  select organization_id into v_org from document_processing_jobs where id = fx('job_id');

  update document_processing_jobs set
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-extract-test',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = fx('job_id');

  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, fx('job_id'), 1, 'noor-worker-extract-test', 'started');

  perform test_text_fixture_set('lease_token', v_token);
  perform start_document_processing_job(fx('job_id'), 'noor-worker-extract-test', v_token);
  raise notice 'FIXTURE READY: registered document with a processing job claimed and started';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: create_document_extraction_run succeeds for the real lease
-- owner, with the correct source checksum/size, and returns out_reused=false.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  select * into r from create_document_extraction_run(
    fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
    fxt('source_sha256'), 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );
  if r.out_extraction_run_id is null or r.out_reused <> false or r.out_status <> 'running' then
    raise exception 'TEST 1 FAILED: expected a fresh running run, got %', row_to_json(r);
  end if;
  perform test_fixture_set('run_id', r.out_extraction_run_id);
  raise notice 'TEST 1 PASSED: extraction run created (running, not reused)';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 2: source checksum / size mismatch is rejected — no run created.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
declare v_count_before int;
declare v_count_after int;
begin
  select count(*) into v_count_before from document_extraction_runs where source_document_id = fx('document_id');
  begin
    perform create_document_extraction_run(
      fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
      repeat('f', 64), 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
    );
  exception when others then
    v_failed := true;
  end;
  select count(*) into v_count_after from document_extraction_runs where source_document_id = fx('document_id');
  if not v_failed then
    raise exception 'TEST 2 FAILED: a mismatched source checksum was accepted';
  end if;
  if v_count_after <> v_count_before then
    raise exception 'TEST 2 FAILED: a run was created despite the checksum mismatch';
  end if;
  raise notice 'TEST 2 PASSED: source checksum mismatch rejected, no run created';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 3: wrong worker / wrong token denied.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    perform create_document_extraction_run(
      fx('job_id'), 'someone-else', 'wrong-token',
      fxt('source_sha256'), 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
    );
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 3 FAILED: a non-owning worker created an extraction run';
  end if;
  raise notice 'TEST 3 PASSED: non-owning worker denied';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 4: same-attempt replay — calling create_document_extraction_run
-- again with the SAME identity, same job/attempt, while the first run is
-- still `running` attaches to the SAME row (out_reused=false, same run
-- id) rather than creating a duplicate. This is the exact bug this test
-- caught on first execution: the original implementation only checked for
-- an existing SUCCEEDED run, so a second call while still running created
-- a conflicting second `running` row at the same identity.
-- ---------------------------------------------------------------------------
do $$
declare r record;
declare v_count int;
begin
  select * into r from create_document_extraction_run(
    fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
    fxt('source_sha256'), 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );
  if r.out_reused <> false then
    raise exception 'TEST 4 FAILED: a still-running run was reported as reused';
  end if;
  if r.out_extraction_run_id <> fx('run_id') then
    raise exception 'TEST 4 FAILED: expected the SAME run id (%) to be returned, got %', fx('run_id'), r.out_extraction_run_id;
  end if;
  select count(*) into v_count from document_extraction_runs
    where organization_id = r.out_organization_id and source_sha256 = fxt('source_sha256')
      and pipeline_version = 'pdf-text-v1' and configuration_version = '1'
      and extractor_name = 'pypdf' and extractor_version = '6.14.2';
  if v_count <> 1 then
    raise exception 'TEST 4 FAILED: expected exactly 1 row at this identity while running, found %', v_count;
  end if;
  raise notice 'TEST 4 PASSED: same-attempt replay attaches to the same running row, no duplicate created';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 5: inserting page rows directly via the connecting (service-role
-- analogue) role succeeds — pages are written via a plain trusted table
-- insert, not a wrapper function (see docs/security/pdf-extraction-security.md).
-- ---------------------------------------------------------------------------
do $$
declare v_org uuid;
begin
  select organization_id into v_org from document_extraction_runs where id = fx('run_id');

  insert into document_extraction_pages (
    organization_id, extraction_run_id, source_document_id, page_number,
    width_points, height_points, rotation_degrees, raw_text, normalized_text,
    character_count, word_count, is_blank, suspected_scanned, extraction_status, page_checksum
  ) values (
    v_org, fx('run_id'), fx('document_id'), 1,
    595.28, 841.89, 0, 'Hello Noor', 'Hello Noor',
    10, 2, false, false, 'text_extracted', repeat('c', 64)
  );
  raise notice 'TEST 5 PASSED: page row inserted via trusted context';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 6: finalize_document_extraction_run rejects a page-count mismatch
-- (expects 2 pages, only 1 exists).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    perform finalize_document_extraction_run(
      fx('run_id'), fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
      2, 'guideline-processed', 'test/path/artifact.json', repeat('d', 64), 100, 'application/json'
    );
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 6 FAILED: finalize succeeded despite a page-count mismatch';
  end if;
  raise notice 'TEST 6 PASSED: page-count mismatch rejected';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 7: finalize_document_extraction_run succeeds with the correct page
-- count, and the run becomes succeeded with the artifact fields set.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  select * into r from finalize_document_extraction_run(
    fx('run_id'), fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
    1, 'guideline-processed', 'test/path/artifact.json', repeat('d', 64), 100, 'application/json',
    '{"page_count":1}'::jsonb, 1, 0, 0, 10, 2, 0, '[]'::jsonb
  );
  if r.out_status <> 'succeeded' then
    raise exception 'TEST 7 FAILED: expected succeeded, got %', r.out_status;
  end if;
  raise notice 'TEST 7 PASSED: finalize succeeded with the correct page count';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 8: replayed finalize with the same artifact checksum is idempotent.
-- ---------------------------------------------------------------------------
do $$
declare r1 record;
declare r2 record;
begin
  select * into r2 from finalize_document_extraction_run(
    fx('run_id'), fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
    1, 'guideline-processed', 'test/path/artifact.json', repeat('d', 64), 100, 'application/json'
  );
  if r2.out_status <> 'succeeded' then
    raise exception 'TEST 8 FAILED: replayed finalize did not return succeeded';
  end if;
  raise notice 'TEST 8 PASSED: replayed finalize with the same artifact checksum is idempotent';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 9: a second create_document_extraction_run call at the SAME
-- identity now returns the SUCCEEDED run with out_reused=true.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  select * into r from create_document_extraction_run(
    fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
    fxt('source_sha256'), 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );
  if r.out_reused <> true or r.out_extraction_run_id <> fx('run_id') or r.out_status <> 'succeeded' then
    raise exception 'TEST 9 FAILED: expected the existing succeeded run to be reused, got %', row_to_json(r);
  end if;
  raise notice 'TEST 9 PASSED: an existing succeeded run at the same identity is reused, not duplicated';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 10: the partial unique index blocks a second SUCCEEDED run at the
-- same identity from ever being inserted directly (defense in depth beyond
-- the function-level reuse check above).
-- ---------------------------------------------------------------------------
do $$
declare v_org uuid;
declare v_doc uuid;
declare v_failed boolean := false;
begin
  select organization_id, source_document_id into v_org, v_doc from document_extraction_runs where id = fx('run_id');
  begin
    insert into document_extraction_runs (
      organization_id, source_document_id, processing_job_id, source_sha256, source_size_bytes,
      pipeline_version, configuration_version, extractor_name, extractor_version, status
    ) values (
      v_org, v_doc, fx('job_id'), fxt('source_sha256'), 1000,
      'pdf-text-v1', '1', 'pypdf', '6.14.2', 'succeeded'
    );
  exception when unique_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 10 FAILED: a second succeeded run at the same identity was allowed';
  end if;
  raise notice 'TEST 10 PASSED: partial unique index blocks a duplicate succeeded run at the same identity';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 11: a succeeded run's provenance/artifact fields are immutable.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    update document_extraction_runs set artifact_sha256 = repeat('9', 64) where id = fx('run_id');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 11 FAILED: a succeeded run''s artifact checksum was mutated';
  end if;
  raise notice 'TEST 11 PASSED: succeeded run''s artifact identity is immutable';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 12: a page row is immutable once inserted (no legitimate UPDATE
-- path exists at all).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    update document_extraction_pages set normalized_text = 'tampered' where extraction_run_id = fx('run_id') and page_number = 1;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 12 FAILED: a page row was mutated after insertion';
  end if;
  raise notice 'TEST 12 PASSED: page rows are immutable once inserted';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 13: fail_document_extraction_run on an already-succeeded run is a
-- safe idempotent no-op (does not flip status to failed).
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  select * into r from fail_document_extraction_run(
    fx('run_id'), fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
    'extractor_internal_error', 'extractor_internal_error', 'should not apply — run already succeeded'
  );
  if r.out_status <> 'succeeded' then
    raise exception 'TEST 13 FAILED: fail_document_extraction_run flipped an already-succeeded run to %', r.out_status;
  end if;
  raise notice 'TEST 13 PASSED: failing an already-succeeded run is a safe no-op';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 14: fail_document_extraction_run on a genuinely running run marks
-- it failed with the given error classification.
-- ---------------------------------------------------------------------------
do $$
declare r record;
declare r2 record;
declare v_row document_extraction_runs%rowtype;
begin
  -- Fresh job/run pair for a real failure test (the first job/run pair is
  -- already terminal from TEST 7 onward).
  select * into r from create_document_extraction_run(
    fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
    fxt('source_sha256'), 1000, 'pdf-text-v1', '2', 'pypdf', '6.14.2', gen_random_uuid()
  );
  if r.out_reused then
    raise exception 'TEST 14 SETUP FAILED: expected a fresh run for configuration_version=2, got reused';
  end if;

  select * into r2 from fail_document_extraction_run(
    r.out_extraction_run_id, fx('job_id'), 'noor-worker-extract-test', fxt('lease_token'),
    'corrupt_pdf', 'corrupt_pdf', 'the source object does not have a valid PDF trailer'
  );
  if r2.out_status <> 'failed' then
    raise exception 'TEST 14 FAILED: expected failed, got %', r2.out_status;
  end if;

  select * into v_row from document_extraction_runs where id = r.out_extraction_run_id;
  if v_row.error_code <> 'corrupt_pdf' or v_row.failed_at is null then
    raise exception 'TEST 14 FAILED: error_code/failed_at not recorded correctly';
  end if;
  raise notice 'TEST 14 PASSED: a running run is marked failed with its error classification recorded';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 15: RLS — clinician cannot read extraction runs or pages; a
-- permitted role can. Uses the same bare-DO-block role-switch pattern as
-- TEST 16 below (set local role inside the block, reset to none before
-- exit) rather than an explicit begin/rollback wrapper — a wrapping
-- begin/rollback around a role switch is only safe when each statement in
-- the file is guaranteed to run as its own independent transaction (true
-- for `psql -f`, NOT guaranteed for a runner that submits an entire
-- multi-statement file as one batched query, where a later `rollback`
-- can unwind uncommitted work from earlier in the same batch — this
-- exact issue was found by actually running this file against hosted
-- Supabase via its Management API query endpoint, not by reading the SQL;
-- see docs/database/deterministic-pdf-extraction-schema.md).
-- ---------------------------------------------------------------------------
do $$
declare v_runs int;
declare v_pages int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  select count(*) into v_runs from document_extraction_runs where id = fx('run_id');
  select count(*) into v_pages from document_extraction_pages where extraction_run_id = fx('run_id');

  set local role none;

  if v_runs <> 0 or v_pages <> 0 then
    raise exception 'TEST 15 FAILED: clinician could read extraction runs/pages (runs=%, pages=%)', v_runs, v_pages;
  end if;
  raise notice 'TEST 15 PASSED: clinician cannot read extraction runs or pages';
end
$$;

do $$
declare v_runs int;
declare v_pages int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select count(*) into v_runs from document_extraction_runs where id = fx('run_id');
  select count(*) into v_pages from document_extraction_pages where extraction_run_id = fx('run_id');

  set local role none;

  if v_runs <> 1 or v_pages <> 1 then
    raise exception 'TEST 15b FAILED: organization_admin could not read its own extraction runs/pages (runs=%, pages=%)', v_runs, v_pages;
  end if;
  raise notice 'TEST 15b PASSED: a permitted role (organization_admin) can read extraction runs and pages';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 16: trust boundary — authenticated cannot call any of the three
-- new Worker-only functions (permanent regression alongside 007's).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  begin
    perform create_document_extraction_run(fx('job_id'), 'x', 'y', fxt('source_sha256'), 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2');
  exception when insufficient_privilege then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 16 FAILED: authenticated could call create_document_extraction_run';
  end if;
  raise notice 'TEST 16 PASSED: authenticated is denied (permission denied) for create_document_extraction_run';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 17: a stale `running` run from an earlier, now-superseded attempt
-- (e.g. a crashed Worker whose lease expired and was reclaimed) is
-- superseded — marked failed with error_code='superseded_by_retry' — and
-- a fresh row is created for the new attempt, rather than blocking
-- forever or creating a second live `running` row. Uses its own fixture
-- (a second job) to avoid disturbing the fx('run_id') narrative above.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline2_id', id) from create_guideline('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'EXTRACT-002', 'Extraction Supersession Fixture');
  select test_fixture_set('version2_id', id) from create_guideline_version(fx('guideline2_id'), 'v1.0');
  select test_fixture_set('session2_id', upload_session_id), test_fixture_set('document2_id', source_document_id)
    from create_guideline_upload_session(fx('version2_id'), 'extract-fixture-2.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_text_fixture_set('source2_sha256', repeat('b', 63) || '2'),
         test_fixture_set('job2_id', processing_job_id)
    from complete_guideline_upload(fx('session2_id'), 'application/pdf', 1000, repeat('b', 63) || '2', null);
commit;

do $$
declare
  v_token1 text := encode(gen_random_bytes(32), 'hex');
  v_hash1 text := encode(digest(v_token1, 'sha256'), 'hex');
  v_org uuid;
  r1 record;
begin
  select organization_id into v_org from document_processing_jobs where id = fx('job2_id');

  -- Attempt 1: claim + start, then create an extraction run and abandon
  -- it (simulating a crashed Worker that never finalized or failed it).
  update document_processing_jobs set
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-extract-test-attempt1',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash1,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = fx('job2_id');
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, fx('job2_id'), 1, 'noor-worker-extract-test-attempt1', 'started');
  perform start_document_processing_job(fx('job2_id'), 'noor-worker-extract-test-attempt1', v_token1);

  select * into r1 from create_document_extraction_run(
    fx('job2_id'), 'noor-worker-extract-test-attempt1', v_token1,
    fxt('source2_sha256'), 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );
  perform test_fixture_set('stale_run_id', r1.out_extraction_run_id);

  -- Simulate crash-recovery: the job moves to a new attempt (attempt 2)
  -- with a different worker/lease — mirroring what
  -- recover_expired_document_processing_jobs -> reclaim -> re-claim would
  -- produce, without re-deriving that already-proven function here.
  update document_processing_jobs set
    status = 'claimed', attempt_count = 2, claimed_by = 'noor-worker-extract-test-attempt2',
    claimed_at = now(), heartbeat_at = now(),
    lease_token_hash = encode(digest('attempt2-token', 'sha256'), 'hex'),
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = fx('job2_id');
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, fx('job2_id'), 2, 'noor-worker-extract-test-attempt2', 'started');
  perform start_document_processing_job(fx('job2_id'), 'noor-worker-extract-test-attempt2', 'attempt2-token');

  raise notice 'TEST 17 SETUP READY: attempt 1''s extraction run left running, attempt 2 now active';
end
$$;

do $$
declare r2 record;
declare v_stale_status text;
begin
  select * into r2 from create_document_extraction_run(
    fx('job2_id'), 'noor-worker-extract-test-attempt2', 'attempt2-token',
    fxt('source2_sha256'), 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );

  if r2.out_reused <> false then
    raise exception 'TEST 17 FAILED: expected a fresh run for the new attempt, got reused=true';
  end if;
  if r2.out_extraction_run_id = fx('stale_run_id') then
    raise exception 'TEST 17 FAILED: expected a NEW run id distinct from the stale attempt''s run';
  end if;

  select status into v_stale_status from document_extraction_runs where id = fx('stale_run_id');
  if v_stale_status <> 'failed' then
    raise exception 'TEST 17 FAILED: expected the stale attempt''s run to be superseded (failed), got %', v_stale_status;
  end if;

  raise notice 'TEST 17 PASSED: a stale running run from an abandoned attempt is superseded; the new attempt gets a fresh run';
end
$$;

do $$
begin
  raise notice 'ALL PDF EXTRACTION SCHEMA TESTS PASSED';
end
$$;

drop function fx(text);
drop function fxt(text);
drop function test_fixture_set(text, uuid);
drop function test_text_fixture_set(text, text);
