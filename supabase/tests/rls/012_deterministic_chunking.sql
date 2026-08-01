-- ============================================================================
-- Noor V1 Test Suite — Deterministic Page-Aware Chunking (Sprint 1-D3)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 012_deterministic_chunking.sql
-- Depends on 001-011 already having run in this database (migrations
-- 0001-0013 must be applied — this file covers both 0012 and 0013, the
-- same execution/review split 009+011 already tested one layer up).
--
-- Same convention as 008/009/011: explicit SELECT/EXECUTE grants at the top
-- rather than relying on the migrations' own guarded (locally no-op) grants
-- — the CI-only bug lesson from Sprint 1.2B, applied again.
-- ============================================================================

grant select on document_chunking_runs, document_chunks, document_chunk_source_spans,
  document_chunking_reviews, document_chunk_reviews, document_chunk_findings,
  document_chunking_review_events
  to authenticated;

grant execute on function
  create_clinical_domain(uuid, text, text, text),
  create_guideline_authority(uuid, text, text, text, text, text, boolean, text),
  create_guideline(uuid, uuid, uuid, text, text, text, text, text, text),
  create_guideline_version(uuid, text, text, date, date, date, date, text, text, text, text, text, text, text, text),
  create_guideline_upload_session(uuid, text, text, bigint, text, text, uuid),
  complete_guideline_upload(uuid, text, bigint, text, text, uuid),
  create_document_extraction_review(uuid, uuid),
  start_document_extraction_review(uuid, uuid),
  mark_extraction_page_reviewed(uuid, int, text, text, uuid),
  submit_document_extraction_review(uuid, text, text, text, text, uuid),
  reopen_extraction_review(uuid, text, uuid),
  invalidate_extraction_review(uuid, text, uuid),
  create_document_chunking_job(uuid, text, uuid),
  create_document_chunking_review(uuid, uuid),
  start_document_chunking_review(uuid, uuid),
  mark_chunk_reviewed(uuid, int, text, text, uuid),
  create_chunk_finding(uuid, text, text, text, int, text, text, uuid),
  submit_document_chunking_review(uuid, text, text, text, text, uuid),
  reopen_chunking_review(uuid, text, uuid),
  invalidate_document_chunking_run(uuid, text, uuid),
  get_document_embedding_readiness(uuid)
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
-- FIXTURE: synthetic reviewer/quality users (idempotent — may already exist
-- from 009/011 in this same database).
-- ----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('66666666-6666-6666-6666-666666666666', 'reviewer.alpha@example.test'),
  ('77777777-7777-7777-7777-777777777777', 'quality.alpha@example.test')
on conflict (id) do nothing;
insert into profiles (id, display_name) values
  ('66666666-6666-6666-6666-666666666666', 'Reviewer Alpha'),
  ('77777777-7777-7777-7777-777777777777', 'Quality Alpha')
on conflict (id) do nothing;
insert into organization_memberships (organization_id, user_id, role_id, status)
  select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '66666666-6666-6666-6666-666666666666', id, 'active' from roles where key = 'clinical_reviewer'
  on conflict do nothing;
insert into organization_memberships (organization_id, user_id, role_id, status)
  select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '77777777-7777-7777-7777-777777777777', id, 'active' from roles where key = 'quality_manager'
  on conflict do nothing;

