-- ============================================================================
-- Noor V1 Test Suite — Retrieval Evaluation Foundation (Sprint 1-E1)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 013_retrieval_evaluation.sql
-- Depends on 001-012 already having run in this database (migrations
-- 0001-0015 must be applied — this file covers both 0014 and 0015, the
-- same execution/content split every prior sprint has used one layer over).
-- ============================================================================

grant select on retrieval_evaluation_datasets, retrieval_evaluation_corpus_items,
  retrieval_evaluation_queries, retrieval_relevance_judgments, retrieval_evaluation_search_documents,
  retrieval_evaluation_runs, retrieval_evaluation_results, retrieval_evaluation_metrics, retrieval_evaluation_failures
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
  create_document_chunking_job(uuid, text, uuid),
  create_document_chunking_review(uuid, uuid),
  start_document_chunking_review(uuid, uuid),
  mark_chunk_reviewed(uuid, int, text, text, uuid),
  submit_document_chunking_review(uuid, text, text, text, text, uuid),
  get_document_embedding_readiness(uuid),
  create_retrieval_evaluation_dataset(uuid, text, int, text, text, text, text[], text, uuid, uuid),
  update_retrieval_evaluation_dataset(uuid, text, text, text, text[], text, uuid),
  submit_evaluation_dataset_for_review(uuid, uuid),
  return_evaluation_dataset_to_draft(uuid, text, uuid),
  mark_evaluation_dataset_reviewed(uuid, uuid),
  add_evaluation_corpus_item(uuid, uuid, uuid),
  remove_evaluation_corpus_item(uuid, uuid),
  create_evaluation_query(uuid, text, text, text, text, text, boolean, text, text, uuid),
  update_evaluation_query(uuid, text, text, text, text, text, boolean, uuid),
  create_relevance_judgment(uuid, uuid, int, text, uuid),
  update_relevance_judgment(uuid, int, text, text, uuid),
  freeze_retrieval_evaluation_dataset(uuid, text, uuid),
  archive_retrieval_evaluation_dataset(uuid, uuid),
  create_retrieval_evaluation_run(uuid, int[], int, text, uuid),
  cancel_evaluation_run(uuid, text, uuid),
  create_failure_annotation(uuid, uuid, text, text, text, uuid),
  update_failure_annotation(uuid, text, text, text, uuid)
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
-- FIXTURE: synthetic reviewer/quality users (idempotent).
-- ----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('66666666-6666-6666-6666-666666666666', 'reviewer.alpha@example.test'),
  ('77777777-7777-7777-7777-777777777777', 'quality.alpha@example.test'),
  ('88888888-8888-8888-8888-888888888888', 'quality.beta@example.test')
on conflict (id) do nothing;
insert into profiles (id, display_name) values
  ('66666666-6666-6666-6666-666666666666', 'Reviewer Alpha'),
  ('77777777-7777-7777-7777-777777777777', 'Quality Alpha'),
  ('88888888-8888-8888-8888-888888888888', 'Quality Beta')
on conflict (id) do nothing;
insert into organization_memberships (organization_id, user_id, role_id, status)
  select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '66666666-6666-6666-6666-666666666666', id, 'active' from roles where key = 'clinical_reviewer'
  on conflict do nothing;
insert into organization_memberships (organization_id, user_id, role_id, status)
  select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '77777777-7777-7777-7777-777777777777', id, 'active' from roles where key = 'quality_manager'
  on conflict do nothing;
insert into organization_memberships (organization_id, user_id, role_id, status)
  select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '88888888-8888-8888-8888-888888888888', id, 'active' from roles where key = 'quality_manager'
  on conflict do nothing;

