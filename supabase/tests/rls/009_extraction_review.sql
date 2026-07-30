-- ============================================================================
-- Noor V1 Test Suite — Extraction Review and Technical Quality Gate (Sprint 1-D1)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 009_extraction_review.sql
-- Depends on 001-008 already having run in this database (migrations
-- 0001-0009 must be applied).
--
-- Same convention as 008_pdf_extraction.sql: this file grants its own
-- explicit SELECT/EXECUTE to `authenticated` at the top rather than relying
-- on migration 0009's own guarded (locally no-op) grant — CI's plain
-- Postgres container has no `authenticated` role until 001_tenant_isolation.sql
-- creates it, so a migration-time guarded grant never re-runs. Missing this
-- exact grant in 008's own test file was a real CI-only bug found in Sprint
-- 1.2B (see docs/database/deterministic-pdf-extraction-schema.md) — this
-- file starts from that lesson rather than re-discovering it.
-- ============================================================================

grant select on document_extraction_reviews, document_extraction_review_findings,
  document_extraction_page_reviews, document_extraction_review_events
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
  claim_extraction_review(uuid, uuid),
  start_document_extraction_review(uuid, uuid),
  mark_extraction_page_reviewed(uuid, int, text, text, uuid),
  create_extraction_finding(uuid, text, text, text, uuid, text, text, uuid),
  update_extraction_finding_status(uuid, text, text, uuid),
  submit_document_extraction_review(uuid, text, text, text, text, uuid),
  reopen_extraction_review(uuid, text, uuid),
  invalidate_extraction_review(uuid, text, uuid),
  get_document_extraction_review_eligibility(uuid)
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
-- FIXTURE: two extra synthetic users (clinical_reviewer, quality_manager) in
-- Org Alpha, on top of seed.sql's admin_alpha/clinician_alpha.
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
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '66666666-6666-6666-6666-666666666666', id, 'active'
from roles where key = 'clinical_reviewer'
on conflict do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '77777777-7777-7777-7777-777777777777', id, 'active'
from roles where key = 'quality_manager'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- FIXTURE: helper to build one succeeded extraction run with N pages, as
-- org_admin '11111111'. Returns via test fixtures: last_guideline_id,
-- last_version_id, last_document_id, last_job_id, last_run_id.
-- ----------------------------------------------------------------------------
do $$
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  perform test_fixture_set('domain_id', id) from create_clinical_domain('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'review-domain', 'Review Test Domain', null);
  perform test_fixture_set('authority_id', id) from create_guideline_authority('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Review Test Authority', null, null, null, null, true, null);
  set local role none;
end
$$;

-- Builds fixture N: guideline/version/upload/complete -> queued job, claimed
-- and started, then a succeeded extraction run with p_pages pages. Stores
-- run_<n>_id / job_<n>_id / document_<n>_id / version_<n>_id in fixtures.
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
  i int;
  v_page_count int;
  v_suffix text;
begin
  for v_suffix in select unnest(array['1','2','3','4','5','6']) loop
    set local role authenticated;
    set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

    select id into v_guideline_id from create_guideline(v_org, fx('domain_id'), fx('authority_id'), 'REVIEW-' || v_suffix, 'Review Guideline ' || v_suffix);
    select id into v_version_id from create_guideline_version(v_guideline_id, 'v1.0');
    select upload_session_id, source_document_id into v_session_id, v_document_id
      from create_guideline_upload_session(v_version_id, 'review-fixture-' || v_suffix || '.pdf', 'application/pdf', 1000, null, null);

    v_sha := repeat('e', 63) || v_suffix;
    select processing_job_id into v_job_id from complete_guideline_upload(v_session_id, 'application/pdf', 1000, v_sha, null);

    set local role none;

    v_token := encode(gen_random_bytes(32), 'hex');
    v_hash := encode(digest(v_token, 'sha256'), 'hex');
    update document_processing_jobs set
      status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-review-test',
      claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
      lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
      where id = v_job_id;
    insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
      values (v_org, v_job_id, 1, 'noor-worker-review-test', 'started');
    perform start_document_processing_job(v_job_id, 'noor-worker-review-test', v_token);

    select * into v_run from create_document_extraction_run(
      v_job_id, 'noor-worker-review-test', v_token, v_sha, 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
    );

    v_page_count := 3;
    for i in 1..v_page_count loop
      insert into document_extraction_pages (
        organization_id, extraction_run_id, source_document_id, page_number,
        width_points, height_points, rotation_degrees, raw_text, normalized_text,
        character_count, word_count, is_blank, suspected_scanned, extraction_status, page_checksum
      ) values (
        v_org, v_run.out_extraction_run_id, v_document_id, i,
        595.28, 841.89, 0, 'Fixture page ' || i, 'Fixture page ' || i,
        20, 3, false, false, 'text_extracted', repeat(v_suffix, 60) || i::text
      );
    end loop;

    perform finalize_document_extraction_run(
      v_run.out_extraction_run_id, v_job_id, 'noor-worker-review-test', v_token,
      v_page_count, 'guideline-processed', 'test/path/review-' || v_suffix || '.json', repeat('f', 64), 100, 'application/json',
      '{}'::jsonb, v_page_count, 0, 0, 60, 9, 0, '[]'::jsonb
    );

    perform test_fixture_set('guideline_' || v_suffix || '_id', v_guideline_id);
    perform test_fixture_set('version_' || v_suffix || '_id', v_version_id);
    perform test_fixture_set('document_' || v_suffix || '_id', v_document_id);
    perform test_fixture_set('job_' || v_suffix || '_id', v_job_id);
    perform test_fixture_set('run_' || v_suffix || '_id', v_run.out_extraction_run_id);
  end loop;

  raise notice 'FIXTURE READY: 6 succeeded extraction runs (3 pages each) built for review testing';
end
$$;

-- A 7th run deliberately left `running` (never finalized) — used to prove
-- review creation is rejected for a non-succeeded run.
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
  v_run record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select id into v_guideline_id from create_guideline(v_org, fx('domain_id'), fx('authority_id'), 'REVIEW-7', 'Review Guideline 7 (running)');
  select id into v_version_id from create_guideline_version(v_guideline_id, 'v1.0');
  select upload_session_id, source_document_id into v_session_id, v_document_id
    from create_guideline_upload_session(v_version_id, 'review-fixture-7.pdf', 'application/pdf', 1000, null, null);
  select processing_job_id into v_job_id from complete_guideline_upload(v_session_id, 'application/pdf', 1000, repeat('e', 63) || '7', null);

  set local role none;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');
  update document_processing_jobs set
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-review-test',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = v_job_id;
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, v_job_id, 1, 'noor-worker-review-test', 'started');
  perform start_document_processing_job(v_job_id, 'noor-worker-review-test', v_token);

  select * into v_run from create_document_extraction_run(
    v_job_id, 'noor-worker-review-test', v_token, repeat('e', 63) || '7', 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );
  perform test_fixture_set('run_running_id', v_run.out_extraction_run_id);
  raise notice 'FIXTURE READY: run 7 left running (never finalized)';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: create_document_extraction_review succeeds for org_admin against a