-- ----------------------------------------------------------------------------
-- FIXTURE: 3 succeeded, 3-page extraction runs, reviewed by reviewer_alpha:
--   fixture 1 -> submitted 'accepted'
--   fixture 2 -> submitted 'accepted_with_warnings' (used for the reopen cascade test)
--   fixture 3 -> review left 'pending_review' (not yet submitted — proves job
--                creation is rejected until the review is final)
-- ----------------------------------------------------------------------------
do $$
declare
  v_guideline_id uuid;
  v_version_id uuid;
  v_session_id uuid;
  v_document_id uuid;
  v_job_id uuid;
  v_token text;
  v_hash text;
  v_org uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_sha text;
  v_run record;
  v_review record;
  i int;
  v_suffix text;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  perform test_fixture_set('domain_id', id) from create_clinical_domain(v_org, 'chunking-domain', 'Chunking Test Domain', null);
  perform test_fixture_set('authority_id', id) from create_guideline_authority(v_org, 'Chunking Test Authority', null, null, null, null, true, null);
  set local role none;

  foreach v_suffix in array array['1', '2', '3'] loop
    set local role authenticated;
    set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

    select id into v_guideline_id from create_guideline(v_org, fx('domain_id'), fx('authority_id'), 'CHUNK-' || v_suffix, 'Chunking Guideline ' || v_suffix);
    select id into v_version_id from create_guideline_version(v_guideline_id, 'v1.0');
    select upload_session_id, source_document_id into v_session_id, v_document_id
      from create_guideline_upload_session(v_version_id, 'chunk-fixture-' || v_suffix || '.pdf', 'application/pdf', 1000, null, null);
    v_sha := repeat('c', 63) || v_suffix;
    select processing_job_id into v_job_id from complete_guideline_upload(v_session_id, 'application/pdf', 1000, v_sha, null);
    set local role none;

    v_token := encode(gen_random_bytes(32), 'hex');
    v_hash := encode(digest(v_token, 'sha256'), 'hex');
    update document_processing_jobs set
      status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-chunk-test',
      claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
      lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
      where id = v_job_id;
    insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
      values (v_org, v_job_id, 1, 'noor-worker-chunk-test', 'started');
    perform start_document_processing_job(v_job_id, 'noor-worker-chunk-test', v_token);

    select * into v_run from create_document_extraction_run(
      v_job_id, 'noor-worker-chunk-test', v_token, v_sha, 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
    );

    for i in 1..3 loop
      insert into document_extraction_pages (
        organization_id, extraction_run_id, source_document_id, page_number,
        width_points, height_points, rotation_degrees, raw_text, normalized_text,
        character_count, word_count, is_blank, suspected_scanned, extraction_status, page_checksum
      ) values (
        v_org, v_run.out_extraction_run_id, v_document_id, i,
        595.28, 841.89, 0, 'Chunk fixture page ' || i, 'Chunk fixture page ' || i,
        20, 4, false, false, 'text_extracted', repeat(v_suffix, 60) || i::text
      );
    end loop;

    perform finalize_document_extraction_run(
      v_run.out_extraction_run_id, v_job_id, 'noor-worker-chunk-test', v_token,
      3, 'guideline-processed', 'test/path/chunk-' || v_suffix || '.json', repeat('f', 64), 100, 'application/json',
      '{}'::jsonb, 3, 0, 0, 60, 12, 0, '[]'::jsonb
    );

    perform test_fixture_set('document_' || v_suffix || '_id', v_document_id);
    perform test_fixture_set('run_' || v_suffix || '_id', v_run.out_extraction_run_id);
    perform test_text_fixture_set('sha_' || v_suffix, v_sha);

    set local role authenticated;
    set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
    select * into v_review from create_document_extraction_review(fx('run_' || v_suffix || '_id'));
    set local role none;

    set local role authenticated;
    set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
    set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
    perform start_document_extraction_review(v_review.id);
    perform mark_extraction_page_reviewed(v_review.id, 1, 'reviewed_clear', null);
    perform mark_extraction_page_reviewed(v_review.id, 2, 'reviewed_clear', null);
    perform mark_extraction_page_reviewed(v_review.id, 3, 'reviewed_clear', null);
    if v_suffix = '1' then
      perform submit_document_extraction_review(v_review.id, 'accepted', null, null);
    elsif v_suffix = '2' then
      perform submit_document_extraction_review(v_review.id, 'accepted_with_warnings', null, 'minor footer noise only');
    end if;
    -- fixture 3's review is deliberately left pending_review (never submitted).
    set local role none;

    perform test_fixture_set('review_' || v_suffix || '_id', v_review.id);
  end loop;

  raise notice 'FIXTURE READY: 3 extraction runs built (accepted / accepted_with_warnings / pending_review)';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: create_document_chunking_job succeeds for an accepted document,