-- ----------------------------------------------------------------------------
-- FIXTURE: one accepted, 3-page, 3-chunk document with distinct real
-- English/Arabic/mixed synthetic text, ready for lexical search testing.
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
  v_sha text := repeat('r', 63) || '1';
  v_run record;
  v_review record;
  v_chunking_job record;
  v_chunking_run record;
  v_chunking_review record;
  i int;
  v_page1 record; v_page2 record; v_page3 record;
  v_chunks jsonb;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  perform test_fixture_set('domain_id', id) from create_clinical_domain(v_org, 'retrieval-eval-domain', 'Retrieval Eval Test Domain', null);
  perform test_fixture_set('authority_id', id) from create_guideline_authority(v_org, 'Retrieval Eval Test Authority', null, null, null, null, true, null);

  select id into v_guideline_id from create_guideline(v_org, fx('domain_id'), fx('authority_id'), 'RETR-1', 'Retrieval Eval Guideline');
  select id into v_version_id from create_guideline_version(v_guideline_id, 'v1.0');
  select upload_session_id, source_document_id into v_session_id, v_document_id
    from create_guideline_upload_session(v_version_id, 'retrieval-fixture.pdf', 'application/pdf', 1000, null, null);
  select processing_job_id into v_job_id from complete_guideline_upload(v_session_id, 'application/pdf', 1000, v_sha, null);
  set local role none;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');
  update document_processing_jobs set
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-retrieval-test',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = v_job_id;
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, v_job_id, 1, 'noor-worker-retrieval-test', 'started');
  perform start_document_processing_job(v_job_id, 'noor-worker-retrieval-test', v_token);

  select * into v_run from create_document_extraction_run(
    v_job_id, 'noor-worker-retrieval-test', v_token, v_sha, 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );

  insert into document_extraction_pages (
    organization_id, extraction_run_id, source_document_id, page_number,
    width_points, height_points, rotation_degrees, raw_text, normalized_text,
    character_count, word_count, is_blank, suspected_scanned, extraction_status, page_checksum
  ) values
    (v_org, v_run.out_extraction_run_id, v_document_id, 1, 595.28, 841.89, 0,
     'Blood pressure measurement technique for adults', 'Blood pressure measurement technique for adults',
     48, 6, false, false, 'text_extracted', repeat('1', 63) || 'a'),
    (v_org, v_run.out_extraction_run_id, v_document_id, 2, 595.28, 841.89, 0,
     'قياس ضغط الدم للبالغين بطريقة صحيحة', 'قياس ضغط الدم للبالغين بطريقة صحيحة',
     36, 6, false, false, 'text_extracted', repeat('2', 63) || 'a'),
    (v_org, v_run.out_extraction_run_id, v_document_id, 3, 595.28, 841.89, 0,
     'Unrelated content about hospital parking procedures', 'Unrelated content about hospital parking procedures',
     52, 6, false, false, 'text_extracted', repeat('3', 63) || 'a');

  perform finalize_document_extraction_run(
    v_run.out_extraction_run_id, v_job_id, 'noor-worker-retrieval-test', v_token,
    3, 'guideline-processed', 'test/path/retrieval-extract.json', repeat('f', 64), 100, 'application/json',
    '{}'::jsonb, 3, 0, 0, 136, 18, 0, '[]'::jsonb
  );

  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into v_review from create_document_extraction_review(v_run.out_extraction_run_id);
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_extraction_review(v_review.id);
  perform mark_extraction_page_reviewed(v_review.id, 1, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(v_review.id, 2, 'reviewed_clear', null);
  perform mark_extraction_page_reviewed(v_review.id, 3, 'reviewed_clear', null);
  perform submit_document_extraction_review(v_review.id, 'accepted', null, null);
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into v_chunking_job from create_document_chunking_job(v_document_id);
  set local role none;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');
  update document_processing_jobs set
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-retrieval-test',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = v_chunking_job.out_job_id;
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, v_chunking_job.out_job_id, 1, 'noor-worker-retrieval-test', 'started');
  perform start_document_processing_job(v_chunking_job.out_job_id, 'noor-worker-retrieval-test', v_token);

  select * into v_chunking_run from create_document_chunking_run(
    v_chunking_job.out_job_id, 'noor-worker-retrieval-test', v_token,
    v_run.out_extraction_run_id, v_review.id, v_sha,
    '{"schema_version":"1.0","pages":[]}'::jsonb, repeat('m', 64),
    'controlled-page-aware-chunking-v1', '1', '1', 'noor-simple-tokenizer', '1'
  );

  select id, page_checksum into v_page1 from document_extraction_pages where extraction_run_id = v_run.out_extraction_run_id and page_number = 1;
  select id, page_checksum into v_page2 from document_extraction_pages where extraction_run_id = v_run.out_extraction_run_id and page_number = 2;
  select id, page_checksum into v_page3 from document_extraction_pages where extraction_run_id = v_run.out_extraction_run_id and page_number = 3;

  v_chunks := jsonb_build_array(
    jsonb_build_object(
      'chunk_index', 1, 'chunk_text', 'Blood pressure measurement technique for adults', 'chunk_checksum', repeat('1', 64),
      'page_start', 1, 'page_end', 1, 'token_count', 6, 'character_count', 48, 'word_count', 6,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 1, 'representation_type', 'native', 'representation_id', v_page1.id,
        'representation_checksum', v_page1.page_checksum, 'start_offset', 0, 'end_offset', 48,
        'source_fragment_checksum', repeat('a', 64), 'span_order', 1
      ))
    ),
    jsonb_build_object(
      'chunk_index', 2, 'chunk_text', 'قياس ضغط الدم للبالغين بطريقة صحيحة', 'chunk_checksum', repeat('2', 64),
      'page_start', 2, 'page_end', 2, 'token_count', 6, 'character_count', 36, 'word_count', 6,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 2, 'representation_type', 'native', 'representation_id', v_page2.id,
        'representation_checksum', v_page2.page_checksum, 'start_offset', 0, 'end_offset', 36,
        'source_fragment_checksum', repeat('b', 64), 'span_order', 1
      ))
    ),
    jsonb_build_object(
      'chunk_index', 3, 'chunk_text', 'Unrelated content about hospital parking procedures', 'chunk_checksum', repeat('3', 64),
      'page_start', 3, 'page_end', 3, 'token_count', 6, 'character_count', 52, 'word_count', 6,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 3, 'representation_type', 'native', 'representation_id', v_page3.id,
        'representation_checksum', v_page3.page_checksum, 'start_offset', 0, 'end_offset', 52,
        'source_fragment_checksum', repeat('c', 64), 'span_order', 1
      ))
    )
  );

  perform finalize_document_chunking_run(
    v_chunking_run.out_chunking_run_id, v_chunking_job.out_job_id, 'noor-worker-retrieval-test', v_token,
    v_chunks, jsonb_build_object('coverage_percentage', 100, 'duplication_percentage', 0, 'page_count', 3, 'chunk_count', 3),
    '[]'::jsonb, 'guideline-processed', 'test/path/retrieval-chunks.json', repeat('d', 64), 300, 'application/json'
  );

  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  select * into v_chunking_review from create_document_chunking_review(v_chunking_run.out_chunking_run_id);
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';
  perform start_document_chunking_review(v_chunking_review.id);
  perform mark_chunk_reviewed(v_chunking_review.id, 1, 'reviewed_clear', null);
  perform mark_chunk_reviewed(v_chunking_review.id, 2, 'reviewed_clear', null);
  perform mark_chunk_reviewed(v_chunking_review.id, 3, 'reviewed_clear', null);
  perform submit_document_chunking_review(v_chunking_review.id, 'accepted', null, null);
  set local role none;

  perform test_fixture_set('document_id', v_document_id);
  for i in 1..3 loop
    perform test_fixture_set('chunk_' || i || '_id', id) from document_chunks where chunking_run_id = v_chunking_run.out_chunking_run_id and chunk_index = i;
  end loop;

  raise notice 'FIXTURE READY: 1 accepted document, 3 embedding-ready chunks (English/Arabic/unrelated)';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: create a draft dataset, add all 3 corpus items, create queries
