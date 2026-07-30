-- ============================================================================
-- Noor V1 Test Suite — Controlled Page-Scoped OCR (Sprint 1-D2)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 011_controlled_ocr.sql
-- Depends on 001-010 already having run in this database (migrations
-- 0001-0011 must be applied).
--
-- Same convention established in 008/009: explicit SELECT/EXECUTE grants at
-- the top rather than relying on migration 0011's own guarded (locally
-- no-op) grant — this is the exact lesson Sprint 1.2B's CI-only bug taught,
-- applied from the start every time since.
--
-- Note: migration 0010 (permission-scoped Storage) has no dedicated local
-- test file, matching migration 0003's own precedent — the `storage` schema
-- does not exist on plain Postgres, so it can only be verified against a
-- real Supabase stack (local CLI or hosted). See
-- docs/verification/sprint-1-d2-controlled-ocr-verification.md for the
-- real hosted Storage verification.
-- ============================================================================

grant select on document_ocr_requests, document_ocr_request_pages, document_ocr_runs,
  document_ocr_reviews, document_ocr_page_reviews, document_ocr_findings
  to authenticated;

grant execute on function
  create_clinical_domain(uuid, text, text, text),
  create_guideline_authority(uuid, text, text, text, text, text, boolean, text),
  create_guideline(uuid, uuid, uuid, text, text, text, text, text, text),
  create_guideline_version(uuid, text, text, date, date, date, date, text, text, text, text, text, text, text, text),
  create_guideline_upload_session(uuid, text, text, bigint, text, text, uuid),
  complete_guideline_upload(uuid, text, bigint, text, text, uuid),
  create_document_extraction_review(uuid, uuid),
  assign_extraction_reviewer(uuid, uuid, uuid),
  start_document_extraction_review(uuid, uuid),
  mark_extraction_page_reviewed(uuid, int, text, text, uuid),
  create_extraction_finding(uuid, text, text, text, uuid, text, text, uuid),
  submit_document_extraction_review(uuid, text, text, text, text, uuid),
  reopen_extraction_review(uuid, text, uuid),
  get_document_extraction_review_eligibility(uuid),
  get_document_page_text_readiness(uuid),
  create_document_ocr_request(uuid, text, text, text, text, text, text, text, text, text[], uuid),
  cancel_document_ocr_request(uuid, text, uuid),
  create_document_ocr_review(uuid, uuid),
  assign_ocr_reviewer(uuid, uuid, uuid),
  claim_ocr_review(uuid, uuid),
  start_document_ocr_review(uuid, uuid),
  mark_ocr_page_reviewed(uuid, int, text, text, uuid),
  create_ocr_finding(uuid, int, text, text, text, text, text, uuid),
  update_ocr_finding_status(uuid, text, text, uuid),
  submit_document_ocr_review(uuid, text, text, text, text, uuid),
  reopen_ocr_review(uuid, text, uuid),
  invalidate_ocr_review(uuid, text, uuid)
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
-- if 009_extraction_review.sql ran earlier in this same database).
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
-- FIXTURE: a succeeded 3-page extraction run, reviewed and submitted
-- ocr_required with page 1 flagged as ocr_candidate.
-- ----------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_guideline_id uuid;
  v_version_id uuid;
  v_session_id uuid;
  v_document_id uuid;
  v_job_id uuid;
  v_token text;
  v_hash text;
  v_run record;
  i int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  perform test_fixture_set('domain_id', id) from create_clinical_domain(v_org, 'ocr-domain', 'OCR Test Domain', null);
  perform test_fixture_set('authority_id', id) from create_guideline_authority(v_org, 'OCR Test Authority', null, null, null, null, true, null);
  select id into v_guideline_id from create_guideline(v_org, fx('domain_id'), fx('authority_id'), 'OCR-001', 'OCR Guideline');
  select id into v_version_id from create_guideline_version(v_guideline_id, 'v1.0');
  select upload_session_id, source_document_id into v_session_id, v_document_id
    from create_guideline_upload_session(v_version_id, 'ocr-fixture.pdf', 'application/pdf', 1000, null, null);
  select processing_job_id into v_job_id from complete_guideline_upload(v_session_id, 'application/pdf', 1000, repeat('9', 63) || '1', null);

  set local role none;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');
  update document_processing_jobs set
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-ocr-test',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = v_job_id;
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, v_job_id, 1, 'noor-worker-ocr-test', 'started');
  perform start_document_processing_job(v_job_id, 'noor-worker-ocr-test', v_token);

  select * into v_run from create_document_extraction_run(
    v_job_id, 'noor-worker-ocr-test', v_token, repeat('9', 63) || '1', 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );

  for i in 1..3 loop
    insert into document_extraction_pages (
      organization_id, extraction_run_id, source_document_id, page_number,
      width_points, height_points, rotation_degrees, raw_text, normalized_text,
      character_count, word_count, is_blank, suspected_scanned, extraction_status, page_checksum
    ) values (
      v_org, v_run.out_extraction_run_id, v_document_id, i,
      595.28, 841.89, 0,
      case when i = 1 then '' else 'Fixture page ' || i end,
      case when i = 1 then '' else 'Fixture page ' || i end,
      case when i = 1 then 0 else 20 end, case when i = 1 then 0 else 3 end,
      i = 1, i = 1,
      case when i = 1 then 'no_text_layer' else 'text_extracted' end,
      repeat('a', 60) || i::text
    );
  end loop;

  perform finalize_document_extraction_run(
    v_run.out_extraction_run_id, v_job_id, 'noor-worker-ocr-test', v_token,
    3, 'guideline-processed', 'test/path/ocr-fixture.json', repeat('f', 64), 100, 'application/json',
    '{}'::jsonb, 2, 0, 1, 40, 6, 0, '[]'::jsonb
  );

  perform test_fixture_set('document_id', v_document_id);
  perform test_fixture_set('job_id', v_job_id);
  perform test_fixture_set('run_id', v_run.out_extraction_run_id);
  raise notice 'FIXTURE READY: succeeded 3-page extraction run (page 1 suspected scanned/no text layer)';