-- and a second call is idempotent (reuses the queued job).
-- ---------------------------------------------------------------------------
do $$
declare r record; v_first_job uuid;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select * into r from create_document_chunking_job(fx('document_1_id'));
  v_first_job := r.out_job_id;
  if r.out_status <> 'queued' or r.out_reused then
    raise exception 'TEST 1 FAILED: expected a fresh queued job, got %', row_to_json(r);
  end if;

  select * into r from create_document_chunking_job(fx('document_1_id'));
  set local role none;

  if r.out_job_id <> v_first_job or not r.out_reused then
    raise exception 'TEST 1 FAILED: expected the active job to be reused, got %', row_to_json(r);
  end if;
  perform test_fixture_set('job_1_id', v_first_job);
  raise notice 'TEST 1 PASSED: create_document_chunking_job creates and idempotently reuses a job';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 2: create_document_chunking_job is rejected while the extraction
-- review is still pending_review (fixture 3).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  begin
    perform create_document_chunking_job(fx('document_3_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 2 FAILED: job creation succeeded for a document with a pending extraction review';
  end if;
  raise notice 'TEST 2 PASSED: chunking job creation is rejected until the extraction review is final';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 3: a clinician (no guideline_chunking.create) cannot create a
-- chunking job.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  begin
    perform create_document_chunking_job(fx('document_2_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 3 FAILED: a clinician was able to create a chunking job';
  end if;
  raise notice 'TEST 3 PASSED: clinician denied guideline_chunking.create';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 4: Worker flow — claim the document_chunking job, read the chunking
-- context (3 native pages, correct text), create the chunking run.
-- ---------------------------------------------------------------------------
do $$
declare
  v_claim record;
  v_context record;
  v_context_count int := 0;
  v_run record;
begin
  set local role none;
  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-chunk-test-1', array['document_chunking']);
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-chunk-test-1', v_claim.out_lease_token);
  perform test_fixture_set('run1_job_id', v_claim.out_job_id);
  perform test_text_fixture_set('run1_lease_token', v_claim.out_lease_token);

  for v_context in
    select * from get_document_chunking_job_context(v_claim.out_job_id, 'noor-worker-chunk-test-1', v_claim.out_lease_token)
  loop
    v_context_count := v_context_count + 1;
    if v_context.out_representation_type <> 'native' or v_context.out_normalized_text <> ('Chunk fixture page ' || v_context.out_page_number) then
      raise exception 'TEST 4 FAILED: unexpected context row %', row_to_json(v_context);
    end if;
  end loop;
  if v_context_count <> 3 then
    raise exception 'TEST 4 FAILED: expected 3 context rows, got %', v_context_count;
  end if;

  select * into v_run from create_document_chunking_run(
    v_claim.out_job_id, 'noor-worker-chunk-test-1', v_claim.out_lease_token,
    fx('run_1_id'), fx('review_1_id'), fxt('sha_1'),
    '{"schema_version":"1.0","pages":[]}'::jsonb, repeat('m', 64),
    'controlled-page-aware-chunking-v1', '1', '1', 'noor-simple-tokenizer', '1'
  );
  set local role none;

  if v_run.out_status <> 'running' or v_run.out_reused then
    raise exception 'TEST 4 FAILED: expected a fresh running chunking run, got %', row_to_json(v_run);
  end if;
  perform test_fixture_set('chunking_run_1_id', v_run.out_chunking_run_id);
  raise notice 'TEST 4 PASSED: Worker context read and chunking run creation succeed';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 5: finalize_document_chunking_run rejects a payload whose coverage
-- is not exactly 100%% (the mandatory coverage gate, migration 0012).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role none;
  begin
    perform finalize_document_chunking_run(
      fx('chunking_run_1_id'), fx('run1_job_id'), 'noor-worker-chunk-test-1', fxt('run1_lease_token'),
      '[]'::jsonb, jsonb_build_object('coverage_percentage', 87, 'duplication_percentage', 0), '[]'::jsonb,
      'guideline-processed', 'test/path/bad-coverage.json', repeat('b', 64), 10, 'application/json'
    );
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 5 FAILED: finalize succeeded despite 87%% coverage';
  end if;
  raise notice 'TEST 5 PASSED: finalize_document_chunking_run enforces the 100%% coverage gate';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 6: finalize_document_chunking_run succeeds with a correct 3-chunk
-- payload (one chunk per page), persisting chunks and source spans.
-- ---------------------------------------------------------------------------
do $$
declare
  v_page1 record; v_page2 record; v_page3 record;
  v_chunks jsonb;
  v_result record;
  v_span_count int;
begin
  select id, page_checksum into v_page1 from document_extraction_pages where extraction_run_id = fx('run_1_id') and page_number = 1;
  select id, page_checksum into v_page2 from document_extraction_pages where extraction_run_id = fx('run_1_id') and page_number = 2;
  select id, page_checksum into v_page3 from document_extraction_pages where extraction_run_id = fx('run_1_id') and page_number = 3;

  v_chunks := jsonb_build_array(
    jsonb_build_object(
      'chunk_index', 1, 'chunk_text', 'Chunk fixture page 1', 'chunk_checksum', repeat('1', 64),
      'page_start', 1, 'page_end', 1, 'token_count', 4, 'character_count', 20, 'word_count', 4,
      'heading_context', null, 'block_type_summary', '["paragraph"]'::jsonb,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 1, 'representation_type', 'native', 'representation_id', v_page1.id,
        'representation_checksum', v_page1.page_checksum, 'start_offset', 0, 'end_offset', 20,
        'source_fragment_checksum', repeat('a', 64), 'span_order', 1, 'block_type_hint', 'paragraph', 'boundary_reason', 'block_boundary'
      ))
    ),
    jsonb_build_object(
      'chunk_index', 2, 'chunk_text', 'Chunk fixture page 2', 'chunk_checksum', repeat('2', 64),
      'page_start', 2, 'page_end', 2, 'token_count', 4, 'character_count', 20, 'word_count', 4,
      'heading_context', null, 'block_type_summary', '["paragraph"]'::jsonb,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 2, 'representation_type', 'native', 'representation_id', v_page2.id,
        'representation_checksum', v_page2.page_checksum, 'start_offset', 0, 'end_offset', 20,
        'source_fragment_checksum', repeat('b', 64), 'span_order', 1, 'block_type_hint', 'paragraph', 'boundary_reason', 'block_boundary'
      ))
    ),
    jsonb_build_object(
      'chunk_index', 3, 'chunk_text', 'Chunk fixture page 3', 'chunk_checksum', repeat('3', 64),
      'page_start', 3, 'page_end', 3, 'token_count', 4, 'character_count', 20, 'word_count', 4,
      'heading_context', null, 'block_type_summary', '["paragraph"]'::jsonb,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 3, 'representation_type', 'native', 'representation_id', v_page3.id,
        'representation_checksum', v_page3.page_checksum, 'start_offset', 0, 'end_offset', 20,
        'source_fragment_checksum', repeat('c', 64), 'span_order', 1, 'block_type_hint', 'paragraph', 'boundary_reason', 'block_boundary'
      ))
    )
  );

  set local role none;
  select * into v_result from finalize_document_chunking_run(
    fx('chunking_run_1_id'), fx('run1_job_id'), 'noor-worker-chunk-test-1', fxt('run1_lease_token'),
    v_chunks, jsonb_build_object('coverage_percentage', 100, 'duplication_percentage', 0, 'page_count', 3, 'chunk_count', 3),
    '[]'::jsonb, 'guideline-processed', 'test/path/chunk-1.json', repeat('d', 64), 300, 'application/json'
  );
  set local role none;

  if v_result.out_status <> 'succeeded' or v_result.out_chunk_count <> 3 then
    raise exception 'TEST 6 FAILED: expected succeeded/3 chunks, got %', row_to_json(v_result);
  end if;
  select count(*) into v_span_count from document_chunk_source_spans where chunking_run_id = fx('chunking_run_1_id');
  if v_span_count <> 3 then
    raise exception 'TEST 6 FAILED: expected 3 source spans, got %', v_span_count;
  end if;
  raise notice 'TEST 6 PASSED: finalize_document_chunking_run persists chunks and spans and succeeds';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 7: a succeeded chunk and its source span are immutable.