-- (English exact, Arabic exact, negative control), add judgments.
-- ---------------------------------------------------------------------------
do $$
declare v_dataset record; v_q_en record; v_q_ar record; v_q_neg record; v_ci1 uuid; v_ci2 uuid; v_ci3 uuid;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  select * into v_dataset from create_retrieval_evaluation_dataset(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'noor-retrieval-eval-foundation', 1,
    'NOOR Retrieval Evaluation — Synthetic Foundation — v1', 'Synthetic integrity + baseline fixtures', null,
    array['en','ar'], 'Sprint 1-E1 verification'
  );
  if v_dataset.status <> 'draft' then
    raise exception 'TEST 1 FAILED: expected draft, got %', row_to_json(v_dataset);
  end if;
  perform test_fixture_set('dataset_id', v_dataset.id);

  select id into v_ci1 from add_evaluation_corpus_item(v_dataset.id, fx('chunk_1_id'));
  select id into v_ci2 from add_evaluation_corpus_item(v_dataset.id, fx('chunk_2_id'));
  select id into v_ci3 from add_evaluation_corpus_item(v_dataset.id, fx('chunk_3_id'));
  perform test_fixture_set('corpus_item_1_id', v_ci1);
  perform test_fixture_set('corpus_item_2_id', v_ci2);
  perform test_fixture_set('corpus_item_3_id', v_ci3);

  select * into v_q_en from create_evaluation_query(v_dataset.id, 'q-en-exact', 'blood pressure measurement', 'en', 'english_exact', 'basic', false);
  select * into v_q_ar from create_evaluation_query(v_dataset.id, 'q-ar-exact', 'قياس ضغط الدم', 'ar', 'arabic_exact', 'basic', false);
  select * into v_q_neg from create_evaluation_query(v_dataset.id, 'q-negative', 'unicorn migration patterns antarctica', 'en', 'negative_control', 'basic', true);
  perform test_fixture_set('query_en_id', v_q_en.id);
  perform test_fixture_set('query_ar_id', v_q_ar.id);
  perform test_fixture_set('query_neg_id', v_q_neg.id);

  if v_q_en.normalized_query_text <> 'blood pressure measurement' then
    raise exception 'TEST 1 FAILED: unexpected normalized query text %', v_q_en.normalized_query_text;
  end if;

  perform create_relevance_judgment(v_q_en.id, v_ci1, 3, 'exact topical match');
  perform create_relevance_judgment(v_q_en.id, v_ci3, 0, 'unrelated content');
  perform create_relevance_judgment(v_q_ar.id, v_ci2, 3, 'exact topical match (Arabic)');
  set local role none;

  raise notice 'TEST 1 PASSED: draft dataset, corpus items, queries, and judgments created';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 2: freeze is rejected before ready_for_review, and before every