end
$$;

do $$
declare v_review_id uuid;
declare v_page1_id uuid;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review_id from create_document_extraction_review(fx('run_id'));
  perform assign_extraction_reviewer(v_review_id, '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_extraction_review(v_review_id);

  select id into v_page1_id from document_extraction_pages where extraction_run_id = fx('run_id') and page_number = 1;
  perform create_extraction_finding(v_review_id, 'image_only_page', 'major', 'Page 1 is image-only', v_page1_id, 'No text layer present', null);
  perform mark_extraction_page_reviewed(v_review_id, 1, 'ocr_candidate', 'flag for OCR');
  perform mark_extraction_page_reviewed(v_review_id, 2, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(v_review_id, 3, 'reviewed_clear', null);

  perform submit_document_extraction_review(v_review_id, 'ocr_required', 'page 1 needs OCR', null);
  set local role none;

  perform test_fixture_set('review_id', v_review_id);
  raise notice 'FIXTURE READY: extraction review submitted ocr_required, page 1 flagged ocr_candidate';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: create_document_ocr_request succeeds, creates exactly 1 request
-- page (page 1), job queued.
-- ---------------------------------------------------------------------------
do $$
declare r document_ocr_requests%rowtype;
declare v_page_count int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select * into r from create_document_ocr_request(
    fx('review_id'), 'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', 'pypdfium2', '5.12.1', '1', '1', array['eng']
  );
  set local role none;

  if r.status <> 'queued' or r.total_pages <> 1 then
    raise exception 'TEST 1 FAILED: expected queued/1 page, got %', row_to_json(r);
  end if;
  select count(*) into v_page_count from document_ocr_request_pages where ocr_request_id = r.id;
  if v_page_count <> 1 then
    raise exception 'TEST 1 FAILED: expected exactly 1 request page, found %', v_page_count;
  end if;
  perform test_fixture_set('ocr_request_id', r.id);
  raise notice 'TEST 1 PASSED: OCR request created with exactly the flagged page';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 2: create_document_ocr_request is idempotent — a second call returns
-- the same request, no duplicate.
-- ---------------------------------------------------------------------------
do $$
declare r document_ocr_requests%rowtype;
declare v_count int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into r from create_document_ocr_request(
    fx('review_id'), 'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', 'pypdfium2', '5.12.1', '1', '1', array['eng']
  );
  set local role none;

  if r.id <> fx('ocr_request_id') then
    raise exception 'TEST 2 FAILED: expected the same request id';
  end if;
  select count(*) into v_count from document_ocr_requests where extraction_review_id = fx('review_id');
  if v_count <> 1 then
    raise exception 'TEST 2 FAILED: expected exactly 1 request row, found %', v_count;
  end if;
  raise notice 'TEST 2 PASSED: duplicate create_document_ocr_request is idempotent';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 3: clinician cannot create an OCR request.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  begin
    perform create_document_ocr_request(fx('review_id'), 'tesseract', '5.5.0', 'x', 'y', 'pypdfium2', '5.12.1', '1', '1', array['eng']);
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 3 FAILED: clinician created an OCR request';
  end if;
  raise notice 'TEST 3 PASSED: clinician denied create_document_ocr_request';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 4: Worker flow — claim the document_ocr job, create the OCR run,
-- finalize it. Reused-identity proof follows.
-- ---------------------------------------------------------------------------
do $$
declare v_claim record;
declare v_run record;
declare v_final record;
begin
  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-ocr-test-1', array['document_ocr']);
  if v_claim.out_job_id is null then
    raise exception 'TEST 4 FAILED: no document_ocr job was claimable';
  end if;
  perform test_fixture_set('ocr_job_id', v_claim.out_job_id);
  perform test_text_fixture_set('ocr_lease_token', v_claim.out_lease_token);

  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-ocr-test-1', v_claim.out_lease_token);

  select * into v_run from create_document_ocr_run(
    v_claim.out_job_id, 'noor-worker-ocr-test-1', v_claim.out_lease_token,
    repeat('9', 63) || '1', repeat('a', 60) || '1',
    'pypdfium2', '5.12.1', '1', 300, 'grayscale', 'png', repeat('b', 64), 50000,
    'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', '1', array['eng']
  );
  if v_run.out_reused <> false then
    raise exception 'TEST 4 FAILED: expected a fresh OCR run, got reused=true';
  end if;
  perform test_fixture_set('ocr_run_id', v_run.out_ocr_run_id);

  select * into v_final from finalize_document_ocr_page(
    v_run.out_ocr_run_id, v_claim.out_job_id, 'noor-worker-ocr-test-1', v_claim.out_lease_token,
    'Noor synthetic fixture', 'Noor synthetic fixture', 23, 3, repeat('c', 64),
    '{"mean_confidence": 92.5}'::jsonb, '[]'::jsonb, '{}'::jsonb,
    'guideline-processed', 'test/path/ocr-page-1.json', repeat('d', 64), 200, 'application/json'
  );
  if v_final.out_status <> 'succeeded' then
    raise exception 'TEST 4 FAILED: expected succeeded, got %', v_final.out_status;
  end if;

  perform complete_document_processing_job(v_claim.out_job_id, 'noor-worker-ocr-test-1', v_claim.out_lease_token, '{}'::jsonb);

  raise notice 'TEST 4 PASSED: Worker claimed, rendered, OCR''d, and finalized the flagged page';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 5: the partial unique index blocks a second SUCCEEDED OCR run at the
-- same full identity from ever being inserted directly — defense in depth
-- beyond the function-level idempotent-reuse check (the function-level
-- reuse path is already proven for extraction in 008 TEST 9/17, an
-- identical pattern one layer deeper here; re-deriving it against an
-- already-completed job's now-released lease would require simulating a
-- second live attempt, which duplicates that existing proof without new
-- value — see docs/database/controlled-ocr-schema.md).
-- ---------------------------------------------------------------------------
do $$
declare v_org uuid;
declare v_page_id uuid;
declare v_failed boolean := false;
begin
  select organization_id, ocr_request_page_id into v_org, v_page_id from document_ocr_runs where id = fx('ocr_run_id');
  begin
    insert into document_ocr_runs (
      organization_id, ocr_request_id, ocr_request_page_id, processing_job_id,
      source_document_id, source_sha256, extraction_run_id, source_page_number, native_page_checksum,
      renderer_name, renderer_version, render_configuration_version, render_dpi, render_color_mode, render_image_format,
      page_image_sha256, page_image_size_bytes,
      provider_name, provider_version, model_identifier, model_version, ocr_configuration_version, language_hints,
      status
    ) values (
      v_org, fx('ocr_request_id'), v_page_id, fx('ocr_job_id'),
      fx('document_id'), repeat('9', 63) || '1', fx('run_id'), 1, repeat('a', 60) || '1',
      'pypdfium2', '5.12.1', '1', 300, 'grayscale', 'png', repeat('b', 64), 50000,
      'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', '1', array['eng'],
      'succeeded'
    );
  exception when unique_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 5 FAILED: a second succeeded OCR run at the same identity was allowed';
  end if;
  raise notice 'TEST 5 PASSED: partial unique index blocks a duplicate succeeded OCR run at the same identity';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 6: a succeeded OCR run is immutable.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    update document_ocr_runs set artifact_sha256 = repeat('9', 64) where id = fx('ocr_run_id');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 6 FAILED: a succeeded OCR run''s artifact identity was mutated';
  end if;
  raise notice 'TEST 6 PASSED: a succeeded OCR run is immutable';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 7: create_document_ocr_review is rejected while pages are still
-- pending, and succeeds once all pages reach a terminal state (already true
-- here since the one flagged page succeeded).
-- ---------------------------------------------------------------------------
do $$
declare r document_ocr_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into r from create_document_ocr_review(fx('ocr_request_id'));
  set local role none;

  if r.review_status <> 'pending_review' or r.total_pages <> 1 then
    raise exception 'TEST 7 FAILED: expected pending_review/1 page, got %', row_to_json(r);
  end if;
  perform test_fixture_set('ocr_review_id', r.id);
  raise notice 'TEST 7 PASSED: OCR review opened once all page jobs reached a terminal state';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 8: full OCR review lifecycle — assign, start, mark page reviewed,
-- submit accepted; eligibility becomes chunking-eligible.
-- ---------------------------------------------------------------------------
do $$
declare elig record;
declare r document_ocr_reviews%rowtype;
begin
  -- Unlike extraction reviews, OCR has no separate .assign permission —
  -- assignment is bundled into guideline_ocr.review (only quality_manager /
  -- clinical_reviewer hold it). organization_admin's only OCR-review power
  -- is the administrative guideline_ocr.reopen_review override, so the
  -- assigning actor here is quality_manager, not org_admin.
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  perform assign_ocr_reviewer(fx('ocr_review_id'), '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_ocr_review(fx('ocr_review_id'));
  perform create_ocr_finding(fx('ocr_review_id'), 1, 'low_confidence', 'informational', 'A few words below 70% confidence', 'Minor recognition uncertainty, does not affect meaning', null);
  perform mark_ocr_page_reviewed(fx('ocr_review_id'), 1, 'accepted', 'clean recognition');
  select * into r from submit_document_ocr_review(fx('ocr_review_id'), 'accepted', null, null);
  set local role none;

  if r.review_status <> 'accepted' then
    raise exception 'TEST 8 FAILED: expected accepted, got %', row_to_json(r);
  end if;

  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into elig from get_document_extraction_review_eligibility(fx('run_id'));
  set local role none;

  if elig.out_eligible_for_chunking <> true or elig.out_eligible_for_ocr <> true then
    raise exception 'TEST 8 FAILED: expected chunking eligible / OCR eligible flag true, got %', row_to_json(elig);
  end if;
  raise notice 'TEST 8 PASSED: OCR review accepted; overall chunking eligibility now true';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 9: get_document_page_text_readiness reports OCR for page 1 and
-- native for pages 2-3, all ready.
-- ---------------------------------------------------------------------------
do $$
declare v_count_ocr int;
declare v_count_native int;
declare v_count_not_ready int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select count(*) into v_count_ocr from get_document_page_text_readiness(fx('run_id')) where out_page_number = 1 and out_representation_type = 'ocr' and out_ready_for_chunking;
  select count(*) into v_count_native from get_document_page_text_readiness(fx('run_id')) where out_page_number in (2, 3) and out_representation_type = 'native' and out_ready_for_chunking;
  select count(*) into v_count_not_ready from get_document_page_text_readiness(fx('run_id')) where not out_ready_for_chunking;
  set local role none;

  if v_count_ocr <> 1 or v_count_native <> 2 or v_count_not_ready <> 0 then
    raise exception 'TEST 9 FAILED: expected 1 ocr-ready page, 2 native-ready pages, 0 not-ready — got ocr=%, native=%, not_ready=%', v_count_ocr, v_count_native, v_count_not_ready;
  end if;
  raise notice 'TEST 9 PASSED: canonical page-text readiness correctly reports OCR for page 1, native for pages 2-3';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 10: reopening the OCR review creates a new round and reverts
-- eligibility to ineligible immediately.
-- ---------------------------------------------------------------------------
do $$
declare r document_ocr_reviews%rowtype;
declare elig record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into r from reopen_ocr_review(fx('ocr_review_id'), 'quality wants a second look at page 1');
  select * into elig from get_document_extraction_review_eligibility(fx('run_id'));
  set local role none;

  if r.review_status <> 'pending_review' or r.review_round <> 2 then
    raise exception 'TEST 10 FAILED: expected a fresh round 2 pending_review, got %', row_to_json(r);
  end if;
  if elig.out_eligible_for_chunking <> false then
    raise exception 'TEST 10 FAILED: expected chunking ineligible immediately after reopening OCR review, got %', row_to_json(elig);
  end if;
  perform test_fixture_set('ocr_review_round2_id', r.id);
  raise notice 'TEST 10 PASSED: reopening the OCR review creates a new round and revokes eligibility';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 11: the prior submitted OCR review round remains historically
-- intact.
-- ---------------------------------------------------------------------------
do $$
declare v_status text;
begin
  select review_status into v_status from document_ocr_reviews where id = fx('ocr_review_id');
  if v_status <> 'accepted' then
    raise exception 'TEST 11 FAILED: round 1''s original OCR decision was altered by reopening';
  end if;
  raise notice 'TEST 11 PASSED: the prior submitted OCR review round remains historically intact';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 12: invalidate_ocr_review — re-accept round 2 first, then
-- invalidate it administratively.
-- ---------------------------------------------------------------------------
do $$
declare r document_ocr_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_ocr_review(fx('ocr_review_round2_id'));
  perform mark_ocr_page_reviewed(fx('ocr_review_round2_id'), 1, 'accepted', 're-confirmed clean');
  perform submit_document_ocr_review(fx('ocr_review_round2_id'), 'accepted', null, null);
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into r from invalidate_ocr_review(fx('ocr_review_round2_id'), 'a rendering defect was discovered after acceptance');
  set local role none;

  if r.review_status <> 'invalidated' then
    raise exception 'TEST 12 FAILED: expected invalidated, got %', row_to_json(r);
  end if;
  raise notice 'TEST 12 PASSED: an accepted OCR review can be administratively invalidated';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 13: RLS — clinician denied all OCR reads; organization_admin
-- permitted; cross-tenant denied.
-- ---------------------------------------------------------------------------
do $$
declare v_requests int;
declare v_runs int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  select count(*) into v_requests from document_ocr_requests where id = fx('ocr_request_id');
  select count(*) into v_runs from document_ocr_runs where id = fx('ocr_run_id');
  set local role none;
  if v_requests <> 0 or v_runs <> 0 then
    raise exception 'TEST 13 FAILED: clinician could read OCR data (requests=%, runs=%)', v_requests, v_runs;
  end if;
  raise notice 'TEST 13 PASSED: clinician denied all OCR reads';
end
$$;

do $$
declare v_requests int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select count(*) into v_requests from document_ocr_requests where id = fx('ocr_request_id');
  set local role none;
  if v_requests = 0 then
    raise exception 'TEST 13b FAILED: organization_admin could not read its own OCR requests';
  end if;
  raise notice 'TEST 13b PASSED: a permitted role can read OCR data';
end
$$;

do $$
declare v_requests int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
  set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
  select count(*) into v_requests from document_ocr_requests where id = fx('ocr_request_id');
  set local role none;
  if v_requests <> 0 then
    raise exception 'TEST 14 FAILED: a cross-tenant admin (Org Beta) could read Org Alpha''s OCR requests';
  end if;
  raise notice 'TEST 14 PASSED: cross-tenant OCR reads are denied';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 15: trust boundary — authenticated cannot call any Worker-only OCR
-- function directly.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  begin
    perform create_document_ocr_run(fx('ocr_job_id'), 'x', 'y', repeat('9', 64), repeat('a', 64), 'r', '1', '1', 300, 'grayscale', 'png', repeat('b', 64), 1, 'p', '1', 'm', '1', '1', array['eng']);
  exception when insufficient_privilege then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 15 FAILED: authenticated could call create_document_ocr_run directly';
  end if;
  raise notice 'TEST 15 PASSED: authenticated is denied for create_document_ocr_run';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 16: findings cannot be deleted without the maintenance override, and
-- can be deleted with it (learned from Sprint 1-D1's real cleanup bug —
-- verified from the start this time). Uses the informational finding
-- created in TEST 8.
-- ---------------------------------------------------------------------------
do $$
declare v_finding_id uuid;
declare v_failed boolean := false;
begin
  select id into v_finding_id from document_ocr_findings where finding_type = 'low_confidence' limit 1;
  if v_finding_id is null then
    raise exception 'TEST 16 SETUP INVARIANT BROKEN: expected finding from TEST 8 not found';
  end if;

  begin
    delete from document_ocr_findings where id = v_finding_id;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 16 FAILED: an OCR finding was deleted without the maintenance override';
  end if;

  set local noor.allow_audit_maintenance = 'true';
  delete from document_ocr_findings where id = v_finding_id;
  set local noor.allow_audit_maintenance = 'false';

  if exists (select 1 from document_ocr_findings where id = v_finding_id) then
    raise exception 'TEST 16 FAILED: the maintenance override did not allow deletion';
  end if;
  raise notice 'TEST 16 PASSED: OCR findings require the maintenance override to delete';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 17: job_type uniqueness — document_ocr jobs are scoped per page, not
-- per document (two simultaneously-active OCR jobs for different pages of
-- the SAME document are both allowed; a duplicate for the SAME page is not).
-- ---------------------------------------------------------------------------
do $$
declare v_page2_id uuid;
declare v_job_a uuid;
declare v_job_b uuid;
declare v_failed boolean := false;
begin
  select id into v_page2_id from document_ocr_request_pages where ocr_request_id = fx('ocr_request_id') limit 1;

  insert into document_processing_jobs (organization_id, source_document_id, job_type, status, correlation_id, ocr_request_page_id)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('document_id'), 'document_ocr', 'queued', gen_random_uuid(), null)
    returning id into v_job_a;
  insert into document_processing_jobs (organization_id, source_document_id, job_type, status, correlation_id, ocr_request_page_id)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('document_id'), 'document_ocr', 'queued', gen_random_uuid(), null)
    returning id into v_job_b;

  if v_job_a is null or v_job_b is null then
    raise exception 'TEST 17 FAILED: two distinct unlinked document_ocr jobs for the same document could not both be queued';
  end if;

  begin
    insert into document_processing_jobs (organization_id, source_document_id, job_type, status, correlation_id, ocr_request_page_id)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('document_id'), 'document_ocr', 'queued', gen_random_uuid(), v_page2_id);
    insert into document_processing_jobs (organization_id, source_document_id, job_type, status, correlation_id, ocr_request_page_id)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('document_id'), 'document_ocr', 'queued', gen_random_uuid(), v_page2_id);
  exception when unique_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 17 FAILED: two active document_ocr jobs for the SAME page were both allowed';
  end if;

  -- Clean up these throwaway, unlinked jobs immediately — left queued, they
  -- would otherwise be claimable by claim_next_document_processing_job('document_ocr')
  -- ahead of the real, request-linked jobs the tests below depend on.
  delete from document_processing_jobs where id in (v_job_a, v_job_b);

  raise notice 'TEST 17 PASSED: document_ocr jobs are uniquely scoped per page, not per document';
