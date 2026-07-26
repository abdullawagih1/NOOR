-- ============================================================================
-- Noor V1 RLS + Idempotency Test Suite — Secure Document Intake (migration 0006)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 005_document_intake.sql
-- Depends on 001-004 already having run in this database (authenticated
-- role, seed fixtures, reviewer.alpha/quality.alpha from 003).
-- ============================================================================

\set ON_ERROR_STOP on

grant select on guideline_source_documents, document_upload_sessions,
  document_processing_jobs, document_processing_attempts, document_intake_events
  to authenticated;
revoke insert, update, delete on guideline_source_documents, document_upload_sessions,
  document_processing_jobs, document_processing_attempts, document_intake_events
  from authenticated;

grant execute on function
  create_guideline_upload_session(uuid, text, text, bigint, text, text, uuid),
  complete_guideline_upload(uuid, text, bigint, text, text, uuid),
  cancel_upload_session(uuid, text, uuid),
  quarantine_guideline_source_document(uuid, text, uuid),
  cancel_processing_job(uuid, text, uuid)
  to authenticated;

create temporary table test_fixtures (key text primary key, value uuid not null);

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

-- Fake but well-formed SHA-256 hex digest used across TEST 6-8 (deliberately
-- reused across documents to exercise duplicate detection). Written as a
-- literal everywhere it's needed rather than a psql variable — psql's
-- `:'var'`/`:var` substitution does not interpolate inside dollar-quoted
-- `DO $$ ... $$` bodies (confirmed the hard way in 003/004), and several
-- uses below are inside DO blocks.
-- 'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111'

-- ----------------------------------------------------------------------------
-- FIXTURE: a domain/authority/guideline with two versions — one that stays
-- draft, one taken all the way to active — both owned by admin.alpha.
-- ----------------------------------------------------------------------------

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('domain_id', id) from create_clinical_domain(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'intake-domain', 'Intake Test Domain', null
  );
  select test_fixture_set('authority_id', id) from create_guideline_authority(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Intake Test Authority', null, null, null, null, true, null
  );
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline_id', id) from create_guideline(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'INTAKE-001', 'Intake Test Guideline'
  );
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('version_draft_id', id) from create_guideline_version(fx('guideline_id'), 'v1.0-draft');
  select test_fixture_set('version_active_id', id) from create_guideline_version(fx('guideline_id'), 'v1.0-active');
  select transition_guideline_version(fx('version_active_id'), 'ready_for_review');
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  select submit_guideline_review(fx('version_active_id'), 'recommended_for_approval', 'Intake fixture review');
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select transition_guideline_version(fx('version_active_id'), 'approved');
  select transition_guideline_version(fx('version_active_id'), 'active');
commit;

do $$ begin raise notice 'FIXTURE READY: guideline with a draft version and an active version'; end $$;

-- ---------------------------------------------------------------------------
-- TEST 1: admin.alpha creates an upload session for the draft version.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('session1_id', upload_session_id), test_fixture_set('document1_id', source_document_id)
    from create_guideline_upload_session(fx('version_draft_id'), 'guideline.pdf', 'application/pdf', 120000, null, 'test-key-1');
commit;

do $$
declare v_status text;
begin
  select status into v_status from document_upload_sessions where id = fx('session1_id');
  if v_status <> 'authorized' then
    raise exception 'TEST 1 FAILED: expected session status authorized, got %', v_status;
  end if;
  raise notice 'TEST 1 PASSED: upload session created and authorized for an eligible (draft) version';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 2: an active (released) version is not eligible for a new upload.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform create_guideline_upload_session(fx('version_active_id'), 'replacement.pdf', 'application/pdf', 1000, null, null);
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 2 FAILED: an active guideline version accepted a new upload session';
    end if;
    raise notice 'TEST 2 PASSED: active (released) version rejects a new source upload';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 3: cross-tenant denial — admin.beta cannot create an upload session
-- for org Alpha's draft version.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
  set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform create_guideline_upload_session(fx('version_draft_id'), 'cross-tenant.pdf', 'application/pdf', 1000, null, null);
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 3 FAILED: admin.beta created an upload session for org Alpha''s guideline version';
    end if;
    raise notice 'TEST 3 PASSED: cross-tenant upload-session creation denied';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 4: idempotent session creation — replaying the same idempotency_key
-- returns the SAME session, not a new one.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_session_id uuid;
  begin
    select upload_session_id into v_session_id
      from create_guideline_upload_session(fx('version_draft_id'), 'guideline.pdf', 'application/pdf', 120000, null, 'test-key-1');
    if v_session_id <> fx('session1_id') then
      raise exception 'TEST 4 FAILED: replaying idempotency_key created a different session (% vs %)', v_session_id, fx('session1_id');
    end if;
    raise notice 'TEST 4 PASSED: replayed idempotency_key returned the existing session';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 5: a second, non-idempotent upload session for the SAME version