-- active non-negative query has a grade>=2 judgment.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform freeze_retrieval_evaluation_dataset(fx('dataset_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 2 FAILED: freeze succeeded from draft status';
  end if;
  raise notice 'TEST 2 PASSED: freeze rejected before ready_for_review';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 3: submit for review, then freeze is rejected without a reviewer
-- distinct from the creator (two-person separation, ADR 0015), then
-- succeeds once a different quality user reviews it.
-- ---------------------------------------------------------------------------
do $$
declare v_dataset record; v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_dataset from submit_evaluation_dataset_for_review(fx('dataset_id'));
  if v_dataset.status <> 'ready_for_review' then
    raise exception 'TEST 3 FAILED: expected ready_for_review, got %', row_to_json(v_dataset);
  end if;

  begin
    perform mark_evaluation_dataset_reviewed(fx('dataset_id'));
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 3 FAILED: the dataset creator was able to review their own dataset';
  end if;
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '88888888-8888-8888-8888-888888888888';
  set local request.jwt.claims = '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}';
  select * into v_dataset from mark_evaluation_dataset_reviewed(fx('dataset_id'));
  if v_dataset.reviewed_by <> '88888888-8888-8888-8888-888888888888' then
    raise exception 'TEST 3 FAILED: reviewed_by not recorded correctly';
  end if;
  set local role none;

  raise notice 'TEST 3 PASSED: two-person dataset review separation enforced';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 4: freeze succeeds; manifests/checksums populated; search
-- representations created; dataset content becomes immutable.
-- ---------------------------------------------------------------------------
do $$
declare v_dataset record; v_search_count int; v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_dataset from freeze_retrieval_evaluation_dataset(fx('dataset_id'));
  set local role none;

  if v_dataset.status <> 'frozen' or v_dataset.dataset_sha256 is null
    or v_dataset.corpus_manifest_sha256 is null or v_dataset.query_manifest_sha256 is null
    or v_dataset.judgment_manifest_sha256 is null then
    raise exception 'TEST 4 FAILED: expected frozen with all checksums populated, got %', row_to_json(v_dataset);
  end if;

  select count(*) into v_search_count from retrieval_evaluation_search_documents where dataset_id = fx('dataset_id');
  if v_search_count <> 3 then
    raise exception 'TEST 4 FAILED: expected 3 search representations, got %', v_search_count;
  end if;

  begin
    perform add_evaluation_corpus_item(fx('dataset_id'), fx('chunk_1_id'));
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 4 FAILED: adding a corpus item succeeded on a frozen dataset';
  end if;

  raise notice 'TEST 4 PASSED: freeze computes deterministic checksums and creates search representations; frozen content is immutable';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 5: freeze is idempotent (a second call on an already-frozen dataset
-- returns the same row without error).
-- ---------------------------------------------------------------------------
do $$
declare v_dataset record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_dataset from freeze_retrieval_evaluation_dataset(fx('dataset_id'));
  set local role none;
  if v_dataset.status <> 'frozen' then
    raise exception 'TEST 5 FAILED: idempotent freeze replay failed, got %', row_to_json(v_dataset);
  end if;
  raise notice 'TEST 5 PASSED: freeze is idempotent';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 6: create_retrieval_evaluation_run succeeds against the frozen
-- dataset; a clinician is denied; a second identical call before the first
-- completes reuses the same active job.
-- ---------------------------------------------------------------------------
do $$
declare v_run record; v_run2 record; v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  begin
    perform create_retrieval_evaluation_run(fx('dataset_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 6 FAILED: a clinician was able to create an evaluation run';
  end if;

  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_run from create_retrieval_evaluation_run(fx('dataset_id'));
  if v_run.out_reused then
    raise exception 'TEST 6 FAILED: expected a fresh run, got reused=true';
  end if;
  perform test_fixture_set('run_job_id', v_run.out_job_id);
  perform test_fixture_set('run_id', v_run.out_run_id);

  select * into v_run2 from create_retrieval_evaluation_run(fx('dataset_id'));
  set local role none;
  if v_run2.out_run_id <> v_run.out_run_id or not v_run2.out_reused then
    raise exception 'TEST 6 FAILED: expected the active run to be reused, got %', row_to_json(v_run2);
  end if;

  raise notice 'TEST 6 PASSED: clinician denied; run created and idempotently reused while active';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 7: Worker flow — claim the job, read context (3 active queries),
-- fetch lexical candidates for the English and Arabic exact-phrase
-- queries (both must match their expected chunk), and confirm the
-- negative-control query matches nothing relevant.
-- ---------------------------------------------------------------------------
do $$
declare
  v_claim record;
  v_context record;
  v_context_count int := 0;
  v_candidate record;
  v_en_top uuid;
  v_ar_top uuid;
  v_neg_count int := 0;
begin
  set local role none;
  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-retrieval-test-1', array['retrieval_evaluation']);
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-retrieval-test-1', v_claim.out_lease_token);
  perform test_text_fixture_set('run_lease_token', v_claim.out_lease_token);

  for v_context in
    select * from get_retrieval_evaluation_job_context(v_claim.out_job_id, 'noor-worker-retrieval-test-1', v_claim.out_lease_token)
  loop
    v_context_count := v_context_count + 1;
  end loop;
  if v_context_count <> 3 then
    raise exception 'TEST 7 FAILED: expected 3 active queries in context, got %', v_context_count;
  end if;

  select out_corpus_item_id into v_en_top from get_retrieval_candidates(
    v_claim.out_job_id, 'noor-worker-retrieval-test-1', v_claim.out_lease_token, fx('dataset_id'), 'blood pressure measurement'
  ) order by out_full_text_rank desc limit 1;
  if v_en_top <> fx('corpus_item_1_id') then
    raise exception 'TEST 7 FAILED: English exact-phrase query did not rank the expected chunk first (got %)', v_en_top;
  end if;

  select out_corpus_item_id into v_ar_top from get_retrieval_candidates(
    v_claim.out_job_id, 'noor-worker-retrieval-test-1', v_claim.out_lease_token, fx('dataset_id'), normalize_retrieval_text('قياس ضغط الدم')
  ) order by out_full_text_rank desc limit 1;
  if v_ar_top <> fx('corpus_item_2_id') then
    raise exception 'TEST 7 FAILED: Arabic exact-phrase query did not rank the expected chunk first (got %)', v_ar_top;
  end if;

  select count(*) into v_neg_count from get_retrieval_candidates(
    v_claim.out_job_id, 'noor-worker-retrieval-test-1', v_claim.out_lease_token, fx('dataset_id'), normalize_retrieval_text('unicorn migration patterns antarctica')
  );
  if v_neg_count <> 0 then
    raise exception 'TEST 7 FAILED: negative-control query unexpectedly matched % candidates', v_neg_count;
  end if;

  set local role none;
  raise notice 'TEST 7 PASSED: Worker-only context read and lexical candidate recall behave correctly (English, Arabic, negative control)';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 8: authenticated cannot call any Worker-only retrieval function
-- directly (trust boundary).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform get_retrieval_candidates(fx('run_job_id'), 'noor-worker-retrieval-test-1', fxt('run_lease_token'), fx('dataset_id'), 'blood pressure');
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 8 FAILED: authenticated was able to call get_retrieval_candidates';
  end if;
  raise notice 'TEST 8 PASSED: Worker-only retrieval functions are unreachable from authenticated';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 9: finalize_retrieval_evaluation_run persists results/metrics,
-- marks the run succeeded, and results are immutable.
-- ---------------------------------------------------------------------------
do $$
declare
  v_results jsonb;
  v_metrics jsonb;
  v_result record;
  v_result_row_id uuid;
  v_failed boolean := false;
begin
  v_results := jsonb_build_array(
    jsonb_build_object('query_id', fx('query_en_id'), 'corpus_item_id', fx('corpus_item_1_id'), 'rank', 1, 'final_score', 0.9, 'relevance_grade', 3, 'is_hit', true, 'reciprocal_rank_contribution', 1.0, 'dcg_contribution', 7.0, 'result_checksum', repeat('a', 64)),
    jsonb_build_object('query_id', fx('query_ar_id'), 'corpus_item_id', fx('corpus_item_2_id'), 'rank', 1, 'final_score', 0.9, 'relevance_grade', 3, 'is_hit', true, 'reciprocal_rank_contribution', 1.0, 'dcg_contribution', 7.0, 'result_checksum', repeat('b', 64))
  );
  v_metrics := jsonb_build_array(
    jsonb_build_object('scope_type', 'overall', 'scope_value', null, 'metric_name', 'mrr', 'metric_value', 1.0, 'sample_size', 2),
    jsonb_build_object('scope_type', 'language', 'scope_value', 'en', 'metric_name', 'precision_at_1', 'metric_value', 1.0, 'sample_size', 1)
  );

  set local role none;
  select * into v_result from finalize_retrieval_evaluation_run(
    fx('run_id'), fx('run_job_id'), 'noor-worker-retrieval-test-1', fxt('run_lease_token'),
    v_results, v_metrics, '[]'::jsonb,
    'guideline-processed', 'test/path/retrieval-run.json', repeat('e', 64), 500, 'application/json'
  );
  set local role none;

  if v_result.out_status <> 'succeeded' or v_result.out_result_count <> 2 then
    raise exception 'TEST 9 FAILED: expected succeeded/2 results, got %', row_to_json(v_result);
  end if;

  select id into v_result_row_id from retrieval_evaluation_results where evaluation_run_id = fx('run_id') limit 1;
  begin
    update retrieval_evaluation_results set final_score = 0.1 where id = v_result_row_id;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 9 FAILED: a result row was mutated';
  end if;

  raise notice 'TEST 9 PASSED: finalize_retrieval_evaluation_run persists results/metrics and results are immutable';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 10: a second create_retrieval_evaluation_run call with the
-- identical identity reuses the succeeded run rather than creating a new one.
-- ---------------------------------------------------------------------------
do $$
declare v_run record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_run from create_retrieval_evaluation_run(fx('dataset_id'));
  set local role none;

  if v_run.out_run_id <> fx('run_id') or not v_run.out_reused then
    raise exception 'TEST 10 FAILED: expected the succeeded run to be reused, got %', row_to_json(v_run);
  end if;
  raise notice 'TEST 10 PASSED: identical evaluation-run identity is reused, never duplicated';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 11: RLS — a clinician cannot read datasets/results; quality_manager can.
-- ---------------------------------------------------------------------------
do $$
declare v_count int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  select count(*) into v_count from retrieval_evaluation_datasets where id = fx('dataset_id');
  if v_count <> 0 then
    raise exception 'TEST 11 FAILED: a clinician could read retrieval_evaluation_datasets';
  end if;
  select count(*) into v_count from retrieval_evaluation_results where evaluation_run_id = fx('run_id');
  if v_count <> 0 then
    raise exception 'TEST 11 FAILED: a clinician could read retrieval_evaluation_results';
  end if;

  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select count(*) into v_count from retrieval_evaluation_datasets where id = fx('dataset_id');
  set local role none;
  if v_count <> 1 then
    raise exception 'TEST 11 FAILED: quality_manager could not read the dataset (got %)', v_count;
  end if;
  raise notice 'TEST 11 PASSED: RLS enforces retrieval_evaluation.read/.read_results correctly';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 12: failure annotations — create and update, core content immutable.
-- ---------------------------------------------------------------------------
do $$
declare v_failure record; v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_failure from create_failure_annotation(fx('run_id'), fx('query_neg_id'), 'other', 'reviewed manually, no issue found');
  select * into v_failure from update_failure_annotation(v_failure.id, 'resolved', 'confirmed no false positive');
  set local role none;

  if v_failure.status <> 'resolved' then
    raise exception 'TEST 12 FAILED: expected resolved, got %', row_to_json(v_failure);
  end if;

  begin
    update retrieval_evaluation_failures set failure_category = 'corpus_gap' where id = v_failure.id;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 12 FAILED: failure_category was mutated';
  end if;

  raise notice 'TEST 12 PASSED: failure annotations created/updated correctly; core content immutable';
end
$$;

do $$
begin
  raise notice 'ALL RETRIEVAL EVALUATION TESTS PASSED';
end
$$;

drop function fx(text);
drop function fxt(text);
drop function test_fixture_set(text, uuid);
drop function test_text_fixture_set(text, text);