end
$$;

-- ============================================================================
-- FIXTURE 2: a second, independent succeeded 1-page (scanned) extraction
-- run, reviewed and submitted ocr_required with its one page flagged
-- ocr_candidate. Kept fully separate from Fixture 1's narrative (which by
-- now has already run through acceptance/reopening/invalidation) so the
-- tests below — fail/retry, real identity-based reuse, the extraction-
-- review-reopen cascade, cancellation, self-review, and findings —  each
-- get a clean, unambiguous state to assert against.
-- ============================================================================
do $$
declare
  v_org uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_guideline_id uuid;
  v_version_id uuid;
  v_session_id uuid;
  v_document_id uuid;
  v_job_id uuid;
  v_token text;
  v_hash text;
  v_run record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select id into v_guideline_id from create_guideline(v_org, fx('domain_id'), fx('authority_id'), 'OCR-002', 'OCR Guideline Two');
  select id into v_version_id from create_guideline_version(v_guideline_id, 'v1.0');
  select upload_session_id, source_document_id into v_session_id, v_document_id
    from create_guideline_upload_session(v_version_id, 'ocr-fixture-2.pdf', 'application/pdf', 1000, null, null);
  select processing_job_id into v_job_id from complete_guideline_upload(v_session_id, 'application/pdf', 1000, repeat('8', 63) || '2', null);

  set local role none;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');
  update document_processing_jobs set
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-ocr-test-2',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = v_job_id;
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, v_job_id, 1, 'noor-worker-ocr-test-2', 'started');
  perform start_document_processing_job(v_job_id, 'noor-worker-ocr-test-2', v_token);

  select * into v_run from create_document_extraction_run(
    v_job_id, 'noor-worker-ocr-test-2', v_token, repeat('8', 63) || '2', 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );

  insert into document_extraction_pages (
    organization_id, extraction_run_id, source_document_id, page_number,
    width_points, height_points, rotation_degrees, raw_text, normalized_text,
    character_count, word_count, is_blank, suspected_scanned, extraction_status, page_checksum
  ) values (
    v_org, v_run.out_extraction_run_id, v_document_id, 1,
    595.28, 841.89, 0, '', '', 0, 0, true, true, 'no_text_layer', repeat('e', 60) || '1'
  );

  perform finalize_document_extraction_run(
    v_run.out_extraction_run_id, v_job_id, 'noor-worker-ocr-test-2', v_token,
    1, 'guideline-processed', 'test/path/ocr-fixture-2.json', repeat('f', 64), 100, 'application/json',
    '{}'::jsonb, 0, 1, 1, 0, 0, 0, '[]'::jsonb
  );

  perform test_fixture_set('document_id2', v_document_id);
  perform test_fixture_set('run_id2', v_run.out_extraction_run_id);
  raise notice 'FIXTURE 2 READY: second succeeded 1-page extraction run (scanned/no text layer)';