-- (which already has an active pending_upload primary) is rejected.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform create_guideline_upload_session(fx('version_draft_id'), 'second-attempt.pdf', 'application/pdf', 1000, null, null);
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 5 FAILED: a second concurrent primary upload session was accepted for the same version';
    end if;
    raise notice 'TEST 5 PASSED: one active primary source per version enforced at session creation';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 6: completion — verified, registered, and a queued job created.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('job1_id', processing_job_id), document_status, session_status
    from complete_guideline_upload(fx('session1_id'), 'application/pdf', 120000, 'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111', null);
commit;

do $$
declare v_doc_status text;
declare v_session_status text;
declare v_job_status text;
begin
  select status into v_doc_status from guideline_source_documents where id = fx('document1_id');
  select status into v_session_status from document_upload_sessions where id = fx('session1_id');
  select status into v_job_status from document_processing_jobs where id = fx('job1_id');
  if v_doc_status <> 'registered' then raise exception 'TEST 6 FAILED: expected document registered, got %', v_doc_status; end if;
  if v_session_status <> 'completed' then raise exception 'TEST 6 FAILED: expected session completed, got %', v_session_status; end if;
  if v_job_status <> 'queued' then raise exception 'TEST 6 FAILED: expected job queued, got %', v_job_status; end if;
  raise notice 'TEST 6 PASSED: upload verified, registered, and a queued processing job created';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 7: idempotent completion — replaying against the now-completed
-- session does not create a second job.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_job_id uuid;
  declare v_job_count int;
  begin
    select processing_job_id into v_job_id from complete_guideline_upload(fx('session1_id'), 'application/pdf', 120000, 'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111', null);
    if v_job_id <> fx('job1_id') then
      raise exception 'TEST 7 FAILED: replayed completion returned a different job (% vs %)', v_job_id, fx('job1_id');
    end if;
    select count(*) into v_job_count from document_processing_jobs where source_document_id = fx('document1_id');
    if v_job_count <> 1 then
      raise exception 'TEST 7 FAILED: expected exactly 1 job after replay, found %', v_job_count;
    end if;
    raise notice 'TEST 7 PASSED: repeated completion is idempotent (no duplicate job)';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 8: cross-version, same-organization duplicate is ALLOWED and
