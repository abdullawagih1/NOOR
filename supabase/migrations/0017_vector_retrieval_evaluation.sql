-- ============================================================================
-- Noor V1 — Migration 0017: Vector Retrieval Evaluation
-- Council: Retrieval Evaluation Agent + PostgreSQL/pgvector Agent + Worker Agent + Database Agent
-- ============================================================================
-- Sprint 1-E2. Extends the existing S1-E1 evaluation framework (migration
-- 0015's retrieval_evaluation_runs/_results/_metrics/_failures) with a
-- second Retriever — noor-vector-baseline-v1 — rather than forking a
-- parallel metric/judgment/results system (mission's own explicit
-- instruction). get_retrieval_evaluation_job_context,
-- finalize_retrieval_evaluation_run, fail_retrieval_evaluation_run, and
-- cancel_evaluation_run (all migration 0015) are fully retriever-agnostic
-- already and are reused here completely unmodified. See ADR 0016.
-- ============================================================================

-- ============================================================================
-- 1. Extend retrieval_evaluation_runs with vector-specific identity
--    components (both nullable — null for a lexical run).
-- ============================================================================

alter table retrieval_evaluation_runs
  add column if not exists embedding_configuration_id uuid references embedding_configurations(id);

alter table retrieval_evaluation_runs
  add column if not exists vector_index_configuration_version text;

-- ============================================================================
-- 2. Extend retrieval_evaluation_metrics: a new 'exact_vs_indexed' scope
--    (mission §36) and the new vector-specific metric names (mission §43-44).
--    Re-declaring both CHECK constraints (drop + re-add) is the same
--    extend-in-place pattern used throughout this codebase for widening
--    an existing enumerated CHECK — never a second parallel metrics table.
-- ============================================================================

alter table retrieval_evaluation_metrics
  drop constraint if exists retrieval_evaluation_metrics_scope_type_check;

alter table retrieval_evaluation_metrics
  add constraint retrieval_evaluation_metrics_scope_type_check
  check (scope_type in ('overall', 'language', 'category', 'difficulty', 'exact_vs_indexed'));

alter table retrieval_evaluation_metrics
  drop constraint if exists retrieval_evaluation_metrics_metric_name_check;

alter table retrieval_evaluation_metrics
  add constraint retrieval_evaluation_metrics_metric_name_check
  check (metric_name in (
    -- Retrieval-quality metrics (S1-E1, unchanged — reused, never forked).
    'precision_at_1', 'precision_at_3', 'precision_at_5', 'precision_at_10',
    'recall_at_1', 'recall_at_3', 'recall_at_5', 'recall_at_10',
    'hit_rate_at_1', 'hit_rate_at_3', 'hit_rate_at_5', 'hit_rate_at_10',
    'mrr', 'ndcg_at_1', 'ndcg_at_3', 'ndcg_at_5', 'ndcg_at_10',
    -- Exact-vs-indexed correctness (mission §36) — never merged with a
    -- retrieval-quality score (mission §43: "do not merge retrieval-
    -- quality metrics and system-performance metrics into one score").
    'exact_vs_indexed_recall_at_1', 'exact_vs_indexed_recall_at_3',
    'exact_vs_indexed_recall_at_5', 'exact_vs_indexed_recall_at_10',
    'exact_vs_indexed_rank_agreement',
    -- Coverage / system-performance metrics (mission §43-44).
    'embedding_coverage', 'query_embedding_coverage',
    'invalid_vector_count', 'reused_vector_count',
    'provider_latency_ms', 'exact_search_latency_ms', 'indexed_search_latency_ms'
  ));

-- ============================================================================
-- 3. Extend retrieval_evaluation_failures with the vector-specific failure
--    taxonomy (mission §42) — 'other' already exists from migration 0015.
-- ============================================================================

alter table retrieval_evaluation_failures
  drop constraint if exists retrieval_evaluation_failures_failure_category_check;

alter table retrieval_evaluation_failures
  add constraint retrieval_evaluation_failures_failure_category_check
  check (failure_category in (
    'missed_relevant_item', 'relevant_below_k', 'non_relevant_ranked_high',
    'exact_phrase_failure', 'arabic_normalization_failure', 'mixed_language_failure',
    'numeric_match_failure', 'abbreviation_failure', 'tokenization_failure',
    'tie_break_failure', 'query_too_broad', 'query_too_narrow',
    'insufficient_lexical_overlap', 'negative_control_false_positive',
    'judgment_gap', 'corpus_gap',
    'semantic_false_positive', 'semantic_false_negative', 'lexical_exact_match_lost',
    'arabic_embedding_failure', 'mixed_language_embedding_failure', 'numeric_semantics_failure',
    'abbreviation_embedding_failure', 'short_query_failure', 'long_chunk_dilution',
    'similar_chunk_confusion', 'query_passage_mode_mismatch', 'model_input_limit',
    'vector_dimension_error', 'vector_norm_anomaly', 'exact_index_disagreement',
    'index_recall_failure', 'dataset_embedding_gap', 'stale_embedding', 'configuration_mismatch',
    'other'
  ));

-- ============================================================================
-- 4. query_embedding_generation job type — dataset-scoped (reuses the
--    dataset_id column migration 0015 added), its own controlled path
--    rather than folded into the vector-evaluation job (ADR 0016: query
--    embeddings are generated once per dataset/configuration and reused
--    across every evaluation run at that configuration, not regenerated
--    per run).
-- ============================================================================

alter table document_processing_jobs
  drop constraint if exists document_processing_jobs_job_type_check;

alter table document_processing_jobs
  add constraint document_processing_jobs_job_type_check
  check (job_type in ('document_parsing', 'document_ocr', 'document_chunking', 'retrieval_evaluation', 'document_embedding', 'query_embedding_generation'));

alter table document_processing_jobs
  drop constraint if exists document_processing_jobs_subject_check;

alter table document_processing_jobs
  add constraint document_processing_jobs_subject_check
  check (
    (job_type in ('document_parsing', 'document_ocr', 'document_chunking', 'document_embedding')
      and source_document_id is not null and dataset_id is null)
    or
    (job_type in ('retrieval_evaluation', 'query_embedding_generation')
      and dataset_id is not null and source_document_id is null)
  );

create unique index if not exists document_processing_jobs_one_active_query_embedding_per_dataset
  on document_processing_jobs (dataset_id, job_type)
  where job_type = 'query_embedding_generation' and status in ('queued', 'claimed', 'processing', 'retry_scheduled');

-- ============================================================================
-- 5. Client-facing: create_query_embeddings_for_dataset — generates (or
--    reuses) embeddings for every active query in a frozen dataset, under
--    the approved embedding configuration.
-- ============================================================================

create or replace function create_query_embeddings_for_dataset(
  p_dataset_id uuid,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_job_id uuid, out_status text, out_reused boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_config embedding_configurations%rowtype;
  v_existing_job document_processing_jobs%rowtype;
  v_job document_processing_jobs%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.run');
  if v_dataset.status <> 'frozen' then
    raise exception 'query_embedding_dataset_not_frozen: query embeddings require a frozen dataset (current status: %)', v_dataset.status
      using errcode = 'P0001';
  end if;

  select * into v_config from embedding_configurations where approval_status = 'approved' limit 1;
  if not found then
    raise exception 'embedding_configuration_not_approved' using errcode = 'P0001';
  end if;

  select * into v_existing_job from document_processing_jobs
    where organization_id = v_dataset.organization_id and dataset_id = p_dataset_id
      and job_type = 'query_embedding_generation' and status in ('queued', 'claimed', 'processing', 'retry_scheduled');
  if found then
    return query select v_existing_job.id, v_existing_job.status, true;
    return;
  end if;

  insert into document_processing_jobs (
    organization_id, dataset_id, job_type, pipeline_version, status, requested_by, correlation_id
  ) values (
    v_dataset.organization_id, p_dataset_id, 'query_embedding_generation',
    v_config.model_identifier || '-' || v_config.model_revision, 'queued', v_actor, p_correlation_id
  )
  returning * into v_job;

  perform record_audit_event(v_dataset.organization_id, 'query_embedding_generation.requested', 'document_processing_job', v_job.id, p_correlation_id,
    jsonb_build_object('dataset_id', p_dataset_id, 'embedding_configuration_id', v_config.id));

  return query select v_job.id, v_job.status, false;
end;
$$;

revoke all on function create_query_embeddings_for_dataset(uuid, text, uuid) from public;

-- ============================================================================
-- 6. Worker-only: query-embedding job context + atomic per-query recording.
-- ============================================================================

create or replace function get_query_embedding_job_context(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text
) returns table (
  out_dataset_id uuid,
  out_dataset_sha256 text,
  out_embedding_configuration_id uuid,
  out_model_identifier text,
  out_model_revision text,
  out_embedding_dimension int,
  out_query_input_template_version text,
  out_maximum_input_tokens int,
  out_query_id uuid,
  out_query_key text,
  out_query_text text,
  out_query_checksum text
)
-- search_path includes `extensions` for digest() (pgcrypto) below — see
-- the note by record_query_embedding on why query_sha256 is computed
-- fresh here rather than trusted from a stored column.
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_job document_processing_jobs%rowtype;
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_config embedding_configurations%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);
  if v_job.job_type <> 'query_embedding_generation' then
    raise exception 'job % is not a query_embedding_generation job (actual type: %)', p_processing_job_id, v_job.job_type;
  end if;

  select * into v_dataset from retrieval_evaluation_datasets where id = v_job.dataset_id;
  if v_dataset.status <> 'frozen' then
    raise exception 'query_embedding_dataset_not_frozen: dataset % is no longer frozen (status: %)', v_dataset.id, v_dataset.status
      using errcode = 'P0001';
  end if;

  select * into v_config from embedding_configurations where approval_status = 'approved' limit 1;
  if not found then
    raise exception 'embedding_configuration_not_approved' using errcode = 'P0001';
  end if;

  return query
  select
    v_dataset.id, v_dataset.dataset_sha256, v_config.id, v_config.model_identifier, v_config.model_revision,
    v_config.embedding_dimension, v_config.query_input_template_version, v_config.maximum_input_tokens,
    q.id, q.query_key, q.query_text, encode(digest(convert_to(q.query_text, 'utf8'), 'sha256'), 'hex')
  from retrieval_evaluation_queries q
  where q.dataset_id = v_dataset.id and q.active
  order by q.display_order;
end;
$$;

revoke all on function get_query_embedding_job_context(uuid, text, text) from public;

create or replace function record_query_embedding(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_dataset_id uuid,
  p_query_id uuid,
  p_embedding_configuration_id uuid,
  p_embedding_identity_sha256 text,
  p_input_text_checksum text,
  p_input_token_count int,
  p_vector_value extensions.vector,
  p_vector_checksum text,
  p_vector_norm double precision,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_query_embeddings
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_job document_processing_jobs%rowtype;
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_query retrieval_evaluation_queries%rowtype;
  v_config embedding_configurations%rowtype;
  v_existing retrieval_evaluation_query_embeddings%rowtype;
  v_row retrieval_evaluation_query_embeddings%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);
  if v_job.dataset_id <> p_dataset_id then
    raise exception 'job % does not match dataset %', p_processing_job_id, p_dataset_id;
  end if;

  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id;
  select * into v_query from retrieval_evaluation_queries where organization_id = v_job.organization_id and id = p_query_id;
  if not found or v_query.dataset_id <> p_dataset_id then
    raise exception 'query % does not belong to dataset %', p_query_id, p_dataset_id;
  end if;
  select * into v_config from embedding_configurations where id = p_embedding_configuration_id;

  select * into v_existing from retrieval_evaluation_query_embeddings
    where organization_id = v_job.organization_id and embedding_identity_sha256 = p_embedding_identity_sha256 and status = 'succeeded';
  if found then
    if v_existing.vector_checksum <> p_vector_checksum then
      raise exception 'embedding_vector_checksum_failed: conflicting vector checksum for identity %', p_embedding_identity_sha256 using errcode = 'P0001';
    end if;
    return v_existing;
  end if;

  if p_vector_value is null then
    raise exception 'embedding_vector_empty' using errcode = 'P0001';
  end if;
  if vector_dims(p_vector_value) <> v_config.embedding_dimension then
    raise exception 'embedding_dimension_mismatch: expected %, got %', v_config.embedding_dimension, vector_dims(p_vector_value) using errcode = 'P0001';
  end if;

  -- retrieval_evaluation_queries.query_sha256 (migration 0014) is never
  -- actually populated by freeze_retrieval_evaluation_dataset — a real gap
  -- discovered while building this function (there was no consumer of that
  -- column until now). Rather than editing the already-shipped migration
  -- 0014, the checksum is computed fresh from canonical query_text here,
  -- matching get_query_embedding_job_context's own approach above.
  insert into retrieval_evaluation_query_embeddings (
    organization_id, evaluation_dataset_id, query_id, embedding_configuration_id,
    dataset_sha256, query_checksum, input_text_checksum, input_token_count, embedding_identity_sha256,
    embedding_dimension, vector_value, vector_checksum, vector_norm, status, completed_at
  ) values (
    v_job.organization_id, p_dataset_id, p_query_id, p_embedding_configuration_id,
    v_dataset.dataset_sha256, encode(digest(convert_to(v_query.query_text, 'utf8'), 'sha256'), 'hex'),
    p_input_text_checksum, p_input_token_count, p_embedding_identity_sha256,
    v_config.embedding_dimension, p_vector_value, p_vector_checksum, p_vector_norm, 'succeeded', now()
  )
  on conflict (evaluation_dataset_id, query_id, embedding_configuration_id) do update set
    status = 'succeeded', completed_at = now(), vector_value = excluded.vector_value,
    vector_checksum = excluded.vector_checksum, vector_norm = excluded.vector_norm
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function record_query_embedding(uuid, text, text, uuid, uuid, uuid, text, text, int, extensions.vector, text, double precision, uuid) from public;

-- ============================================================================
-- 7. Client-facing: create_vector_evaluation_run — mirrors
--    create_retrieval_evaluation_run's identity/reuse shape (migration
--    0015) exactly, adding embedding-coverage validation and a
--    vector-specific identity tuple. Reuses the SAME
--    retrieval_evaluation_runs/_results/_metrics/_failures tables and the
--    SAME finalize_retrieval_evaluation_run/fail_retrieval_evaluation_run/
--    cancel_evaluation_run/get_retrieval_evaluation_job_context functions
--    — none of those are touched by this migration because they are
--    already fully retriever-agnostic.
-- ============================================================================

create or replace function create_vector_evaluation_run(
  p_dataset_id uuid,
  p_top_k_values int[] default '{1,3,5,10}'::int[],
  p_relevance_threshold int default 2,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_run_id uuid, out_job_id uuid, out_status text, out_reused boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_actor uuid := auth.uid();
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_config embedding_configurations%rowtype;
  v_identity jsonb;
  v_identity_sha256 text;
  v_existing_run retrieval_evaluation_runs%rowtype;
  v_existing_job document_processing_jobs%rowtype;
  v_job document_processing_jobs%rowtype;
  v_run retrieval_evaluation_runs%rowtype;
  v_missing_chunk_count int;
  v_missing_query_count int;
  v_retriever_name text := 'noor-vector-baseline';
  v_retriever_version text := '1';
  v_vector_index_configuration_version text := 'vector_index_configuration_v1';
  v_metric_definition_version text := '1';
  v_evaluation_runner_version text := '1';
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_dataset from retrieval_evaluation_datasets where id = p_dataset_id;
  if not found then
    raise exception 'dataset not found: %', p_dataset_id;
  end if;
  perform assert_permission(v_dataset.organization_id, 'retrieval_evaluation.run');
  if v_dataset.status <> 'frozen' then
    raise exception 'evaluation runs require a frozen dataset (current status: %)', v_dataset.status using errcode = 'P0001';
  end if;

  select * into v_config from embedding_configurations where approval_status = 'approved' limit 1;
  if not found then
    raise exception 'embedding_configuration_not_approved' using errcode = 'P0001';
  end if;

  select count(*) into v_missing_chunk_count
  from retrieval_evaluation_corpus_items c
  where c.dataset_id = p_dataset_id
    and not exists (
      select 1 from document_chunk_embeddings dce
      where dce.chunk_id = c.chunk_id and dce.embedding_configuration_id = v_config.id and dce.status = 'succeeded'
    );
  if v_missing_chunk_count > 0 then
    raise exception 'dataset_embedding_gap: % corpus item(s) have no succeeded chunk embedding at the approved configuration', v_missing_chunk_count
      using errcode = 'P0001';
  end if;

  select count(*) into v_missing_query_count
  from retrieval_evaluation_queries q
  where q.dataset_id = p_dataset_id and q.active
    and not exists (
      select 1 from retrieval_evaluation_query_embeddings qe
      where qe.query_id = q.id and qe.evaluation_dataset_id = p_dataset_id
        and qe.embedding_configuration_id = v_config.id and qe.status = 'succeeded'
    );
  if v_missing_query_count > 0 then
    raise exception 'query_embedding_coverage_incomplete: % active queries have no succeeded query embedding at the approved configuration', v_missing_query_count
      using errcode = 'P0001';
  end if;

  v_identity := jsonb_build_object(
    'organization_id', v_dataset.organization_id,
    'dataset_sha256', v_dataset.dataset_sha256,
    'retriever_name', v_retriever_name,
    'retriever_version', v_retriever_version,
    'embedding_configuration_id', v_config.id,
    'embedding_configuration_key', v_config.configuration_key,
    'vector_index_configuration_version', v_vector_index_configuration_version,
    'metric_definition_version', v_metric_definition_version,
    'top_k_values', to_jsonb(p_top_k_values),
    'evaluation_runner_version', v_evaluation_runner_version
  );
  v_identity_sha256 := encode(digest(convert_to(v_identity::text, 'utf8'), 'sha256'), 'hex');

  select * into v_existing_run from retrieval_evaluation_runs
    where organization_id = v_dataset.organization_id and run_identity_sha256 = v_identity_sha256 and status = 'succeeded';
  if found then
    return query select v_existing_run.id, v_existing_run.processing_job_id, 'succeeded'::text, true;
    return;
  end if;

  select * into v_existing_job from document_processing_jobs
    where organization_id = v_dataset.organization_id and dataset_id = p_dataset_id
      and job_type = 'retrieval_evaluation' and status in ('queued', 'claimed', 'processing');
  if found then
    select * into v_existing_run from retrieval_evaluation_runs where processing_job_id = v_existing_job.id;
    return query select v_existing_run.id, v_existing_job.id, v_existing_job.status, true;
    return;
  end if;

  insert into document_processing_jobs (
    organization_id, dataset_id, job_type, pipeline_version, status, requested_by, correlation_id
  ) values (
    v_dataset.organization_id, p_dataset_id, 'retrieval_evaluation', v_retriever_name || '-v' || v_retriever_version, 'queued', v_actor, p_correlation_id
  )
  returning * into v_job;

  insert into retrieval_evaluation_runs (
    organization_id, dataset_id, processing_job_id,
    retriever_name, retriever_version, retrieval_configuration_version,
    query_normalization_version, metric_definition_version,
    top_k_values, relevance_threshold, evaluation_runner_version,
    embedding_configuration_id, vector_index_configuration_version,
    run_identity_sha256, status, created_by
  ) values (
    v_dataset.organization_id, p_dataset_id, v_job.id,
    v_retriever_name, v_retriever_version, v_config.configuration_key,
    'retrieval_text_normalization_v1', v_metric_definition_version,
    p_top_k_values, p_relevance_threshold, v_evaluation_runner_version,
    v_config.id, v_vector_index_configuration_version,
    v_identity_sha256, 'running', v_actor
  )
  returning * into v_run;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_run.created', 'retrieval_evaluation_run', v_run.id, p_correlation_id,
    jsonb_build_object('dataset_id', p_dataset_id, 'run_identity_sha256', v_identity_sha256, 'retriever_name', v_retriever_name));

  return query select v_run.id, v_job.id, v_job.status, false;
end;
$$;

revoke all on function create_vector_evaluation_run(uuid, int[], int, text, uuid) from public;

-- ============================================================================
-- 8. Worker-only: get_vector_search_candidates — both the exact reference
--    path and the indexed (HNSW) path share one function, toggled by
--    p_search_mode, to avoid duplicating the tenant/dataset-boundary logic
--    (mission §34-35 both require identical dataset/tenant restriction and
--    tie-break — only the scan strategy differs). Exact mode disables
--    index/bitmap scans for this statement only (SET LOCAL, scoped to the
--    current transaction), guaranteeing a true sequential scan with no ANN
--    approximation; indexed mode sets the HNSW ef_search parameter and
--    lets the planner choose the index it already has.
-- ============================================================================

create or replace function get_vector_search_candidates(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_dataset_id uuid,
  p_query_id uuid,
  p_search_mode text default 'indexed'
) returns table (
  out_corpus_item_id uuid,
  out_distance double precision,
  out_similarity double precision,
  out_display_order int,
  out_chunk_checksum text
)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_job document_processing_jobs%rowtype;
  v_query_embedding retrieval_evaluation_query_embeddings%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);
  if v_job.job_type <> 'retrieval_evaluation' or v_job.dataset_id <> p_dataset_id then
    raise exception 'job % does not match dataset %', p_processing_job_id, p_dataset_id;
  end if;
  if p_search_mode not in ('exact', 'indexed') then
    raise exception 'invalid search mode: %', p_search_mode;
  end if;

  select * into v_query_embedding from retrieval_evaluation_query_embeddings
    where organization_id = v_job.organization_id and evaluation_dataset_id = p_dataset_id and query_id = p_query_id and status = 'succeeded'
    order by created_at desc limit 1;
  if not found then
    return;
  end if;

  if p_search_mode = 'exact' then
    set local enable_indexscan = off;
    set local enable_bitmapscan = off;
  else
    set local hnsw.ef_search = 100;
  end if;

  return query
  select
    c.id,
    (dce.vector_value <=> v_query_embedding.vector_value)::double precision,
    (1 - (dce.vector_value <=> v_query_embedding.vector_value))::double precision,
    c.display_order,
    c.chunk_checksum
  from retrieval_evaluation_corpus_items c
  join document_chunk_embeddings dce
    on dce.chunk_id = c.chunk_id and dce.status = 'succeeded' and dce.embedding_configuration_id = v_query_embedding.embedding_configuration_id
  where c.dataset_id = p_dataset_id and c.organization_id = v_job.organization_id
  order by (dce.vector_value <=> v_query_embedding.vector_value) asc, c.display_order asc, c.chunk_checksum asc;
end;
$$;

revoke all on function get_vector_search_candidates(uuid, text, text, uuid, uuid, text) from public;

-- ============================================================================
-- 9. Guarded double-revoke from authenticated/anon, and guarded grants for
--    the new client-facing functions.
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke execute on function
      get_query_embedding_job_context(uuid, text, text),
      record_query_embedding(uuid, text, text, uuid, uuid, uuid, text, text, int, extensions.vector, text, double precision, uuid),
      get_vector_search_candidates(uuid, text, text, uuid, uuid, text)
      from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke execute on function
      get_query_embedding_job_context(uuid, text, text),
      record_query_embedding(uuid, text, text, uuid, uuid, uuid, text, text, int, extensions.vector, text, double precision, uuid),
      get_vector_search_candidates(uuid, text, text, uuid, uuid, text)
      from anon;
  end if;
end
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
      create_query_embeddings_for_dataset(uuid, text, uuid),
      create_vector_evaluation_run(uuid, int[], int, text, uuid)
      to authenticated;
  end if;
end
$$;