-- ---------------------------------------------------------------------------
do $$
declare v_chunk_id uuid; v_failed_update boolean := false; v_failed_delete boolean := false;
begin
  select id into v_chunk_id from document_chunks where chunking_run_id = fx('chunking_run_1_id') and chunk_index = 1;
  begin
    update document_chunks set chunk_text = 'tampered' where id = v_chunk_id;
  exception when others then
    v_failed_update := true;
  end;
  begin
    delete from document_chunks where id = v_chunk_id;
  exception when others then
    v_failed_delete := true;
  end;
  if not v_failed_update or not v_failed_delete then
    raise exception 'TEST 7 FAILED: a document_chunks row was mutated or deleted';
  end if;
  raise notice 'TEST 7 PASSED: document_chunks rows are immutable';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 8: the V1 hard page-boundary policy (page_end = page_start) is a
-- real, unbypassable database constraint.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    insert into document_chunks (
      organization_id, chunking_run_id, source_document_id, chunk_index, chunk_text, chunk_checksum,
      page_start, page_end, source_span_count, token_count, character_count, word_count,
      boundary_start_reason, boundary_end_reason
    ) values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('chunking_run_1_id'), fx('document_1_id'), 999, 'x', repeat('9', 64),
      1, 2, 0, 1, 1, 1, 'page_start', 'page_end'
    );
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 8 FAILED: a chunk spanning page_start <> page_end was accepted';
  end if;
  raise notice 'TEST 8 PASSED: the hard page-boundary constraint rejects cross-page chunks';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 9: identity-based idempotent reuse — a genuinely fresh job attempt