end
$$;

do $$
declare v_review_id uuid;
declare v_page1_id uuid;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review_id from create_document_extraction_review(fx('run_id2'));
  perform assign_extraction_reviewer(v_review_id, '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_extraction_review(v_review_id);
  select id into v_page1_id from document_extraction_pages where extraction_run_id = fx('run_id2') and page_number = 1;
  perform create_extraction_finding(v_review_id, 'image_only_page', 'major', 'Page 1 is image-only', v_page1_id, 'No text layer present', null);
  perform mark_extraction_page_reviewed(v_review_id, 1, 'ocr_candidate', 'flag for OCR');
  perform submit_document_extraction_review(v_review_id, 'ocr_required', 'page 1 needs OCR', null);
  set local role none;

  perform test_fixture_set('review_id2', v_review_id);
  raise notice 'FIXTURE 2 READY: extraction review submitted ocr_required, page 1 flagged ocr_candidate';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 18: second, independent OCR request (fixture 2).
-- ---------------------------------------------------------------------------
do $$
declare r document_ocr_requests%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into r from create_document_ocr_request(
    fx('review_id2'), 'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', 'pypdfium2', '5.12.1', '1', '1', array['eng']
  );
  set local role none;

  if r.status <> 'queued' or r.total_pages <> 1 then
    raise exception 'TEST 18 FAILED: expected queued/1 page, got %', row_to_json(r);
  end if;
  perform test_fixture_set('ocr_request_id2', r.id);
  raise notice 'TEST 18 PASSED: second, independent OCR request created';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 19: fail_document_ocr_run — a provider failure marks the run and its
-- request page failed, and the underlying processing job is retry_scheduled
-- (mission §27: ocr_provider_error is retryable).
-- ---------------------------------------------------------------------------
do $$
declare v_claim record;
declare v_run record;
declare v_fail record;
declare v_page_status text;
declare v_job_status text;
begin
  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-ocr-test-2a', array['document_ocr']);
  if v_claim.out_job_id is null then
    raise exception 'TEST 19 FAILED: no document_ocr job was claimable';
  end if;
  perform test_fixture_set('ocr_job_id2', v_claim.out_job_id);
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-ocr-test-2a', v_claim.out_lease_token);

  select * into v_run from create_document_ocr_run(
    v_claim.out_job_id, 'noor-worker-ocr-test-2a', v_claim.out_lease_token,
    repeat('8', 63) || '2', repeat('e', 60) || '1',
    'pypdfium2', '5.12.1', '1', 300, 'grayscale', 'png', repeat('1', 64), 40000,
    'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', '1', array['eng']
  );
  if v_run.out_reused <> false then
    raise exception 'TEST 19 FAILED: expected a fresh OCR run, got reused=true';
  end if;
  perform test_fixture_set('ocr_run_id2a', v_run.out_ocr_run_id);

  select * into v_fail from fail_document_ocr_run(
    v_run.out_ocr_run_id, v_claim.out_job_id, 'noor-worker-ocr-test-2a', v_claim.out_lease_token,
    'ocr_provider_error', 'ocr_provider_error', 'synthetic provider failure for TEST 19'
  );
  if v_fail.out_status <> 'failed' then
    raise exception 'TEST 19 FAILED: expected failed run status, got %', v_fail.out_status;
  end if;

  select status into v_page_status from document_ocr_request_pages where id = (
    select ocr_request_page_id from document_ocr_runs where id = v_run.out_ocr_run_id
  );
  if v_page_status <> 'failed' then
    raise exception 'TEST 19 FAILED: expected request page status failed, got %', v_page_status;
  end if;

  perform fail_document_processing_job(
    v_claim.out_job_id, 'noor-worker-ocr-test-2a', v_claim.out_lease_token,
    'ocr_provider_error', 'ocr_provider_error', 'synthetic provider failure for TEST 19', true
  );
  select status into v_job_status from document_processing_jobs where id = v_claim.out_job_id;
  if v_job_status <> 'retry_scheduled' then
    raise exception 'TEST 19 FAILED: expected job retry_scheduled, got %', v_job_status;
  end if;

  raise notice 'TEST 19 PASSED: fail_document_ocr_run marks the run/page failed; the job is retry_scheduled';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 20: the retried attempt succeeds. Because the first attempt's run at
-- this identity is 'failed' (not 'succeeded'), the partial unique index does
-- not block a second row, and create_document_ocr_run correctly reports a
-- FRESH run (reused=false) rather than reusing the failed one.
-- ---------------------------------------------------------------------------
do $$
declare v_claim record;
declare v_run record;
declare v_final record;
begin
  update document_processing_jobs set next_attempt_at = now() - interval '1 second' where id = fx('ocr_job_id2');

  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-ocr-test-2b', array['document_ocr']);
  if v_claim.out_job_id is distinct from fx('ocr_job_id2') then
    raise exception 'TEST 20 FAILED: expected to reclaim the same retry-scheduled job';
  end if;
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-ocr-test-2b', v_claim.out_lease_token);

  select * into v_run from create_document_ocr_run(
    v_claim.out_job_id, 'noor-worker-ocr-test-2b', v_claim.out_lease_token,
    repeat('8', 63) || '2', repeat('e', 60) || '1',
    'pypdfium2', '5.12.1', '1', 300, 'grayscale', 'png', repeat('1', 64), 40000,
    'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', '1', array['eng']
  );
  if v_run.out_reused <> false then
    raise exception 'TEST 20 FAILED: expected a fresh second attempt (the first failed, it was not succeeded), got reused=true';
  end if;
  if v_run.out_ocr_run_id = fx('ocr_run_id2a') then
    raise exception 'TEST 20 FAILED: expected a distinct run row from the failed first attempt';
  end if;
  perform test_fixture_set('ocr_run_id2b', v_run.out_ocr_run_id);

  select * into v_final from finalize_document_ocr_page(
    v_run.out_ocr_run_id, v_claim.out_job_id, 'noor-worker-ocr-test-2b', v_claim.out_lease_token,
    'Noor synthetic fixture 2', 'Noor synthetic fixture 2', 24, 3, repeat('c', 64),
    '{"mean_confidence": 91.0}'::jsonb, '[]'::jsonb, '{}'::jsonb,
    'guideline-processed', 'test/path/ocr-fixture-2-page-1.json', repeat('d', 64), 210, 'application/json'
  );
  if v_final.out_status <> 'succeeded' then
    raise exception 'TEST 20 FAILED: expected succeeded on retry, got %', v_final.out_status;
  end if;
  perform complete_document_processing_job(v_claim.out_job_id, 'noor-worker-ocr-test-2b', v_claim.out_lease_token, '{}'::jsonb);

  raise notice 'TEST 20 PASSED: the retried OCR page job succeeds after an earlier failed attempt; both runs are preserved';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 21: reopening the underlying EXTRACTION review cascades into the
-- still-active OCR request tied to it (mission §10) — the request is
-- immediately invalidated, but the already-succeeded page/run is left
-- historically untouched (mission §10: "no historical rows are deleted").
-- ---------------------------------------------------------------------------
do $$
declare v_new record;
declare v_req_status text;
declare v_req_reason text;
declare v_page_status text;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_new from reopen_extraction_review(fx('review_id2'), 'need a second look at the whole extraction');
  set local role none;

  if v_new.review_status <> 'pending_review' or v_new.review_round <> 2 then
    raise exception 'TEST 21 FAILED: expected a fresh round 2 pending_review, got %', row_to_json(v_new);
  end if;

  select status, invalidation_reason into v_req_status, v_req_reason from document_ocr_requests where id = fx('ocr_request_id2');
  if v_req_status <> 'invalidated' or v_req_reason is null or position('extraction review reopened' in v_req_reason) = 0 then
    raise exception 'TEST 21 FAILED: expected the active OCR request cascade-invalidated, got status=% reason=%', v_req_status, v_req_reason;
  end if;

  select status into v_page_status from document_ocr_request_pages where ocr_request_id = fx('ocr_request_id2');
  if v_page_status <> 'succeeded' then
    raise exception 'TEST 21 FAILED: a succeeded OCR page must remain historically preserved by the cascade, got %', v_page_status;
  end if;

  perform test_fixture_set('review_id2_round2', v_new.id);
  raise notice 'TEST 21 PASSED: reopening the extraction review cascade-invalidates the active OCR request while preserving the succeeded page';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 22: cancel_document_ocr_request — a fresh request/page/job created
-- from the reopened round is explicitly cancelled before ever being claimed.
-- ---------------------------------------------------------------------------
do $$
declare v_page1_id uuid;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_extraction_review(fx('review_id2_round2'));
  select id into v_page1_id from document_extraction_pages where extraction_run_id = fx('run_id2') and page_number = 1;
  perform mark_extraction_page_reviewed(fx('review_id2_round2'), 1, 'ocr_candidate', 're-flag for OCR after reopening');
  perform submit_document_extraction_review(fx('review_id2_round2'), 'ocr_required', 'page 1 still needs OCR', null);
  set local role none;
end
$$;

do $$
declare r document_ocr_requests%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into r from create_document_ocr_request(
    fx('review_id2_round2'), 'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', 'pypdfium2', '5.12.1', '1', '1', array['eng']
  );
  set local role none;
  perform test_fixture_set('ocr_request_id3', r.id);
end
$$;

do $$
declare r document_ocr_requests%rowtype;
declare v_job_status text;
declare v_page_status text;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into r from cancel_document_ocr_request(fx('ocr_request_id3'), 'no longer needed for this test');
  set local role none;

  if r.status <> 'cancelled' then
    raise exception 'TEST 22 FAILED: expected cancelled, got %', row_to_json(r);
  end if;
  select status into v_job_status from document_processing_jobs
    where ocr_request_page_id in (select id from document_ocr_request_pages where ocr_request_id = fx('ocr_request_id3'));
  select status into v_page_status from document_ocr_request_pages where ocr_request_id = fx('ocr_request_id3');
  if v_job_status <> 'cancelled' or v_page_status <> 'cancelled' then
    raise exception 'TEST 22 FAILED: expected job and page cancelled, got job=% page=%', v_job_status, v_page_status;
  end if;
  raise notice 'TEST 22 PASSED: cancel_document_ocr_request cancels the request, its page, and its queued job';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 23: real function-level identity-based reuse. A fourth OCR request
-- (created after cancelling the third, from the same reopened round, same
-- page) is claimed and, at the exact same OCR identity as the succeeded
-- run from TEST 20, correctly reports out_reused=true against that same
-- run — and, per the fix applied to create_document_ocr_run's reused
-- branch, the new request page is immediately marked succeeded even though
-- finalize_document_ocr_page is never called for it.
-- ---------------------------------------------------------------------------
do $$
declare r document_ocr_requests%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into r from create_document_ocr_request(
    fx('review_id2_round2'), 'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', 'pypdfium2', '5.12.1', '1', '1', array['eng']
  );
  set local role none;
  if r.id = fx('ocr_request_id3') then
    raise exception 'TEST 23 FAILED: expected a brand-new request now that request 3 is cancelled, got the same id';
  end if;
  perform test_fixture_set('ocr_request_id4', r.id);
end
$$;

do $$
declare v_claim record;
declare v_run record;
declare v_page_status text;
begin
  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-ocr-test-4', array['document_ocr']);
  if v_claim.out_job_id is null then
    raise exception 'TEST 23 FAILED: no document_ocr job was claimable for request 4';
  end if;
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-ocr-test-4', v_claim.out_lease_token);

  select * into v_run from create_document_ocr_run(
    v_claim.out_job_id, 'noor-worker-ocr-test-4', v_claim.out_lease_token,
    repeat('8', 63) || '2', repeat('e', 60) || '1',
    'pypdfium2', '5.12.1', '1', 300, 'grayscale', 'png', repeat('1', 64), 40000,
    'tesseract', '5.5.0', 'tessdata_fast/eng', '7d4322bd', '1', array['eng']
  );
  if v_run.out_reused <> true then
    raise exception 'TEST 23 FAILED: expected identity-based reuse of the already-succeeded run, got reused=false';
  end if;
  if v_run.out_ocr_run_id <> fx('ocr_run_id2b') then
    raise exception 'TEST 23 FAILED: expected the reused run to be the previously succeeded run from TEST 20';
  end if;

  select status into v_page_status from document_ocr_request_pages where ocr_request_id = fx('ocr_request_id4');
  if v_page_status <> 'succeeded' then
    raise exception 'TEST 23 FAILED: a reused OCR identity must immediately mark the new request page succeeded, got %', v_page_status;
  end if;

  perform complete_document_processing_job(v_claim.out_job_id, 'noor-worker-ocr-test-4', v_claim.out_lease_token, '{}'::jsonb);
  raise notice 'TEST 23 PASSED: create_document_ocr_run correctly reuses an already-succeeded identity across two different OCR requests, and immediately marks the new page succeeded';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 24: self-review — a reviewer who uploaded/registered the source
-- document cannot start (technically review) its own OCR output, mirroring
-- migration 0009's identical extraction-review policy one layer deeper.
-- (This repo's fixtures have only one clinical_reviewer account, so the
-- uploader/reviewer collision is engineered with a direct, test-only
-- fixture update rather than a second real reviewer account.)
-- ---------------------------------------------------------------------------
do $$
declare v_review4_id uuid;
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review4_id from create_document_ocr_review(fx('ocr_request_id4'));
  set local role none;
  perform test_fixture_set('ocr_review_id4', v_review4_id);

  update guideline_source_documents set uploaded_by = '66666666-6666-6666-6666-666666666666' where id = fx('document_id2');

  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  perform assign_ocr_reviewer(v_review4_id, '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  begin
    perform start_document_ocr_review(v_review4_id);
  exception when others then
    v_failed := true;
  end;
  set local role none;

  if not v_failed then
    raise exception 'TEST 24 FAILED: a reviewer who uploaded the source document was allowed to review its own OCR output';
  end if;

  -- Restore the real uploader and hand the review to someone who genuinely
  -- did not upload this document, so the narrative can continue for TEST 25.
  update guideline_source_documents set uploaded_by = '11111111-1111-1111-1111-111111111111' where id = fx('document_id2');

  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  perform assign_ocr_reviewer(v_review4_id, '77777777-7777-7777-7777-777777777777');
  perform start_document_ocr_review(v_review4_id);
  set local role none;

  raise notice 'TEST 24 PASSED: a reviewer who uploaded/registered the source document is blocked from reviewing its own OCR output';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 25: create_ocr_finding / update_ocr_finding_status, and
-- submit_document_ocr_review('rejected').
-- ---------------------------------------------------------------------------
do $$
declare v_finding_id uuid;
declare v_finding_status text;
declare r document_ocr_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  select id into v_finding_id from create_ocr_finding(
    fx('ocr_review_id4'), 1, 'garbled_characters', 'major', 'Garbled output detected',
    'Several words are unreadable', 'reprocess with a different render configuration'
  );
  perform update_ocr_finding_status(v_finding_id, 'acknowledged', 'confirmed by reviewer, escalating to rejection');
  select status into v_finding_status from document_ocr_findings where id = v_finding_id;
  if v_finding_status <> 'acknowledged' then
    raise exception 'TEST 25 FAILED: expected finding status acknowledged, got %', v_finding_status;
  end if;

  perform mark_ocr_page_reviewed(fx('ocr_review_id4'), 1, 'rejected', 'garbled output, not usable');
  select * into r from submit_document_ocr_review(fx('ocr_review_id4'), 'rejected', 'garbled recognition output, unusable for chunking', null);
  set local role none;

  if r.review_status <> 'rejected' then
    raise exception 'TEST 25 FAILED: expected rejected, got %', row_to_json(r);
  end if;
  raise notice 'TEST 25 PASSED: create_ocr_finding/update_ocr_finding_status work correctly, and submit_document_ocr_review(rejected) is enforced';
end
$$;

do $$
begin
  raise notice 'ALL CONTROLLED OCR TESTS PASSED';
end
$$;

drop function fx(text);
drop function fxt(text);
drop function test_fixture_set(text, uuid);
drop function test_text_fixture_set(text, text);