-- explicitly recorded (not rejected).
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline2_id', id) from create_guideline(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'), 'INTAKE-002', 'Second Intake Guideline'
  );
  select test_fixture_set('version_draft2_id', id) from create_guideline_version(fx('guideline2_id'), 'v1.0');
  select test_fixture_set('session2_id', upload_session_id), test_fixture_set('document2_id', source_document_id)
    from create_guideline_upload_session(fx('version_draft2_id'), 'reused.pdf', 'application/pdf', 120000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_status text;
  declare v_dup_event_count int;
  begin
    select document_status into v_status from complete_guideline_upload(fx('session2_id'), 'application/pdf', 120000, 'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111', null);
    if v_status <> 'registered' then
      raise exception 'TEST 8 FAILED: expected a cross-version same-org duplicate to be allowed (registered), got %', v_status;
    end if;
    select count(*) into v_dup_event_count from document_intake_events
      where source_document_id = fx('document2_id') and event_type = 'guideline_document.duplicate_detected';
    if v_dup_event_count <> 1 then
      raise exception 'TEST 8 FAILED: expected the duplicate to be explicitly recorded, found % events', v_dup_event_count;
    end if;
    raise notice 'TEST 8 PASSED: cross-version same-organization duplicate allowed and explicitly recorded';
  end
  $$;
commit;

-- ---------------------------------------------------------------------------
-- TEST 9: RLS — clinician cannot read any intake records; a privileged
-- role (admin.alpha, guideline_documents.read) can.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_docs int;
  declare v_sessions int;
  declare v_jobs int;
  begin
    select count(*) into v_docs from guideline_source_documents where id = fx('document1_id');
    select count(*) into v_sessions from document_upload_sessions where id = fx('session1_id');
    select count(*) into v_jobs from document_processing_jobs where id = fx('job1_id');
    if v_docs <> 0 or v_sessions <> 0 or v_jobs <> 0 then
      raise exception 'TEST 9 FAILED: clinician could read intake records (docs=%, sessions=%, jobs=%)', v_docs, v_sessions, v_jobs;
    end if;
    raise notice 'TEST 9 PASSED: clinician cannot read any document-intake records';
  end
  $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_docs int;
  begin
    select count(*) into v_docs from guideline_source_documents where id = fx('document1_id');
    if v_docs <> 1 then
      raise exception 'TEST 9b FAILED: admin.alpha (guideline_documents.read) could not read the source document';
    end if;
    raise notice 'TEST 9b PASSED: guideline_documents.read holder can read intake records';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 10: suspended and removed memberships denied.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
  set local request.jwt.claims = '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from guideline_source_documents where id = fx('document1_id');
    if v_count <> 0 then
      raise exception 'TEST 10 FAILED: suspended member could read intake records';
    end if;
    raise notice 'TEST 10 PASSED: suspended membership denied intake read access';
  end
  $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
  set local request.jwt.claims = '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from guideline_source_documents where id = fx('document1_id');
    if v_count <> 0 then
      raise exception 'TEST 10b FAILED: removed member could read intake records';
    end if;
    raise notice 'TEST 10b PASSED: removed membership denied intake read access';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 11: a registered document's file identity is immutable via raw
-- UPDATE, regardless of role (bare statement — bypasses RLS/grants
-- entirely, isolating the trigger from the permission layer).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    update guideline_source_documents set sha256 = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef' where id = fx('document1_id');
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 11 FAILED: a registered document''s checksum was mutated';
  end if;
  raise notice 'TEST 11 PASSED: registered document file identity is immutable';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 12: quarantine cascades — cancels the document's active job too.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_doc_status text;
  declare v_job_status text;
  begin
    perform quarantine_guideline_source_document(fx('document1_id'), 'Discovered issue during RLS test');
    select status into v_doc_status from guideline_source_documents where id = fx('document1_id');
    select status into v_job_status from document_processing_jobs where id = fx('job1_id');
    if v_doc_status <> 'quarantined' then raise exception 'TEST 12 FAILED: expected quarantined, got %', v_doc_status; end if;
    if v_job_status <> 'cancelled' then raise exception 'TEST 12 FAILED: expected cascaded job cancellation, got %', v_job_status; end if;
    raise notice 'TEST 12 PASSED: quarantine cascades to cancel the active processing job';
  end
  $$;
commit;

-- ---------------------------------------------------------------------------
-- TEST 13: after rejection/quarantine, a NEW upload session for the same
-- version is allowed (retry path) — proves TEST 5's block was about the
-- ACTIVE primary, not a permanent per-version lock.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_new_session_id uuid;
  begin
    select upload_session_id into v_new_session_id
      from create_guideline_upload_session(fx('version_draft_id'), 'retry.pdf', 'application/pdf', 1000, null, null);
    if v_new_session_id is null then
      raise exception 'TEST 13 FAILED: retry upload session was not created';
    end if;
    raise notice 'TEST 13 PASSED: a new upload session is allowed after the prior primary was quarantined';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 14: cancel_upload_session — a created/authorized session can be
-- cancelled by its creator; the pending document is rejected too.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('session3_id', upload_session_id), test_fixture_set('document3_id', source_document_id)
    from create_guideline_upload_session(fx('version_draft_id'), 'to-cancel.pdf', 'application/pdf', 1000, null, null);
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_session_status text;
  declare v_doc_status text;
  begin
    perform cancel_upload_session(fx('session3_id'), 'changed my mind');
    select status into v_session_status from document_upload_sessions where id = fx('session3_id');
    select status into v_doc_status from guideline_source_documents where id = fx('document3_id');
    if v_session_status <> 'cancelled' then raise exception 'TEST 14 FAILED: expected cancelled session, got %', v_session_status; end if;
    if v_doc_status <> 'rejected' then raise exception 'TEST 14 FAILED: expected rejected document, got %', v_doc_status; end if;
    raise notice 'TEST 14 PASSED: cancel_upload_session cancels the session and rejects the pending document';
  end
  $$;
commit;

-- ---------------------------------------------------------------------------
-- TEST 15: cancel_processing_job — only a queued job can be cancelled;
-- unauthorized (clinician) cancellation is denied.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform cancel_processing_job(fx('job1_id'), 'unauthorized attempt');
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 15 FAILED: clinician (lacking guideline_processing_jobs.cancel) cancelled a job';
    end if;
    raise notice 'TEST 15 PASSED: unauthorized job cancellation denied';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 16: append-only document_intake_events — UPDATE blocked without the
-- documented maintenance override.
-- ---------------------------------------------------------------------------
do $$
declare v_event_id uuid;
declare v_mutated boolean := false;
begin
  select id into v_event_id from document_intake_events where source_document_id = fx('document1_id') limit 1;
  begin
    update document_intake_events set metadata = '{"tampered":true}'::jsonb where id = v_event_id;
    v_mutated := true;
  exception when others then
    v_mutated := false;
  end;
  if v_mutated then
    raise exception 'TEST 16 FAILED: document_intake_events was mutated without the maintenance override';
  end if;
  raise notice 'TEST 16 PASSED: document_intake_events UPDATE blocked without the maintenance override';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 17: audit_events recorded across the intake flow for document1.
-- ---------------------------------------------------------------------------
do $$
declare v_count int;
begin
  select count(*) into v_count from audit_events
    where resource_type = 'guideline_source_document' and resource_id = fx('document1_id')
      and event_type in (
        'guideline_document.upload_session_created', 'guideline_document.upload_authorized',
        'guideline_document.verified', 'guideline_document.registered', 'guideline_document.rejected'
      );
  if v_count < 5 then
    raise exception 'TEST 17 FAILED: expected at least 5 audit_events rows for document1 (created/authorized/verified/registered/quarantine-rejected), found %', v_count;
  end if;
  raise notice 'TEST 17 PASSED: audit_events recorded across the intake flow (% rows)', v_count;
end
$$;

drop function fx(text);
drop function test_fixture_set(text, uuid);

\echo 'ALL DOCUMENT INTAKE TESTS PASSED'