-- (document_1's first job already succeeded, so a new create_document_chunking_job
-- call creates a second, independent job/lease — mirroring a real rechunk
-- retry) calling create_document_chunking_run with the IDENTICAL identity
-- tuple returns the existing succeeded run rather than inserting a new one.
-- ---------------------------------------------------------------------------
do $$
declare v_job record; v_claim record; v_result record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into v_job from create_document_chunking_job(fx('document_1_id'));
  set local role none;
  if v_job.out_reused then
    raise exception 'TEST 9 FAILED: expected a fresh job (the prior one already succeeded), got reused=true';
  end if;

  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-chunk-test-9', array['document_chunking']);
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-chunk-test-9', v_claim.out_lease_token);

  select * into v_result from create_document_chunking_run(
    v_claim.out_job_id, 'noor-worker-chunk-test-9', v_claim.out_lease_token,
    fx('run_1_id'), fx('review_1_id'), fxt('sha_1'),
    '{"schema_version":"1.0","pages":[]}'::jsonb, repeat('m', 64),
    'controlled-page-aware-chunking-v1', '1', '1', 'noor-simple-tokenizer', '1'
  );
  -- Mirrors what the real Worker's outer loop does when a processor
  -- reports reused=true (app/chunking/processor.py) — this job still
  -- needs to reach a terminal state even though no new row was created.
  perform complete_document_processing_job(v_claim.out_job_id, 'noor-worker-chunk-test-9', v_claim.out_lease_token,
    jsonb_build_object('chunking_run_id', v_result.out_chunking_run_id, 'reused', true));
  set local role none;

  if v_result.out_chunking_run_id <> fx('chunking_run_1_id') or not v_result.out_reused then
    raise exception 'TEST 9 FAILED: expected the succeeded run to be reused, got %', row_to_json(v_result);
  end if;
  raise notice 'TEST 9 PASSED: identical chunking identity is reused, never duplicated, even from a fresh job attempt';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 10: trust boundary — authenticated cannot call any Worker-only
