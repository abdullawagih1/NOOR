-- ============================================================================
-- Noor V1 Test Suite — Embedding and Vector Index Foundation (Sprint 1-E2)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 014_embedding_and_vector_evaluation.sql
-- Requires a pgvector-enabled Postgres (pgvector/pgvector:pg16 locally,
-- matching CI's postgres service image) — migrations 0001-0017 already run.
-- ============================================================================

grant select on embedding_configurations, document_embedding_runs, document_chunk_embeddings,
  retrieval_evaluation_query_embeddings to authenticated;

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
  create_retrieval_evaluation_dataset(uuid, text, int, text, text, text, text[], text, uuid, uuid),
  add_evaluation_corpus_item(uuid, uuid, uuid),
  create_evaluation_query(uuid, text, text, text, text, text, boolean, text, text, uuid),
  create_relevance_judgment(uuid, uuid, int, text, uuid),
  submit_evaluation_dataset_for_review(uuid, uuid),
  mark_evaluation_dataset_reviewed(uuid, uuid),
  freeze_retrieval_evaluation_dataset(uuid, text, uuid),
  get_approved_embedding_configuration(),
  create_document_embedding_job(uuid, text, uuid),
  cancel_document_embedding_run(uuid, text, uuid),
  create_query_embeddings_for_dataset(uuid, text, uuid),
  create_vector_evaluation_run(uuid, int[], int, text, uuid)
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
-- FIXTURE: reuse the exact accepted extraction/chunking chain established
-- in 012_deterministic_chunking.sql / 013_retrieval_evaluation.sql, this
-- time producing 2 chunks whose synthetic vectors we control directly (no
-- real model in this SQL-layer suite — deterministic hand-built vectors,
-- matching this codebase's own "small synthetic fixture" convention).
-- ----------------------------------------------------------------------------
do $$
declare
  v_session_id uuid;
  v_document_id uuid;
  v_job_id uuid;
  v_token text;
  v_hash text;
  v_org uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_sha text := repeat('m', 63) || '1';
  v_run record;
  v_review record;
  v_chunking_job record;
  v_chunking_run record;
  v_chunking_review record;
  v_page1 record; v_page2 record;
  v_chunks jsonb;
  i int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
  perform test_fixture_set('domain_id', id) from create_clinical_domain(v_org, 'e2-domain', 'S1-E2 Test Domain', null);
  perform test_fixture_set('authority_id', id) from create_guideline_authority(v_org, 'S1-E2 Test Authority', null, null, null, null, true, null);

  declare v_guideline_id uuid; v_version_id uuid;
  begin
    select id into v_guideline_id from create_guideline(v_org, fx('domain_id'), fx('authority_id'), 'E2-1', 'S1-E2 Embedding Test Guideline');
    select id into v_version_id from create_guideline_version(v_guideline_id, 'v1.0');
    perform test_fixture_set('guideline_version_id', v_version_id);
    select upload_session_id, source_document_id into v_session_id, v_document_id
      from create_guideline_upload_session(v_version_id, 'e2-fixture.pdf', 'application/pdf', 1000, null, null);
  end;
  select processing_job_id into v_job_id from complete_guideline_upload(v_session_id, 'application/pdf', 1000, v_sha, null);
  set local role none;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');
  update document_processing_jobs set
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-e2-test',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = v_job_id;
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, v_job_id, 1, 'noor-worker-e2-test', 'started');
  perform start_document_processing_job(v_job_id, 'noor-worker-e2-test', v_token);

  select * into v_run from create_document_extraction_run(
    v_job_id, 'noor-worker-e2-test', v_token, v_sha, 1000, 'pdf-text-v1', '1', 'pypdf', '6.14.2', gen_random_uuid()
  );

  insert into document_extraction_pages (
    organization_id, extraction_run_id, source_document_id, page_number,
    width_points, height_points, rotation_degrees, raw_text, normalized_text,
    character_count, word_count, is_blank, suspected_scanned, extraction_status, page_checksum
  ) values
    (v_org, v_run.out_extraction_run_id, v_document_id, 1,
     595.28, 841.89, 0, 'Diabetes management overview', 'Diabetes management overview',
     29, 3, false, false, 'text_extracted', repeat('1', 63) || 'b'),
    (v_org, v_run.out_extraction_run_id, v_document_id, 2,
     595.28, 841.89, 0, 'Unrelated hospital cafeteria menu', 'Unrelated hospital cafeteria menu',
     33, 4, false, false, 'text_extracted', repeat('2', 63) || 'b');

  perform finalize_document_extraction_run(
    v_run.out_extraction_run_id, v_job_id, 'noor-worker-e2-test', v_token,
    2, 'guideline-processed', 'test/path/e2-extract.json', repeat('f', 64), 100, 'application/json',
    '{}'::jsonb, 2, 0, 0, 62, 7, 0, '[]'::jsonb
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
    status = 'claimed', attempt_count = 1, claimed_by = 'noor-worker-e2-test',
    claimed_at = now(), heartbeat_at = now(), lease_token_hash = v_hash,
    lease_acquired_at = now(), lease_expires_at = now() + interval '90 seconds'
    where id = v_chunking_job.out_job_id;
  insert into document_processing_attempts (organization_id, processing_job_id, attempt_number, worker_id, status)
    values (v_org, v_chunking_job.out_job_id, 1, 'noor-worker-e2-test', 'started');
  perform start_document_processing_job(v_chunking_job.out_job_id, 'noor-worker-e2-test', v_token);

  select * into v_chunking_run from create_document_chunking_run(
    v_chunking_job.out_job_id, 'noor-worker-e2-test', v_token,
    v_run.out_extraction_run_id, v_review.id, v_sha,
    '{"schema_version":"1.0","pages":[]}'::jsonb, repeat('m', 64),
    'controlled-page-aware-chunking-v1', '1', '1', 'noor-simple-tokenizer', '1'
  );

  select id, page_checksum into v_page1 from document_extraction_pages where extraction_run_id = v_run.out_extraction_run_id and page_number = 1;
  select id, page_checksum into v_page2 from document_extraction_pages where extraction_run_id = v_run.out_extraction_run_id and page_number = 2;

  v_chunks := jsonb_build_array(
    jsonb_build_object(
      'chunk_index', 1, 'chunk_text', 'Diabetes management overview', 'chunk_checksum', repeat('1', 64),
      'page_start', 1, 'page_end', 1, 'token_count', 3, 'character_count', 29, 'word_count', 3,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 1, 'representation_type', 'native', 'representation_id', v_page1.id,
        'representation_checksum', v_page1.page_checksum, 'start_offset', 0, 'end_offset', 29,
        'source_fragment_checksum', repeat('a', 64), 'span_order', 1
      ))
    ),
    jsonb_build_object(
      'chunk_index', 2, 'chunk_text', 'Unrelated hospital cafeteria menu', 'chunk_checksum', repeat('2', 64),
      'page_start', 2, 'page_end', 2, 'token_count', 4, 'character_count', 33, 'word_count', 4,
      'boundary_start_reason', 'page_start', 'boundary_end_reason', 'page_end',
      'contains_native_text', true, 'contains_ocr_text', false, 'warning_state', false, 'warnings', '[]'::jsonb,
      'source_spans', jsonb_build_array(jsonb_build_object(
        'page_number', 2, 'representation_type', 'native', 'representation_id', v_page2.id,
        'representation_checksum', v_page2.page_checksum, 'start_offset', 0, 'end_offset', 33,
        'source_fragment_checksum', repeat('b', 64), 'span_order', 1
      ))
    )
  );

  perform finalize_document_chunking_run(
    v_chunking_run.out_chunking_run_id, v_chunking_job.out_job_id, 'noor-worker-e2-test', v_token,
    v_chunks, jsonb_build_object('coverage_percentage', 100, 'duplication_percentage', 0, 'page_count', 2, 'chunk_count', 2),
    '[]'::jsonb, 'guideline-processed', 'test/path/e2-chunks.json', repeat('d', 64), 300, 'application/json'
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
  perform submit_document_chunking_review(v_chunking_review.id, 'accepted', null, null);
  set local role none;

  perform test_fixture_set('document_id', v_document_id);
  for i in 1..2 loop
    perform test_fixture_set('chunk_' || i || '_id', id) from document_chunks where chunking_run_id = v_chunking_run.out_chunking_run_id and chunk_index = i;
  end loop;

  raise notice 'FIXTURE READY: 1 accepted document, 2 embedding-ready chunks';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: get_approved_embedding_configuration returns the seeded config.
-- ---------------------------------------------------------------------------
do $$
declare v_config record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_config from get_approved_embedding_configuration();
  set local role none;
  if v_config.configuration_key <> 'noor-multilingual-e5-base-v1' or v_config.embedding_dimension <> 768 then
    raise exception 'TEST 1 FAILED: unexpected approved configuration %', row_to_json(v_config);
  end if;
  perform test_fixture_set('embedding_configuration_id', v_config.id);
  raise notice 'TEST 1 PASSED: approved embedding configuration resolved correctly';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 2: create_document_embedding_job succeeds for an embedding-ready
-- document; a clinician is denied.
-- ---------------------------------------------------------------------------
do $$
declare v_job record; v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  begin
    perform create_document_embedding_job(fx('document_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 2 FAILED: a clinician was able to create a document embedding job';
  end if;

  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_job from create_document_embedding_job(fx('document_id'));
  set local role none;
  if v_job.out_status <> 'queued' or v_job.out_reused then
    raise exception 'TEST 2 FAILED: expected a fresh queued job, got %', row_to_json(v_job);
  end if;
  perform test_fixture_set('embedding_job_id', v_job.out_job_id);
  raise notice 'TEST 2 PASSED: clinician denied; embedding job created for quality_manager';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 3: Worker claims the job, reads context (2 chunks), creates the
-- embedding run (identity-based, idempotent), and records 2 synthetic
-- 768-dim vectors deterministically constructed so chunk 1 is "close" to
-- a later test query vector and chunk 2 is "far" (cosine distance).
-- ---------------------------------------------------------------------------
do $$
declare
  v_claim record;
  v_context_count int := 0;
  v_manifest jsonb;
  v_manifest_sha256 text;
  v_run record;
  v_vec1 extensions.vector(768);
  v_vec2 extensions.vector(768);
  v_identity1 text;
  v_identity2 text;
  v_row record;
begin
  set local role none;
  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-e2-test-1', array['document_embedding']);
  if v_claim.out_job_id is null or v_claim.out_job_id <> fx('embedding_job_id') then
    raise exception 'TEST 3 FAILED: expected to claim the fixture embedding job, got %', row_to_json(v_claim);
  end if;
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token);
  perform test_text_fixture_set('embedding_job_lease_token', v_claim.out_lease_token);

  select count(*) into v_context_count from get_document_embedding_job_context(v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token);
  if v_context_count <> 2 then
    raise exception 'TEST 3 FAILED: expected 2 chunks in embedding job context, got %', v_context_count;
  end if;

  v_manifest := jsonb_build_array(
    jsonb_build_object('chunk_id', fx('chunk_1_id'), 'chunk_index', 1, 'chunk_checksum', repeat('1', 64), 'input_text_checksum', repeat('x', 64), 'input_token_count', 3),
    jsonb_build_object('chunk_id', fx('chunk_2_id'), 'chunk_index', 2, 'chunk_checksum', repeat('2', 64), 'input_text_checksum', repeat('y', 64), 'input_token_count', 4)
  );
  v_manifest_sha256 := encode(digest(convert_to(v_manifest::text, 'utf8'), 'sha256'), 'hex');

  select * into v_run from create_document_embedding_run(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token,
    (select chunking_run_id from document_chunks where id = fx('chunk_1_id')),
    null, fx('embedding_configuration_id'), v_manifest, v_manifest_sha256, 2
  );
  if v_run.out_status <> 'processing' or v_run.out_reused then
    raise exception 'TEST 3 FAILED: expected a fresh processing embedding run, got %', row_to_json(v_run);
  end if;
  perform test_fixture_set('embedding_run_id', v_run.out_embedding_run_id);

  -- Deterministic synthetic vectors: mostly 0.01, with a distinguishing
  -- coordinate. Chunk 1's "signal" coordinate matches the later test
  -- query's own signal coordinate (small cosine distance); chunk 2's
  -- differs entirely (large cosine distance).
  select array_agg(case when i = 1 then 0.9 else 0.01 end)::extensions.vector(768) into v_vec1 from generate_series(1, 768) as i;
  select array_agg(case when i = 400 then 0.9 else 0.01 end)::extensions.vector(768) into v_vec2 from generate_series(1, 768) as i;

  v_identity1 := encode(digest('identity-chunk-1', 'sha256'), 'hex');
  v_identity2 := encode(digest('identity-chunk-2', 'sha256'), 'hex');

  select * into v_row from record_document_chunk_embedding(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token, v_run.out_embedding_run_id,
    fx('chunk_1_id'), v_identity1, repeat('x', 64), 3, v_vec1, encode(digest('vec1', 'sha256'), 'hex'), 1.0
  );
  if v_row.status <> 'succeeded' then
    raise exception 'TEST 3 FAILED: expected chunk 1 embedding to succeed, got %', row_to_json(v_row);
  end if;

  select * into v_row from record_document_chunk_embedding(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token, v_run.out_embedding_run_id,
    fx('chunk_2_id'), v_identity2, repeat('y', 64), 4, v_vec2, encode(digest('vec2', 'sha256'), 'hex'), 1.0
  );
  if v_row.status <> 'succeeded' then
    raise exception 'TEST 3 FAILED: expected chunk 2 embedding to succeed, got %', row_to_json(v_row);
  end if;

  -- Idempotent replay: re-recording the same identity returns the same row.
  select * into v_row from record_document_chunk_embedding(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token, v_run.out_embedding_run_id,
    fx('chunk_1_id'), v_identity1, repeat('x', 64), 3, v_vec1, encode(digest('vec1', 'sha256'), 'hex'), 1.0
  );
  if v_row.status <> 'succeeded' then
    raise exception 'TEST 3 FAILED: idempotent replay of chunk 1 embedding failed';
  end if;

  select * into v_run from finalize_document_embedding_run(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token, v_run.out_embedding_run_id,
    'guideline-processed', 'test/path/e2-embeddings.json', repeat('e', 64), 200, 'application/json'
  );
  if v_run.out_status <> 'succeeded' or v_run.out_succeeded_count <> 2 then
    raise exception 'TEST 3 FAILED: expected embedding run to succeed with 2 embeddings, got %', row_to_json(v_run);
  end if;

  set local role none;
  raise notice 'TEST 3 PASSED: Worker claimed job, created run, recorded 2 chunk embeddings (idempotent), finalized run';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 4: dimension mismatch is rejected.
-- ---------------------------------------------------------------------------
do $$
declare
  v_bad_vec extensions.vector(3);
  v_failed boolean := false;
begin
  set local role none;
  select array_agg(0.1)::extensions.vector(3) into v_bad_vec from generate_series(1, 3);
  begin
    perform record_document_chunk_embedding(
      fx('embedding_job_id'), 'noor-worker-e2-test-1', fxt('embedding_job_lease_token'), fx('embedding_run_id'),
      fx('chunk_1_id'), 'a-different-identity-for-dimension-test', repeat('z', 64), 3, v_bad_vec, encode(digest('bad', 'sha256'), 'hex'), 1.0
    );
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 4 FAILED: a wrong-dimension vector was accepted';
  end if;
  raise notice 'TEST 4 PASSED: embedding_dimension_mismatch correctly rejected';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 5: chunk embeddings are immutable once succeeded (only invalidation
-- with reason is allowed).
-- ---------------------------------------------------------------------------
do $$
declare v_id uuid; v_failed boolean := false;
begin
  select id into v_id from document_chunk_embeddings where chunk_id = fx('chunk_1_id') and status = 'succeeded';
  begin
    update document_chunk_embeddings set vector_norm = 99.0 where id = v_id;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 5 FAILED: a succeeded chunk embedding was mutated';
  end if;
  raise notice 'TEST 5 PASSED: succeeded chunk embeddings are immutable';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 6: Worker-only trust boundary — authenticated cannot call any
-- embedding Worker-only function directly.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform get_document_embedding_job_context(fx('embedding_job_id'), 'noor-worker-e2-test-1', fxt('embedding_job_lease_token'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 6 FAILED: authenticated was able to call get_document_embedding_job_context';
  end if;
  raise notice 'TEST 6 PASSED: embedding Worker-only functions are unreachable from authenticated';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 7: build a frozen retrieval-evaluation dataset from the 2
-- embedded chunks plus 1 query, ready for vector evaluation.
-- ---------------------------------------------------------------------------
do $$
declare v_dataset record; v_ci1 uuid; v_ci2 uuid; v_query record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  select * into v_dataset from create_retrieval_evaluation_dataset(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'noor-e2-vector-eval-foundation', 1,
    'S1-E2 Vector Evaluation Dataset', 'Synthetic vector evaluation fixture', null,
    array['en'], 'Sprint 1-E2 verification'
  );
  perform test_fixture_set('dataset_id', v_dataset.id);

  select id into v_ci1 from add_evaluation_corpus_item(v_dataset.id, fx('chunk_1_id'));
  select id into v_ci2 from add_evaluation_corpus_item(v_dataset.id, fx('chunk_2_id'));
  perform test_fixture_set('corpus_item_1_id', v_ci1);
  perform test_fixture_set('corpus_item_2_id', v_ci2);

  select * into v_query from create_evaluation_query(v_dataset.id, 'q-diabetes', 'diabetes management', 'en', 'english_exact', 'basic', false);
  perform test_fixture_set('query_id', v_query.id);
  perform create_relevance_judgment(v_query.id, v_ci1, 3, 'exact topical match');

  perform submit_evaluation_dataset_for_review(v_dataset.id);
  set local role none;

  set local role authenticated;
  set local request.jwt.claim.sub = '88888888-8888-8888-8888-888888888888';
  set local request.jwt.claims = '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}';
  perform mark_evaluation_dataset_reviewed(v_dataset.id);
  set local role none;

  raise notice 'TEST 7 PASSED: draft dataset built with 2 corpus items (already embedded) and 1 query, submitted and reviewed';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 8: create_vector_evaluation_run is rejected before the dataset is
-- frozen.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform create_vector_evaluation_run(fx('dataset_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 8 FAILED: create_vector_evaluation_run succeeded before the dataset was frozen';
  end if;
  raise notice 'TEST 8 PASSED: create_vector_evaluation_run rejected before freeze';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 9: create_query_embeddings_for_dataset is rejected before freeze;
-- freeze the dataset, then it succeeds.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false; v_job record; v_dataset record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform create_query_embeddings_for_dataset(fx('dataset_id'));
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 9 FAILED: create_query_embeddings_for_dataset succeeded before freeze';
  end if;

  select * into v_dataset from freeze_retrieval_evaluation_dataset(fx('dataset_id'));
  if v_dataset.status <> 'frozen' then
    raise exception 'TEST 9 FAILED: freeze did not succeed: %', row_to_json(v_dataset);
  end if;

  select * into v_job from create_query_embeddings_for_dataset(fx('dataset_id'));
  set local role none;
  if v_job.out_status <> 'queued' or v_job.out_reused then
    raise exception 'TEST 9 FAILED: expected a fresh queued query-embedding job, got %', row_to_json(v_job);
  end if;
  perform test_fixture_set('query_embedding_job_id', v_job.out_job_id);
  raise notice 'TEST 9 PASSED: query-embedding generation requires a frozen dataset; job created after freeze';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 10: create_vector_evaluation_run still rejected — chunk embeddings
-- exist, but query embeddings do not yet.
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  begin
    perform create_vector_evaluation_run(fx('dataset_id'));
  exception when others then
    v_failed := true;
  end;
  set local role none;
  if not v_failed then
    raise exception 'TEST 10 FAILED: create_vector_evaluation_run succeeded with no query embeddings yet';
  end if;
  raise notice 'TEST 10 PASSED: create_vector_evaluation_run rejected without query-embedding coverage';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 11: Worker claims the query-embedding job, records the query's
-- vector (deterministically close to chunk 1's vector), job completes.
-- ---------------------------------------------------------------------------
do $$
declare
  v_claim record;
  v_context_count int := 0;
  v_query_vec extensions.vector(768);
  v_row record;
begin
  set local role none;
  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-e2-test-1', array['query_embedding_generation']);
  if v_claim.out_job_id is null or v_claim.out_job_id <> fx('query_embedding_job_id') then
    raise exception 'TEST 11 FAILED: expected to claim the fixture query-embedding job, got %', row_to_json(v_claim);
  end if;
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token);

  select count(*) into v_context_count from get_query_embedding_job_context(v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token);
  if v_context_count <> 1 then
    raise exception 'TEST 11 FAILED: expected 1 active query in context, got %', v_context_count;
  end if;

  -- Same "signal" coordinate as chunk 1's vector (position 1) -> small
  -- cosine distance to chunk 1, large cosine distance to chunk 2.
  select array_agg(case when i = 1 then 0.9 else 0.01 end)::extensions.vector(768) into v_query_vec from generate_series(1, 768) as i;

  select * into v_row from record_query_embedding(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token, fx('dataset_id'), fx('query_id'),
    fx('embedding_configuration_id'), encode(digest('identity-query-1', 'sha256'), 'hex'), repeat('q', 64), 2,
    v_query_vec, encode(digest('queryvec', 'sha256'), 'hex'), 1.0
  );
  if v_row.status <> 'succeeded' then
    raise exception 'TEST 11 FAILED: expected query embedding to succeed, got %', row_to_json(v_row);
  end if;

  perform complete_document_processing_job(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token,
    jsonb_build_object('query_count', 1), v_claim.out_job_id::text || ':finalize', gen_random_uuid()
  );
  set local role none;
  raise notice 'TEST 11 PASSED: Worker recorded the query embedding and completed the job';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 12: create_vector_evaluation_run now succeeds (full coverage).
-- ---------------------------------------------------------------------------
do $$
declare v_run record;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select * into v_run from create_vector_evaluation_run(fx('dataset_id'));
  set local role none;
  if v_run.out_status <> 'queued' or v_run.out_reused then
    raise exception 'TEST 12 FAILED: expected a fresh queued vector evaluation run, got %', row_to_json(v_run);
  end if;
  perform test_fixture_set('vector_run_id', v_run.out_run_id);
  perform test_fixture_set('vector_job_id', v_run.out_job_id);
  raise notice 'TEST 12 PASSED: create_vector_evaluation_run succeeds once chunk + query embedding coverage is complete';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 13: get_vector_search_candidates ranks chunk 1 first (small cosine
-- distance to the query) in BOTH exact and indexed search modes.
-- ---------------------------------------------------------------------------
do $$
declare
  v_claim record;
  v_top_exact uuid;
  v_top_indexed uuid;
begin
  set local role none;
  select out_job_id, out_lease_token into v_claim
    from claim_next_document_processing_job('noor-worker-e2-test-1', array['retrieval_evaluation']);
  if v_claim.out_job_id is null or v_claim.out_job_id <> fx('vector_job_id') then
    raise exception 'TEST 13 FAILED: expected to claim the fixture vector evaluation job, got %', row_to_json(v_claim);
  end if;
  perform start_document_processing_job(v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token);
  perform test_text_fixture_set('vector_job_lease_token', v_claim.out_lease_token);

  select out_corpus_item_id into v_top_exact from get_vector_search_candidates(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token, fx('dataset_id'), fx('query_id'), 'exact'
  ) order by out_distance asc limit 1;
  if v_top_exact <> fx('corpus_item_1_id') then
    raise exception 'TEST 13 FAILED: exact vector search did not rank chunk 1 first (got %)', v_top_exact;
  end if;

  select out_corpus_item_id into v_top_indexed from get_vector_search_candidates(
    v_claim.out_job_id, 'noor-worker-e2-test-1', v_claim.out_lease_token, fx('dataset_id'), fx('query_id'), 'indexed'
  ) order by out_distance asc limit 1;
  if v_top_indexed <> fx('corpus_item_1_id') then
    raise exception 'TEST 13 FAILED: indexed vector search did not rank chunk 1 first (got %)', v_top_indexed;
  end if;

  set local role none;
  raise notice 'TEST 13 PASSED: both exact and indexed vector search correctly rank the semantically closer chunk first';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 14: finalize_retrieval_evaluation_run (reused, unmodified, from
-- migration 0015) accepts the new vector-specific metric_name and
-- failure_category values added by migration 0017.
-- ---------------------------------------------------------------------------
do $$
declare
  v_results jsonb;
  v_metrics jsonb;
  v_failures jsonb;
  v_result record;
begin
  v_results := jsonb_build_array(
    jsonb_build_object('query_id', fx('query_id'), 'corpus_item_id', fx('corpus_item_1_id'), 'rank', 1, 'final_score', 0.95, 'relevance_grade', 3, 'is_hit', true, 'reciprocal_rank_contribution', 1.0, 'dcg_contribution', 7.0, 'result_checksum', repeat('r', 64))
  );
  v_metrics := jsonb_build_array(
    jsonb_build_object('scope_type', 'overall', 'scope_value', null, 'metric_name', 'mrr', 'metric_value', 1.0, 'sample_size', 1),
    jsonb_build_object('scope_type', 'exact_vs_indexed', 'scope_value', null, 'metric_name', 'exact_vs_indexed_recall_at_1', 'metric_value', 1.0, 'sample_size', 1),
    jsonb_build_object('scope_type', 'overall', 'scope_value', null, 'metric_name', 'embedding_coverage', 'metric_value', 1.0, 'sample_size', 2)
  );
  v_failures := '[]'::jsonb;

  set local role none;
  select * into v_result from finalize_retrieval_evaluation_run(
    fx('vector_run_id'), fx('vector_job_id'), 'noor-worker-e2-test-1', fxt('vector_job_lease_token'),
    v_results, v_metrics, v_failures,
    'guideline-processed', 'test/path/e2-vector-run.json', repeat('v', 64), 500, 'application/json'
  );
  set local role none;

  if v_result.out_status <> 'succeeded' or v_result.out_result_count <> 1 then
    raise exception 'TEST 14 FAILED: expected succeeded/1 result, got %', row_to_json(v_result);
  end if;
  raise notice 'TEST 14 PASSED: finalize_retrieval_evaluation_run (reused, unmodified) accepts new vector metric/scope values';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 15: RLS — a clinician cannot read embedding tables; quality_manager can.
-- ---------------------------------------------------------------------------
do $$
declare v_count int;
begin
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  select count(*) into v_count from document_chunk_embeddings where chunk_id = fx('chunk_1_id');
  if v_count <> 0 then
    raise exception 'TEST 15 FAILED: a clinician could read document_chunk_embeddings';
  end if;
  select count(*) into v_count from embedding_configurations where id = fx('embedding_configuration_id');
  if v_count <> 0 then
    raise exception 'TEST 15 FAILED: a clinician could read embedding_configurations';
  end if;

  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';
  select count(*) into v_count from document_chunk_embeddings where chunk_id = fx('chunk_1_id');
  set local role none;
  if v_count <> 1 then
    raise exception 'TEST 15 FAILED: quality_manager could not read document_chunk_embeddings (got %)', v_count;
  end if;
  raise notice 'TEST 15 PASSED: RLS enforces document_embeddings.read / embedding_configurations.read correctly';
end
$$;

do $$
begin
  raise notice 'ALL EMBEDDING AND VECTOR EVALUATION TESTS PASSED';
end
$$;

drop function fx(text);
drop function fxt(text);
drop function test_fixture_set(text, uuid);
drop function test_text_fixture_set(text, text);