-- succeeded run, pending_review, total_pages carried over.
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select * into r from create_document_extraction_review(fx('run_1_id'));
  set local role none;

  if r.review_status <> 'pending_review' or r.total_pages <> 3 or r.review_round <> 1 then
    raise exception 'TEST 1 FAILED: expected pending_review/3 pages/round 1, got %', row_to_json(r);
  end if;
  perform test_fixture_set('review_1_id', r.id);
  raise notice 'TEST 1 PASSED: extraction review created (pending_review, 3 total pages)';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 2: a second create_document_extraction_review call for the SAME run
-- is idempotent — returns the same active round, not a duplicate.
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
declare v_count int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select * into r from create_document_extraction_review(fx('run_1_id'));
  set local role none;

  if r.id <> fx('review_1_id') then
    raise exception 'TEST 2 FAILED: expected the same review id, got a different one';
  end if;
  select count(*) into v_count from document_extraction_reviews where extraction_run_id = fx('run_1_id');
  if v_count <> 1 then
    raise exception 'TEST 2 FAILED: expected exactly 1 review row, found %', v_count;
  end if;
  raise notice 'TEST 2 PASSED: duplicate create_document_extraction_review is idempotent, no duplicate round created';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 3: clinician cannot create an extraction review (lacks permission).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  begin
    perform create_document_extraction_review(fx('run_2_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 3 FAILED: clinician created an extraction review';
  end if;
  raise notice 'TEST 3 PASSED: clinician denied create_document_extraction_review';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 4: a review cannot be opened against a non-succeeded (running) run.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  begin
    perform create_document_extraction_review(fx('run_running_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 4 FAILED: a review was opened against a running (non-succeeded) extraction run';
  end if;
  raise notice 'TEST 4 PASSED: review creation rejected for a non-succeeded extraction run';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 5: assign_extraction_reviewer succeeds for a reviewer who holds
-- review permission.
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select * into r from assign_extraction_reviewer(fx('review_1_id'), '66666666-6666-6666-6666-666666666666');
  set local role none;

  if r.assigned_reviewer_id <> '66666666-6666-6666-6666-666666666666' then
    raise exception 'TEST 5 FAILED: assignment did not stick';
  end if;
  raise notice 'TEST 5 PASSED: review assigned to a permitted reviewer';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 6: assigning to a user without review permission (a clinician) is
-- rejected.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  begin
    perform assign_extraction_reviewer(fx('review_1_id'), '22222222-2222-2222-2222-222222222222');
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 6 FAILED: a clinician (no review permission) was assigned as a reviewer';
  end if;
  raise notice 'TEST 6 PASSED: assignment rejected for a user without review permission';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 7: start_document_extraction_review succeeds for the assigned
-- reviewer -> in_review.
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  select * into r from start_document_extraction_review(fx('review_1_id'));
  set local role none;

  if r.review_status <> 'in_review' or r.started_by <> '66666666-6666-6666-6666-666666666666' then
    raise exception 'TEST 7 FAILED: expected in_review with started_by set, got %', row_to_json(r);
  end if;
  raise notice 'TEST 7 PASSED: review started by the assigned reviewer';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 8: starting an already-started review fails (not pending_review).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  begin
    perform start_document_extraction_review(fx('review_1_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 8 FAILED: an already-in_review round was started again';
  end if;
  raise notice 'TEST 8 PASSED: re-starting an in_review round is rejected';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 9: mark_extraction_page_reviewed succeeds for the assigned reviewer;
-- pages_reviewed increments.
-- ---------------------------------------------------------------------------
do $$
declare v_pages_reviewed int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  perform mark_extraction_page_reviewed(fx('review_1_id'), 1, 'reviewed_clear', 'looks fine');
  set local role none;

  select pages_reviewed into v_pages_reviewed from document_extraction_reviews where id = fx('review_1_id');
  if v_pages_reviewed <> 1 then
    raise exception 'TEST 9 FAILED: expected pages_reviewed=1, got %', v_pages_reviewed;
  end if;
  raise notice 'TEST 9 PASSED: page 1 marked reviewed, pages_reviewed incremented';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 10: a non-assigned reviewer (quality_manager, not assigned to this
-- round) cannot mark a page reviewed.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform mark_extraction_page_reviewed(fx('review_1_id'), 2, 'reviewed_clear', null);
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 10 FAILED: a non-assigned reviewer marked a page reviewed';
  end if;
  raise notice 'TEST 10 PASSED: only the assigned reviewer can mark pages reviewed';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 11: create_extraction_finding (page-level, minor) succeeds; the
-- review's minor_finding_count reflects it.
-- ---------------------------------------------------------------------------
do $$
declare f document_extraction_review_findings%rowtype;
declare v_page_id uuid;
declare v_minor int;
begin
  select id into v_page_id from document_extraction_pages where extraction_run_id = fx('run_1_id') and page_number = 1;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  select * into f from create_extraction_finding(fx('review_1_id'), 'header_footer_noise', 'minor', 'Repeated footer', v_page_id, 'Footer repeats on every page', null);
  set local role none;

  if f.status <> 'open' or f.page_number <> 1 then
    raise exception 'TEST 11 FAILED: expected an open finding on page 1, got %', row_to_json(f);
  end if;
  select minor_finding_count into v_minor from document_extraction_reviews where id = fx('review_1_id');
  if v_minor <> 1 then
    raise exception 'TEST 11 FAILED: expected minor_finding_count=1, got %', v_minor;
  end if;
  perform test_fixture_set('finding_1_id', f.id);
  raise notice 'TEST 11 PASSED: page-level minor finding created and counted';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 12: create_extraction_finding (document-level, no page) succeeds.
-- ---------------------------------------------------------------------------
do $$
declare f document_extraction_review_findings%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  select * into f from create_extraction_finding(fx('review_1_id'), 'metadata_mismatch', 'informational', 'Title casing differs from source', null, 'Cosmetic only', null);
  set local role none;

  if f.extraction_page_id is not null or f.page_number is not null then
    raise exception 'TEST 12 FAILED: expected a document-level finding with no page reference';
  end if;
  raise notice 'TEST 12 PASSED: document-level finding created with no page reference';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 13: finding_type='other' without a description is rejected by the
-- CHECK constraint.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  begin
    perform create_extraction_finding(fx('review_1_id'), 'other', 'minor', 'Something unusual', null, null, null);
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 13 FAILED: an "other" finding without a description was accepted';
  end if;
  raise notice 'TEST 13 PASSED: "other" finding type requires a description';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 14: submitting before all pages are reviewed is rejected.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  begin
    perform submit_document_extraction_review(fx('review_1_id'), 'accepted_with_warnings', null, 'minor footer noise only');
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 14 FAILED: submission succeeded despite only 1 of 3 pages reviewed';
  end if;
  raise notice 'TEST 14 PASSED: submission rejected until all pages are reviewed';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 15: submit accepted_with_warnings after all pages reviewed, only
-- minor/informational open findings remain -> succeeds; eligibility reports
-- chunking eligible, OCR not eligible.
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
declare elig record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  perform mark_extraction_page_reviewed(fx('review_1_id'), 2, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(fx('review_1_id'), 3, 'reviewed_with_findings', null);

  select * into r from submit_document_extraction_review(fx('review_1_id'), 'accepted_with_warnings', null, 'minor footer noise and a cosmetic title mismatch only', 'idem-1');
  set local role authenticated;
  select * into elig from get_document_extraction_review_eligibility(fx('run_1_id'));
  set local role none;

  if r.review_status <> 'accepted_with_warnings' or r.warning_summary is null then
    raise exception 'TEST 15 FAILED: expected accepted_with_warnings with a warning_summary, got %', row_to_json(r);
  end if;
  if elig.out_eligible_for_chunking <> true or elig.out_eligible_for_ocr <> false then
    raise exception 'TEST 15 FAILED: expected chunking eligible / OCR not eligible, got %', row_to_json(elig);
  end if;
  raise notice 'TEST 15 PASSED: accepted_with_warnings submitted; eligibility correctly derived';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 16: replaying the same submission with the same idempotency key is
-- idempotent (no error, same status returned).
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  select * into r from submit_document_extraction_review(fx('review_1_id'), 'accepted_with_warnings', null, 'minor footer noise and a cosmetic title mismatch only', 'idem-1');
  set local role none;

  if r.review_status <> 'accepted_with_warnings' then
    raise exception 'TEST 16 FAILED: idempotent replay did not return accepted_with_warnings';
  end if;
  raise notice 'TEST 16 PASSED: replayed submission with the same idempotency key is idempotent';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 17: a submitted (terminal) review round is immutable — a direct
-- UPDATE attempt is rejected by the trigger, not just discouraged by RLS.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    update document_extraction_reviews set overall_comments = 'tampered' where id = fx('review_1_id');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 17 FAILED: a terminal review round was mutated directly';
  end if;
  raise notice 'TEST 17 PASSED: a submitted review round is immutable';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 18: submitting again while already terminal (no idempotency match)
-- is rejected, not silently accepted.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  begin
    perform submit_document_extraction_review(fx('review_1_id'), 'accepted', null, null, 'idem-different');
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 18 FAILED: a terminal review round accepted a second, non-idempotent submission';
  end if;
  raise notice 'TEST 18 PASSED: a genuinely new submission attempt on a terminal round is rejected';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 19: reopen_extraction_review creates a NEW round (round 2,
-- pending_review); eligibility immediately reverts to ineligible.
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
declare elig record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  select * into r from reopen_extraction_review(fx('review_1_id'), 'quality spot-check requested a second pass');
  select * into elig from get_document_extraction_review_eligibility(fx('run_1_id'));
  set local role none;

  if r.review_status <> 'pending_review' or r.review_round <> 2 or r.reopened_from_review_id <> fx('review_1_id') then
    raise exception 'TEST 19 FAILED: expected a fresh round 2 pending_review, got %', row_to_json(r);
  end if;
  if elig.out_eligible_for_chunking <> false then
    raise exception 'TEST 19 FAILED: expected chunking ineligible immediately after reopening, got %', row_to_json(elig);
  end if;
  perform test_fixture_set('review_1_round2_id', r.id);
  raise notice 'TEST 19 PASSED: reopening creates a new round and immediately revokes eligibility';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 20: the prior (round 1) submitted review remains historically
-- readable and untouched.
-- ---------------------------------------------------------------------------
do $$
declare v_status text;
declare v_warning text;
begin
  select review_status, warning_summary into v_status, v_warning from document_extraction_reviews where id = fx('review_1_id');
  if v_status <> 'accepted_with_warnings' or v_warning is null then
    raise exception 'TEST 20 FAILED: round 1''s original decision was altered by reopening';
  end if;
  raise notice 'TEST 20 PASSED: the prior submitted round remains historically intact';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 21: reopening again while round 2 is still active (not yet
-- submitted) is rejected — only a submitted round can be reopened.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform reopen_extraction_review(fx('review_1_round2_id'), 'should not be allowed');
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 21 FAILED: an active (non-submitted) round was reopened';
  end if;
  raise notice 'TEST 21 PASSED: only a submitted round can be reopened';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 22: the partial unique index blocks a second active round for the
-- same run from ever being inserted directly (defense in depth beyond the
-- function-level idempotent-reuse check).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    insert into document_extraction_reviews (organization_id, extraction_run_id, review_round, review_status, total_pages)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('run_1_id'), 99, 'pending_review', 3);
  exception when unique_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 22 FAILED: a second active round at the same run was allowed';
  end if;
  raise notice 'TEST 22 PASSED: partial unique index blocks a duplicate active round';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 23: invalidate_extraction_review on the accepted_with_warnings round
-- 1 succeeds; eligibility reflects invalidated status; the reason is
-- recorded.
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  select * into r from invalidate_extraction_review(fx('review_1_id'), 'a pipeline defect was discovered after acceptance');
  set local role none;

  if r.review_status <> 'invalidated' or r.decision_reason is null then
    raise exception 'TEST 23 FAILED: expected invalidated with a reason recorded, got %', row_to_json(r);
  end if;
  raise notice 'TEST 23 PASSED: an accepted_with_warnings round can be administratively invalidated';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 24: an invalidated round is itself immutable, and cannot be
-- invalidated a second time.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform invalidate_extraction_review(fx('review_1_id'), 'again');
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 24 FAILED: an already-invalidated round was invalidated again';
  end if;
  raise notice 'TEST 24 PASSED: an invalidated round cannot be invalidated a second time';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 25: accepted requires zero open critical/major findings — a critical
-- open finding blocks it (run 2, fresh review).
-- ---------------------------------------------------------------------------
do $$
declare v_review_id uuid;
declare v_page_id uuid;
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review_id from create_document_extraction_review(fx('run_2_id'));
  perform assign_extraction_reviewer(v_review_id, '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_extraction_review(v_review_id);
  select id into v_page_id from document_extraction_pages where extraction_run_id = fx('run_2_id') and page_number = 1;
  perform create_extraction_finding(v_review_id, 'garbled_characters', 'critical', 'Arabic text is fully garbled', v_page_id, 'Every character on this page is mis-shaped', null);
  perform mark_extraction_page_reviewed(v_review_id, 1, 'reviewed_with_findings', null);
  perform mark_extraction_page_reviewed(v_review_id, 2, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(v_review_id, 3, 'reviewed_clear', null);
  begin
    perform submit_document_extraction_review(v_review_id, 'accepted', null, null);
  exception when others then
    v_failed := true;
  end;
  set local role none;

  if not v_failed then
    raise exception 'TEST 25 FAILED: accepted was allowed with an open critical finding';
  end if;
  perform test_fixture_set('review_2_id', v_review_id);
  raise notice 'TEST 25 PASSED: accepted blocked by an open critical finding';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 26: dismissing a critical finding without a resolution note is
-- rejected; with a resolution note it succeeds, and accepted then succeeds.
-- ---------------------------------------------------------------------------
do $$
declare v_finding_id uuid;
declare v_failed boolean := false;
declare r document_extraction_reviews%rowtype;
begin
  select id into v_finding_id from document_extraction_review_findings
    where extraction_review_id = fx('review_2_id') and severity = 'critical' limit 1;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  begin
    perform update_extraction_finding_status(v_finding_id, 'accepted_risk', null);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 26 FAILED: a critical finding was accepted-risk without a resolution note';
  end if;

  perform update_extraction_finding_status(v_finding_id, 'accepted_risk', 'confirmed with the clinical author out of band; text is a known low-value footnote');
  select * into r from submit_document_extraction_review(fx('review_2_id'), 'accepted', null, null);
  set local role none;

  if r.review_status <> 'accepted' then
    raise exception 'TEST 26 FAILED: expected accepted after resolving the critical finding, got %', row_to_json(r);
  end if;
  raise notice 'TEST 26 PASSED: dismissing a critical finding requires a reason; accepted succeeds once resolved';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 27: ocr_required requires a supporting finding and a decision reason
-- (run 3).
-- ---------------------------------------------------------------------------
do $$
declare v_review_id uuid;
declare v_page_id uuid;
declare v_failed boolean := false;
declare r document_extraction_reviews%rowtype;
declare elig record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review_id from create_document_extraction_review(fx('run_3_id'));
  perform assign_extraction_reviewer(v_review_id, '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_extraction_review(v_review_id);
  perform mark_extraction_page_reviewed(v_review_id, 1, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(v_review_id, 2, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(v_review_id, 3, 'reviewed_clear', null);

  begin
    perform submit_document_extraction_review(v_review_id, 'ocr_required', 'no supporting finding yet', null);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 27 FAILED: ocr_required was accepted with no supporting finding';
  end if;
  v_failed := false;

  select id into v_page_id from document_extraction_pages where extraction_run_id = fx('run_3_id') and page_number = 3;
  perform create_extraction_finding(v_review_id, 'suspected_scanned_page', 'major', 'Page 3 appears scanned', v_page_id, 'No real text layer, only an image', null);

  begin
    perform submit_document_extraction_review(v_review_id, 'ocr_required', null, null);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 27 FAILED: ocr_required was accepted without a decision_reason';
  end if;

  -- Sprint 1-D2 tightened ocr_required to also require at least one page
  -- actually marked ocr_candidate (see migration 0011's CREATE OR REPLACE
  -- of submit_document_extraction_review) — a finding alone is no longer
  -- sufficient, since create_document_ocr_request() only ever acts on
  -- ocr_candidate pages. Prove that gap is still enforced before marking
  -- page 3 ocr_candidate for real.
  begin
    perform submit_document_extraction_review(v_review_id, 'ocr_required', 'page 3 needs OCR before it can be used', null);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 27 FAILED: ocr_required was accepted with no page marked ocr_candidate';
  end if;
  v_failed := false;

  perform mark_extraction_page_reviewed(v_review_id, 3, 'ocr_candidate', 'flag for OCR');

  select * into r from submit_document_extraction_review(v_review_id, 'ocr_required', 'page 3 needs OCR before it can be used', null);
  set local role authenticated;
  select * into elig from get_document_extraction_review_eligibility(fx('run_3_id'));
  set local role none;

  if r.review_status <> 'ocr_required' or not r.requires_ocr then
    raise exception 'TEST 27 FAILED: expected ocr_required with requires_ocr=true, got %', row_to_json(r);
  end if;
  if elig.out_eligible_for_ocr <> true or elig.out_eligible_for_chunking <> false then
    raise exception 'TEST 27 FAILED: expected OCR eligible / chunking ineligible, got %', row_to_json(elig);
  end if;
  raise notice 'TEST 27 PASSED: ocr_required requires a supporting finding and a reason; eligibility correct';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 28: reprocessing_required requires a supporting finding and a
-- decision reason (run 4).
-- ---------------------------------------------------------------------------
do $$
declare v_review_id uuid;
declare v_page_id uuid;
declare v_failed boolean := false;
declare r document_extraction_reviews%rowtype;
declare elig record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review_id from create_document_extraction_review(fx('run_4_id'));
  perform assign_extraction_reviewer(v_review_id, '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_extraction_review(v_review_id);
  perform mark_extraction_page_reviewed(v_review_id, 1, 'reviewed_with_findings', null);
  perform mark_extraction_page_reviewed(v_review_id, 2, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(v_review_id, 3, 'reviewed_clear', null);

  select id into v_page_id from document_extraction_pages where extraction_run_id = fx('run_4_id') and page_number = 1;
  perform create_extraction_finding(v_review_id, 'incorrect_reading_order', 'major', 'Two-column layout read straight across', v_page_id, 'Configuration should use column-aware extraction', 'Re-run with column-aware configuration');

  begin
    perform submit_document_extraction_review(v_review_id, 'reprocessing_required', null, null);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 28 FAILED: reprocessing_required was accepted without a decision_reason';
  end if;

  select * into r from submit_document_extraction_review(v_review_id, 'reprocessing_required', 'needs column-aware extraction configuration', null);
  set local role authenticated;
  select * into elig from get_document_extraction_review_eligibility(fx('run_4_id'));
  set local role none;

  if r.review_status <> 'reprocessing_required' or not r.requires_reprocessing then
    raise exception 'TEST 28 FAILED: expected reprocessing_required with requires_reprocessing=true, got %', row_to_json(r);
  end if;
  if elig.out_eligible_for_ocr <> false or elig.out_eligible_for_chunking <> false then
    raise exception 'TEST 28 FAILED: expected both OCR and chunking ineligible, got %', row_to_json(elig);
  end if;
  raise notice 'TEST 28 PASSED: reprocessing_required requires a supporting finding and a reason; eligibility correct';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 29: rejected requires a decision reason and at least one major or
-- critical finding (run 5).
-- ---------------------------------------------------------------------------
do $$
declare v_review_id uuid;
declare v_page_id uuid;
declare v_failed boolean := false;
declare r document_extraction_reviews%rowtype;
declare elig record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review_id from create_document_extraction_review(fx('run_5_id'));
  perform assign_extraction_reviewer(v_review_id, '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_extraction_review(v_review_id);
  perform mark_extraction_page_reviewed(v_review_id, 1, 'reviewed_with_findings', null);
  perform mark_extraction_page_reviewed(v_review_id, 2, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(v_review_id, 3, 'reviewed_clear', null);

  begin
    perform submit_document_extraction_review(v_review_id, 'rejected', 'wrong document entirely', null);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 29 FAILED: rejected was accepted with no major/critical finding';
  end if;

  select id into v_page_id from document_extraction_pages where extraction_run_id = fx('run_5_id') and page_number = 1;
  perform create_extraction_finding(v_review_id, 'source_integrity_concern', 'critical', 'Uploaded PDF is a different guideline entirely', v_page_id, 'Title page names an unrelated document', null);

  select * into r from submit_document_extraction_review(v_review_id, 'rejected', 'wrong document was uploaded for this guideline version', null);
  set local role authenticated;
  select * into elig from get_document_extraction_review_eligibility(fx('run_5_id'));
  set local role none;

  if r.review_status <> 'rejected' then
    raise exception 'TEST 29 FAILED: expected rejected, got %', row_to_json(r);
  end if;
  if elig.out_eligible_for_ocr <> false or elig.out_eligible_for_chunking <> false then
    raise exception 'TEST 29 FAILED: expected both OCR and chunking ineligible after rejection, got %', row_to_json(elig);
  end if;
  raise notice 'TEST 29 PASSED: rejected requires a reason and a major/critical finding; eligibility correct';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 30: self-review — a reviewer who uploaded/registered the source
-- document cannot start (or therefore submit) its review (run 6).
-- ---------------------------------------------------------------------------
do $$
declare v_review_id uuid;
declare v_failed boolean := false;
begin
  update guideline_source_documents set uploaded_by = '66666666-6666-6666-6666-666666666666', registered_by = '66666666-6666-6666-6666-666666666666'
    where id = fx('document_6_id');

  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review_id from create_document_extraction_review(fx('run_6_id'));
  perform assign_extraction_reviewer(v_review_id, '66666666-6666-6666-6666-666666666666');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  begin
    perform start_document_extraction_review(v_review_id);
  exception when others then
    v_failed := true;
  end;
  set local role none;

  if not v_failed then
    raise exception 'TEST 30 FAILED: a reviewer started a review of a document they uploaded themselves';
  end if;
  perform test_fixture_set('review_6_id', v_review_id);
  raise notice 'TEST 30 PASSED: self-review is blocked at start time';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 31: a different, permitted reviewer (quality_manager) can start the
-- same review that was blocked for the uploader in TEST 30.
-- ---------------------------------------------------------------------------
do $$
declare r document_extraction_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  perform assign_extraction_reviewer(fx('review_6_id'), '77777777-7777-7777-7777-777777777777');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into r from start_document_extraction_review(fx('review_6_id'));
  set local role none;

  if r.review_status <> 'in_review' then
    raise exception 'TEST 31 FAILED: a non-uploading reviewer could not start the review';
  end if;
  raise notice 'TEST 31 PASSED: a reviewer who did not upload the document can start the review';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 32: claim_extraction_review lets an unassigned, permitted reviewer
-- self-claim an active round.
-- ---------------------------------------------------------------------------
do $$
declare v_review_id uuid;
declare r document_extraction_reviews%rowtype;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select id into v_review_id from reopen_extraction_review(fx('review_2_id'), 'quality wants an independent second look');
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into r from claim_extraction_review(v_review_id);
  set local role none;

  if r.assigned_reviewer_id <> '77777777-7777-7777-7777-777777777777' then
    raise exception 'TEST 32 FAILED: self-claim did not assign the calling reviewer';
  end if;
  raise notice 'TEST 32 PASSED: an unassigned, permitted reviewer can self-claim an active round';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 33: RLS — clinician cannot read reviews, findings, page reviews, or
-- events; a permitted role (organization_admin) can.
-- ---------------------------------------------------------------------------
do $$
declare v_reviews int;
declare v_findings int;
declare v_page_reviews int;
declare v_events int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  select count(*) into v_reviews from document_extraction_reviews where extraction_run_id = fx('run_1_id');
  select count(*) into v_findings from document_extraction_review_findings where extraction_run_id = fx('run_1_id');
  select count(*) into v_page_reviews from document_extraction_page_reviews where extraction_review_id = fx('review_1_id');
  select count(*) into v_events from document_extraction_review_events where extraction_review_id = fx('review_1_id');

  set local role none;

  if v_reviews <> 0 or v_findings <> 0 or v_page_reviews <> 0 or v_events <> 0 then
    raise exception 'TEST 33 FAILED: clinician could read review data (reviews=%, findings=%, page_reviews=%, events=%)', v_reviews, v_findings, v_page_reviews, v_events;
  end if;
  raise notice 'TEST 33 PASSED: clinician denied all extraction-review reads';
end
$$;

do $$
declare v_reviews int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select count(*) into v_reviews from document_extraction_reviews where extraction_run_id = fx('run_1_id');
  set local role none;

  if v_reviews = 0 then
    raise exception 'TEST 33b FAILED: organization_admin could not read its own organization''s extraction reviews';
  end if;
  raise notice 'TEST 33b PASSED: a permitted role (organization_admin) can read extraction review data';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 34: RLS — cross-tenant denial. admin_beta (Org Beta) cannot read
-- Org Alpha's extraction reviews.
-- ---------------------------------------------------------------------------
do $$
declare v_reviews int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
  set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

  select count(*) into v_reviews from document_extraction_reviews where extraction_run_id = fx('run_1_id');
  set local role none;

  if v_reviews <> 0 then
    raise exception 'TEST 34 FAILED: a cross-tenant admin (Org Beta) could read Org Alpha''s extraction reviews';
  end if;
  raise notice 'TEST 34 PASSED: cross-tenant extraction review reads are denied';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 35: trust boundary — authenticated cannot call any function while
-- lacking the specific required permission (a clinician calling the
-- reviewer-only submit function directly, bypassing the UI entirely).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  begin
    perform submit_document_extraction_review(fx('review_2_id'), 'accepted', null, null);
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 35 FAILED: a clinician submitted an extraction review decision directly';
  end if;
  raise notice 'TEST 35 PASSED: a clinician cannot call submit_document_extraction_review directly';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 36: anon (where it exists — hosted/real Supabase; skipped on the
-- plain Postgres CI container, which has no anon role at all) cannot read
-- extraction reviews at all — no grant was ever issued to anon.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    raise notice 'TEST 36 SKIPPED: no anon role on this database (expected locally)';
  else
    begin
      set local role anon;
      perform count(*) from document_extraction_reviews;
      set local role none;
    exception when others then
      set local role none;
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 36 FAILED: anon could read extraction reviews';
    end if;
    raise notice 'TEST 36 PASSED: anon is denied (no grant) on document_extraction_reviews';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 37: findings cannot be deleted (trigger-enforced, defense in depth
-- beyond the missing DELETE RLS policy).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    delete from document_extraction_review_findings where id = fx('finding_1_id');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 37 FAILED: a finding was deleted';
  end if;
  raise notice 'TEST 37 PASSED: findings cannot be deleted';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 38: a finding's core content is immutable once created — only
-- status/resolution fields may be updated (already proven functionally by
-- update_extraction_finding_status; this proves the trigger blocks a raw
-- content edit too).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    update document_extraction_review_findings set severity = 'critical' where id = fx('finding_1_id');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 38 FAILED: a finding''s severity was mutated directly';
  end if;
  raise notice 'TEST 38 PASSED: a finding''s core content is immutable once created';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 39: document_extraction_review_events is append-only — a direct
-- UPDATE/DELETE is rejected without the maintenance override GUC set.
-- ---------------------------------------------------------------------------
do $$
declare v_event_id uuid;
declare v_failed boolean := false;
begin
  select id into v_event_id from document_extraction_review_events where extraction_review_id = fx('review_1_id') limit 1;
  begin
    update document_extraction_review_events set reason = 'tampered' where id = v_event_id;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 39 FAILED: a review event was mutated without the maintenance override';
  end if;
  raise notice 'TEST 39 PASSED: document_extraction_review_events is append-only';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 40: get_document_extraction_review_eligibility on a run with no
-- review at all reports ineligible for everything (no accepted decision
-- ever recorded).
-- ---------------------------------------------------------------------------
do $$
declare elig record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into elig from get_document_extraction_review_eligibility(fx('run_running_id'));
  set local role none;

  if elig.out_eligible_for_ocr <> false or elig.out_eligible_for_chunking <> false or elig.out_eligible_for_retrieval <> false then
    raise exception 'TEST 40 FAILED: a run with no accepted review reported some eligibility, got %', row_to_json(elig);
  end if;
  raise notice 'TEST 40 PASSED: no review at all -> no downstream eligibility';
end
$$;

do $$
begin
  raise notice 'ALL EXTRACTION REVIEW QUALITY GATE TESTS PASSED';
end
$$;

drop function fx(text);
drop function fxt(text);
drop function test_fixture_set(text, uuid);
drop function test_text_fixture_set(text, text);