-- chunking function directly.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  begin
    perform get_document_chunking_job_context(fx('run1_job_id'), 'noor-worker-chunk-test-1', fxt('run1_lease_token'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 10 FAILED: authenticated was able to call get_document_chunking_job_context';
  end if;
  raise notice 'TEST 10 PASSED: Worker-only chunking functions are unreachable from authenticated';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 11: RLS — a clinician cannot read chunking runs/chunks; an
-- organization_admin can.
-- ---------------------------------------------------------------------------
do $$
declare v_count int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  select count(*) into v_count from document_chunks where chunking_run_id = fx('chunking_run_1_id');
  if v_count <> 0 then
    raise exception 'TEST 11 FAILED: a clinician could read document_chunks';
  end if;

  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select count(*) into v_count from document_chunks where chunking_run_id = fx('chunking_run_1_id');
  set local role none;
  if v_count <> 3 then
    raise exception 'TEST 11 FAILED: organization_admin could not read the 3 expected chunks (got %)', v_count;
  end if;
  raise notice 'TEST 11 PASSED: RLS enforces guideline_chunking.read correctly';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 12: full chunk technical review lifecycle (migration 0013) — create,
-- mark all 3 chunks reviewed_clear, submit accepted; embedding readiness
-- becomes true only after acceptance, never before.
-- ---------------------------------------------------------------------------
do $$
declare v_review record; v_readiness record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into v_readiness from get_document_embedding_readiness(fx('document_1_id'));
  if v_readiness.out_eligible_for_embedding then
    raise exception 'TEST 12 FAILED: embedding readiness was true before any chunk review existed';
  end if;

  select * into v_review from create_document_chunking_review(fx('chunking_run_1_id'));
  set local role none;
  perform test_fixture_set('chunking_review_1_id', v_review.id);

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_chunking_review(v_review.id);
  perform mark_chunk_reviewed(v_review.id, 1, 'reviewed_clear', null);
  perform mark_chunk_reviewed(v_review.id, 2, 'reviewed_clear', null);
  perform mark_chunk_reviewed(v_review.id, 3, 'reviewed_clear', null);
  select * into v_review from submit_document_chunking_review(v_review.id, 'accepted', null, null);
  set local role none;

  if v_review.review_status <> 'accepted' then
    raise exception 'TEST 12 FAILED: expected accepted, got %', row_to_json(v_review);
  end if;

  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into v_readiness from get_document_embedding_readiness(fx('document_1_id'));
  set local role none;
  if not v_readiness.out_eligible_for_embedding or v_readiness.out_eligible_for_retrieval then
    raise exception 'TEST 12 FAILED: unexpected readiness after acceptance: %', row_to_json(v_readiness);
  end if;
  raise notice 'TEST 12 PASSED: chunk review lifecycle and embedding readiness (accepted) work correctly';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 13: submitting before all chunks are reviewed is rejected.
-- ---------------------------------------------------------------------------
do $$
declare v_run record; v_context record; v_review record; v_failed boolean := false;
declare v_job record;
begin
  -- Build a second succeeded chunking run (fixture 2) to exercise this
  -- independently of fixture 1's already-accepted review.
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  perform create_document_chunking_job(fx('document_2_id'));
  set local role none;

  select out_job_id, out_lease_token into v_job
    from claim_next_document_processing_job('noor-worker-chunk-test-2', array['document_chunking']);
  perform start_document_processing_job(v_job.out_job_id, 'noor-worker-chunk-test-2', v_job.out_lease_token);

  select * into v_run from create_document_chunking_run(
    v_job.out_job_id, 'noor-worker-chunk-test-2', v_job.out_lease_token,
    fx('run_2_id'), fx('review_2_id'), fxt('sha_2'),
    '{"schema_version":"1.0","pages":[]}'::jsonb, repeat('n', 64),
    'controlled-page-aware-chunking-v1', '1', '1', 'noor-simple-tokenizer', '1'
  );

  perform finalize_document_chunking_run(
    v_run.out_chunking_run_id, v_job.out_job_id, 'noor-worker-chunk-test-2', v_job.out_lease_token,
    jsonb_build_array(jsonb_build_object(
      'chunk_index', 1, 'chunk_text', 'x', 'chunk_checksum', repeat('e', 64),
      'page_start', 1, 'page_end', 1, 'token_count', 1, 'character_count', 1, 'word_count', 1,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 1, 'representation_type', 'native',
        'representation_id', (select id from document_extraction_pages where extraction_run_id = fx('run_2_id') and page_number = 1),
        'representation_checksum', (select page_checksum from document_extraction_pages where extraction_run_id = fx('run_2_id') and page_number = 1),
        'start_offset', 0, 'end_offset', 1, 'source_fragment_checksum', repeat('f', 64), 'span_order', 1
      ))
    )),
    jsonb_build_object('coverage_percentage', 100, 'duplication_percentage', 0), '[]'::jsonb,
    'guideline-processed', 'test/path/chunk-2.json', repeat('e', 64), 100, 'application/json'
  );
  set local role none;
  perform test_fixture_set('chunking_run_2_id', v_run.out_chunking_run_id);

  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_review from create_document_chunking_review(v_run.out_chunking_run_id);
  perform start_document_chunking_review(v_review.id);
  begin
    perform submit_document_chunking_review(v_review.id, 'accepted', null, null);
  exception when others then
    v_failed := true;
  end;
  set local role none;

  if not v_failed then
    raise exception 'TEST 13 FAILED: submission succeeded despite 0 of 1 chunks reviewed';
  end if;
  perform test_fixture_set('chunking_review_2_id', v_review.id);
  raise notice 'TEST 13 PASSED: submission rejected until every chunk is reviewed';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 14: rechunk_required requires a supporting finding and a reason, and
-- keeps embedding readiness false.
-- ---------------------------------------------------------------------------
do $$
declare v_review record; v_readiness record; v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  begin
    perform submit_document_chunking_review(fx('chunking_review_2_id'), 'rechunk_required', 'boundary looks wrong', null);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 14 FAILED: rechunk_required was accepted without any finding';
  end if;

  perform create_chunk_finding(fx('chunking_review_2_id'), 'boundary_splits_sentence', 'major', 'Chunk cuts mid-sentence', 1, 'Boundary looks unsafe', 'rechunk with adjusted target size');
  perform mark_chunk_reviewed(fx('chunking_review_2_id'), 1, 'rechunk_candidate', null);
  select * into v_review from submit_document_chunking_review(fx('chunking_review_2_id'), 'rechunk_required', 'boundary cuts mid-sentence, needs adjustment', null);

  if v_review.review_status <> 'rechunk_required' then
    raise exception 'TEST 14 FAILED: expected rechunk_required, got %', row_to_json(v_review);
  end if;
  select * into v_readiness from get_document_embedding_readiness(fx('document_2_id'));
  set local role none;
  if v_readiness.out_eligible_for_embedding then
    raise exception 'TEST 14 FAILED: embedding readiness was true after rechunk_required';
  end if;
  raise notice 'TEST 14 PASSED: rechunk_required requires evidence and blocks embedding readiness';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 15: reopen_chunking_review starts a new round; embedding readiness
-- for the still-accepted fixture 1 review is unaffected by fixture 2's round.
-- ---------------------------------------------------------------------------
do $$
declare v_readiness record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into v_readiness from get_document_embedding_readiness(fx('document_1_id'));
  set local role none;
  if not v_readiness.out_eligible_for_embedding then
    raise exception 'TEST 15 FAILED: fixture 1 embedding readiness regressed: %', row_to_json(v_readiness);
  end if;
  raise notice 'TEST 15 PASSED: chunk review rounds are correctly scoped per chunking run';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 16: reopening the underlying EXTRACTION review cascades into
-- invalidating the dependent, still-succeeded chunking run (fixture 2, which
-- has a succeeded chunking run even though its review round ended in
-- rechunk_required) — the same cascade discipline 011 added for OCR, one
-- layer downstream.
-- ---------------------------------------------------------------------------
do $$
declare v_status text; v_readiness record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  perform reopen_extraction_review(fx('review_2_id'), 'reprocessing needed upstream, cascading to chunking');

  select status into v_status from document_chunking_runs where id = fx('chunking_run_2_id');
  if v_status <> 'invalidated' then
    raise exception 'TEST 16 FAILED: expected the dependent chunking run invalidated, got %', v_status;
  end if;

  select * into v_readiness from get_document_embedding_readiness(fx('document_2_id'));
  set local role none;
  if v_readiness.out_eligible_for_embedding then
    raise exception 'TEST 16 FAILED: embedding readiness was true after upstream invalidation';
  end if;
  raise notice 'TEST 16 PASSED: reopening the extraction review cascades to invalidate the dependent chunking run';
end
$$;

do $$
begin
  raise notice 'ALL DETERMINISTIC CHUNKING TESTS PASSED';
end
$$;

drop function fx(text);
drop function fxt(text);
drop function test_fixture_set(text, uuid);
drop function test_text_fixture_set(text, text);
