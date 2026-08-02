-- ============================================================================
-- Noor V1 — Migration 0015: Lexical Baseline and Evaluation Runs
-- Council: Information Retrieval Agent + Worker Agent + Database Agent + Security Agent
-- ============================================================================
-- Sprint 1-E1. Durable evaluation-run execution against a frozen dataset
-- (migration 0014): candidate recall via built-in PostgreSQL full-text
-- search, immutable ranked results, versioned metrics, and failure
-- analysis. See ADR 0015.
--
-- No embeddings, no vector columns, no pgvector, no external AI calls
-- anywhere in this migration. Final scoring/tie-breaking/metrics are
-- deliberately NOT computed here — they are pure Python
-- (apps/worker/app/retrieval/*), fully testable without a live database,
-- since this Worker has never had a direct Postgres driver (PostgREST RPC
-- only, confirmed by inspection — see ADR 0015).
-- ============================================================================

-- ============================================================================
-- 1. Extend document_processing_jobs for job_type = 'retrieval_evaluation'
--    (dataset-scoped, not document-scoped — the first job type in this
--    codebase that isn't tied to exactly one source document).
-- ============================================================================

alter table document_processing_jobs
  alter column source_document_id drop not null;

alter table document_processing_jobs
  add column if not exists dataset_id uuid;

alter table document_processing_jobs
  drop constraint if exists document_processing_jobs_job_type_check;

alter table document_processing_jobs
  add constraint document_processing_jobs_job_type_check
  check (job_type in ('document_parsing', 'document_ocr', 'document_chunking', 'retrieval_evaluation'));

-- Exactly one of source_document_id / dataset_id is set, depending on
-- job_type — a document-scoped job never has a dataset_id and vice versa.
alter table document_processing_jobs
  drop constraint if exists document_processing_jobs_subject_check;

alter table document_processing_jobs
  add constraint document_processing_jobs_subject_check
  check (
    (job_type in ('document_parsing', 'document_ocr', 'document_chunking')
      and source_document_id is not null and dataset_id is null)
    or
    (job_type = 'retrieval_evaluation'
      and dataset_id is not null and source_document_id is null)
  );

alter table document_processing_jobs
  add constraint document_processing_jobs_dataset_id_fkey
  foreign key (organization_id, dataset_id) references retrieval_evaluation_datasets(organization_id, id);

-- Dataset-scoped, like extraction's own index (not page-scoped like OCR's) —
-- at most one active retrieval_evaluation job per dataset at a time.
create unique index if not exists document_processing_jobs_one_active_eval_per_dataset
  on document_processing_jobs (dataset_id, job_type)
  where job_type = 'retrieval_evaluation' and status in ('queued', 'claimed', 'processing');

-- 0007's original claim_next_document_processing_job() required every
-- claimable job to have a source_document_id resolving to a 'registered'
-- guideline_source_documents row — true for every job type until now.
-- A retrieval_evaluation job is dataset-scoped (source_document_id is
-- null), so that EXISTS check would silently make every such job
-- unclaimable forever. Re-declared here (same signature, same 0007
-- behavior for every other job_type) with one added eligibility branch —
-- the identical pattern already used by migration 0013 to extend a
-- 0011-era function without touching the original migration file.
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
    and (
      (j.source_document_id is not null and exists (
        select 1 from guideline_source_documents gsd
        where gsd.id = j.source_document_id and gsd.status = 'registered'
      ))
      or
      (j.dataset_id is not null and exists (
        select 1 from retrieval_evaluation_datasets d
        where d.id = j.dataset_id and d.status = 'frozen'
      ))
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

  if v_row.source_document_id is not null then
    insert into document_intake_events (organization_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
      values (v_row.organization_id, v_job_id, 'document_processing_job.claimed', null, p_correlation_id,
        jsonb_build_object('worker_instance_id', p_worker_instance_id, 'attempt_number', v_row.attempt_count));
  else
    perform record_audit_event(v_row.organization_id, 'document_processing_job.claimed', 'document_processing_job', v_job_id, p_correlation_id,
      jsonb_build_object('worker_instance_id', p_worker_instance_id, 'attempt_number', v_row.attempt_count, 'dataset_id', v_row.dataset_id));
  end if;

  return query select
    v_row.id, v_row.organization_id, v_row.source_document_id, v_row.job_type, v_row.pipeline_version,
    p_correlation_id, v_row.attempt_count, v_lease_token, v_expires;
end;
$$;

-- CREATE OR REPLACE preserves this function's existing ACL from migration
-- 0007 (object identity is unchanged) — its guarded revoke-from-
-- authenticated/anon there already covers this redefinition; nothing
-- further to grant or revoke here.

-- ============================================================================
-- 2. retrieval_evaluation_runs — one durable execution attempt at one
--    deterministic identity (mission §24). Unlike chunking's identity,
--    every component here is already known server-side at request time
--    (no external file parsing dependency), so the run row is created
--    directly by the client-facing function below, not by the Worker.
-- ============================================================================

create table if not exists retrieval_evaluation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  dataset_id uuid not null,
  processing_job_id uuid not null,
  processing_attempt_id uuid,

  retriever_name text not null default 'noor-lexical-baseline',
  retriever_version text not null default '1',
  retrieval_configuration_version text not null default '1',
  query_normalization_version text not null default 'retrieval_text_normalization_v1',
  metric_definition_version text not null default '1',
  top_k_values int[] not null default '{1,3,5,10}'::int[],
  relevance_threshold int not null default 2,
  evaluation_runner_version text not null default '1',
  run_identity_sha256 text not null,

  status text not null default 'running'
    check (status in ('running', 'succeeded', 'failed', 'invalidated', 'cancelled', 'reused')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,
  invalidated_at timestamptz,
  invalidation_reason text,

  query_count int,
  result_count int,

  artifact_bucket text,
  artifact_path text,
  artifact_sha256 text,
  artifact_size_bytes bigint,
  artifact_media_type text,

  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),

  unique (organization_id, id)
);

alter table retrieval_evaluation_runs
  add constraint retrieval_evaluation_runs_dataset_id_fkey
  foreign key (organization_id, dataset_id) references retrieval_evaluation_datasets(organization_id, id);

alter table retrieval_evaluation_runs
  add constraint retrieval_evaluation_runs_processing_job_id_fkey
  foreign key (organization_id, processing_job_id) references document_processing_jobs(organization_id, id);

alter table retrieval_evaluation_runs
  add constraint retrieval_evaluation_runs_processing_attempt_id_fkey
  foreign key (organization_id, processing_attempt_id) references document_processing_attempts(organization_id, id);

-- At most one succeeded run per full identity tuple — reused rather than
-- recomputed (mission §24).
create unique index if not exists retrieval_evaluation_runs_one_succeeded_per_identity
  on retrieval_evaluation_runs (organization_id, run_identity_sha256)
  where status = 'succeeded';

create index if not exists idx_retrieval_runs_dataset on retrieval_evaluation_runs (organization_id, dataset_id, created_at desc);

create or replace function prevent_terminal_evaluation_run_mutation()
returns trigger language plpgsql as $$
begin
  if old.status in ('succeeded', 'failed', 'cancelled', 'invalidated') then
    if new.status = 'invalidated' and old.status in ('succeeded', 'cancelled') then
      if new.invalidated_at is null or new.invalidation_reason is null then
        raise exception 'invalidating a run requires invalidated_at and invalidation_reason';
      end if;
      if new.id <> old.id or new.organization_id <> old.organization_id
        or new.result_count is distinct from old.result_count
        or new.artifact_sha256 is distinct from old.artifact_sha256
        or new.run_identity_sha256 is distinct from old.run_identity_sha256
      then
        raise exception 'a terminal run may only transition to invalidated, with no other field changed';
      end if;
      new.status := 'invalidated';
      return new;
    end if;
    raise exception 'evaluation run % is already terminal (status: %) and cannot be modified', old.id, old.status;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_terminal_evaluation_run_mutation on retrieval_evaluation_runs;
create trigger trg_prevent_terminal_evaluation_run_mutation
  before update on retrieval_evaluation_runs
  for each row execute function prevent_terminal_evaluation_run_mutation();

alter table retrieval_evaluation_runs enable row level security;

-- ============================================================================
-- 3. retrieval_evaluation_results — immutable per-query ranked results
-- ============================================================================

create table if not exists retrieval_evaluation_results (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  evaluation_run_id uuid not null,
  query_id uuid not null,
  corpus_item_id uuid not null,

  rank int not null check (rank >= 1),
  final_score numeric not null,
  score_components jsonb not null default '{}'::jsonb,
  matched_terms jsonb not null default '[]'::jsonb,
  relevance_grade int,
  reciprocal_rank_contribution numeric,
  dcg_contribution numeric,
  is_hit boolean not null default false,
  result_checksum text not null,

  created_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (evaluation_run_id, query_id, rank),
  unique (evaluation_run_id, query_id, corpus_item_id)
);

alter table retrieval_evaluation_results
  add constraint retrieval_evaluation_results_run_id_fkey
  foreign key (organization_id, evaluation_run_id) references retrieval_evaluation_runs(organization_id, id);

create index if not exists idx_retrieval_results_run_query on retrieval_evaluation_results (organization_id, evaluation_run_id, query_id, rank);

create or replace function prevent_evaluation_result_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'evaluation result % is immutable once created', old.id;
end;
$$;

drop trigger if exists trg_prevent_evaluation_result_mutation on retrieval_evaluation_results;
create trigger trg_prevent_evaluation_result_mutation
  before update on retrieval_evaluation_results
  for each row execute function prevent_evaluation_result_mutation();

drop trigger if exists trg_prevent_evaluation_result_delete on retrieval_evaluation_results;
create trigger trg_prevent_evaluation_result_delete
  before delete on retrieval_evaluation_results
  for each row execute function prevent_evaluation_result_mutation();

alter table retrieval_evaluation_results enable row level security;

-- ============================================================================
-- 4. retrieval_evaluation_metrics — immutable metric summaries, scoped by
--    overall / language / category / difficulty
-- ============================================================================

create table if not exists retrieval_evaluation_metrics (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  evaluation_run_id uuid not null,

  scope_type text not null check (scope_type in ('overall', 'language', 'category', 'difficulty')),
  scope_value text,
  metric_name text not null check (metric_name in (
    'precision_at_1', 'precision_at_3', 'precision_at_5', 'precision_at_10',
    'recall_at_1', 'recall_at_3', 'recall_at_5', 'recall_at_10',
    'hit_rate_at_1', 'hit_rate_at_3', 'hit_rate_at_5', 'hit_rate_at_10',
    'mrr', 'ndcg_at_1', 'ndcg_at_3', 'ndcg_at_5', 'ndcg_at_10'
  )),
  metric_value numeric not null,
  sample_size int not null,

  created_at timestamptz not null default now(),

  unique (organization_id, id)
);

alter table retrieval_evaluation_metrics
  add constraint retrieval_evaluation_metrics_run_id_fkey
  foreign key (organization_id, evaluation_run_id) references retrieval_evaluation_runs(organization_id, id);

create unique index if not exists idx_retrieval_metrics_unique_scope
  on retrieval_evaluation_metrics (evaluation_run_id, scope_type, coalesce(scope_value, ''), metric_name);

create or replace function prevent_evaluation_metric_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'evaluation metric % is immutable once created', old.id;
end;
$$;

drop trigger if exists trg_prevent_evaluation_metric_mutation on retrieval_evaluation_metrics;
create trigger trg_prevent_evaluation_metric_mutation
  before update on retrieval_evaluation_metrics
  for each row execute function prevent_evaluation_metric_mutation();

drop trigger if exists trg_prevent_evaluation_metric_delete on retrieval_evaluation_metrics;
create trigger trg_prevent_evaluation_metric_delete
  before delete on retrieval_evaluation_metrics
  for each row execute function prevent_evaluation_metric_mutation();

alter table retrieval_evaluation_metrics enable row level security;

-- ============================================================================
-- 5. retrieval_evaluation_failures — deterministic + human failure analysis
-- ============================================================================

create table if not exists retrieval_evaluation_failures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  evaluation_run_id uuid not null,
  query_id uuid not null,

  failure_category text not null check (failure_category in (
    'missed_relevant_item', 'relevant_below_k', 'non_relevant_ranked_high',
    'exact_phrase_failure', 'arabic_normalization_failure', 'mixed_language_failure',
    'numeric_match_failure', 'abbreviation_failure', 'tokenization_failure',
    'tie_break_failure', 'query_too_broad', 'query_too_narrow',
    'insufficient_lexical_overlap', 'negative_control_false_positive',
    'judgment_gap', 'corpus_gap', 'other'
  )),
  source text not null default 'system' check (source in ('system', 'human')),
  reviewer_note text,
  recommended_experiment text,
  status text not null default 'open' check (status in ('open', 'acknowledged', 'resolved')),

  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id)
);

alter table retrieval_evaluation_failures
  add constraint retrieval_evaluation_failures_run_id_fkey
  foreign key (organization_id, evaluation_run_id) references retrieval_evaluation_runs(organization_id, id);

create index if not exists idx_retrieval_failures_run on retrieval_evaluation_failures (organization_id, evaluation_run_id, query_id);

-- Core content (category/source) is immutable once created; only status/
-- reviewer_note/recommended_experiment may change — mirrors
-- prevent_chunk_finding_content_mutation (migration 0013), one layer over.
create or replace function prevent_failure_content_mutation()
returns trigger language plpgsql as $$
begin
  if new.failure_category <> old.failure_category or new.source <> old.source or new.query_id <> old.query_id then
    raise exception 'a failure annotation''s core content is immutable once created — only status/reviewer_note/recommended_experiment may change';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_prevent_failure_content_mutation on retrieval_evaluation_failures;
create trigger trg_prevent_failure_content_mutation
  before update on retrieval_evaluation_failures
  for each row execute function prevent_failure_content_mutation();

alter table retrieval_evaluation_failures enable row level security;

-- ============================================================================
-- 6. RLS — SELECT-only; every write goes through a security definer function
-- ============================================================================

drop policy if exists retrieval_evaluation_runs_select on retrieval_evaluation_runs;
create policy retrieval_evaluation_runs_select on retrieval_evaluation_runs
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read_results'));

drop policy if exists retrieval_evaluation_results_select on retrieval_evaluation_results;
create policy retrieval_evaluation_results_select on retrieval_evaluation_results
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read_results'));

drop policy if exists retrieval_evaluation_metrics_select on retrieval_evaluation_metrics;
create policy retrieval_evaluation_metrics_select on retrieval_evaluation_metrics
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read_results'));

drop policy if exists retrieval_evaluation_failures_select on retrieval_evaluation_failures;
create policy retrieval_evaluation_failures_select on retrieval_evaluation_failures
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read_results'));

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on retrieval_evaluation_runs, retrieval_evaluation_results,
      retrieval_evaluation_metrics, retrieval_evaluation_failures
      to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 7. Extend migration 0012's guideline-processed Storage policy to also
--    accept retrieval_evaluation.read_artifacts — the evaluation artifact
--    lives in the same private "processed artifact" bucket as extraction/
--    OCR/chunking artifacts (ADR 0015 — no new bucket).
-- ============================================================================

do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    drop policy if exists storage_guideline_processed_select on storage.objects;

    execute $policy$
      create policy storage_guideline_processed_select on storage.objects
        for select using (
          bucket_id = 'guideline-processed'
          and (storage.foldername(name))[1]::uuid in (select current_active_organization_ids())
          and (
            has_permission_in_organization((storage.foldername(name))[1]::uuid, 'guideline_extractions.read_artifacts')
            or has_permission_in_organization((storage.foldername(name))[1]::uuid, 'guideline_ocr.read_artifacts')
            or has_permission_in_organization((storage.foldername(name))[1]::uuid, 'guideline_chunking.read_artifacts')
            or has_permission_in_organization((storage.foldername(name))[1]::uuid, 'retrieval_evaluation.read_artifacts')
          )
        )
    $policy$;
  end if;
end
$$;

-- ============================================================================
-- 8. create_retrieval_evaluation_run — client-facing. Every identity
--    component is already known server-side, so this function computes
--    the identity, checks for reuse, and creates the run row directly —
--    unlike chunking, there is no external-file dependency requiring the
--    Worker to compute anything before the row can exist (mission §24).
-- ============================================================================

create or replace function create_retrieval_evaluation_run(
  p_dataset_id uuid,
  p_top_k_values int[] default '{1,3,5,10}'::int[],
  p_relevance_threshold int default 2,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (
  out_run_id uuid,
  out_job_id uuid,
  out_status text,
  out_reused boolean
)
-- search_path includes `extensions` — this function calls digest()
-- directly to compute the run identity hash; on hosted Supabase pgcrypto
-- lives in the `extensions` schema, not `public` (see assert_lease_owner's
-- own comment in migration 0007 for the same fact).
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_actor uuid := auth.uid();
  v_dataset retrieval_evaluation_datasets%rowtype;
  v_identity jsonb;
  v_identity_sha256 text;
  v_existing_run retrieval_evaluation_runs%rowtype;
  v_existing_job document_processing_jobs%rowtype;
  v_job document_processing_jobs%rowtype;
  v_run retrieval_evaluation_runs%rowtype;
  v_retriever_name text := 'noor-lexical-baseline';
  v_retriever_version text := '1';
  v_retrieval_configuration_version text := '1';
  v_query_normalization_version text := 'retrieval_text_normalization_v1';
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
    raise exception 'evaluation runs require a frozen dataset (current status: %)', v_dataset.status
      using errcode = 'P0001';
  end if;

  v_identity := jsonb_build_object(
    'organization_id', v_dataset.organization_id,
    'dataset_sha256', v_dataset.dataset_sha256,
    'retriever_name', v_retriever_name,
    'retriever_version', v_retriever_version,
    'retrieval_configuration_version', v_retrieval_configuration_version,
    'query_normalization_version', v_query_normalization_version,
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
    v_dataset.organization_id, p_dataset_id, 'retrieval_evaluation', v_retriever_name || '-v' || v_retriever_version, 'queued',
    v_actor, p_correlation_id
  )
  returning * into v_job;

  insert into retrieval_evaluation_runs (
    organization_id, dataset_id, processing_job_id,
    retriever_name, retriever_version, retrieval_configuration_version,
    query_normalization_version, metric_definition_version,
    top_k_values, relevance_threshold, evaluation_runner_version,
    run_identity_sha256, status, created_by
  ) values (
    v_dataset.organization_id, p_dataset_id, v_job.id,
    v_retriever_name, v_retriever_version, v_retrieval_configuration_version,
    v_query_normalization_version, v_metric_definition_version,
    p_top_k_values, p_relevance_threshold, v_evaluation_runner_version,
    v_identity_sha256, 'running', v_actor
  )
  returning * into v_run;

  perform record_audit_event(v_dataset.organization_id, 'retrieval_evaluation_run.created', 'retrieval_evaluation_run', v_run.id, p_correlation_id,
    jsonb_build_object('dataset_id', p_dataset_id, 'run_identity_sha256', v_identity_sha256));

  return query select v_run.id, v_job.id, v_job.status, false;
end;
$$;

revoke all on function create_retrieval_evaluation_run(uuid, int[], int, text, uuid) from public;

create or replace function cancel_evaluation_run(
  p_run_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_runs
language plpgsql security definer set search_path = public as $$
declare
  v_run retrieval_evaluation_runs%rowtype;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancelling a run requires a reason';
  end if;
  select * into v_run from retrieval_evaluation_runs where id = p_run_id for update;
  if not found then
    raise exception 'evaluation run not found: %', p_run_id;
  end if;
  perform assert_permission(v_run.organization_id, 'retrieval_evaluation.cancel_run');
  if v_run.status <> 'running' then
    raise exception 'only a running evaluation run can be cancelled (current status: %)', v_run.status;
  end if;

  perform cancel_processing_job(v_run.processing_job_id, p_reason, p_correlation_id);

  update retrieval_evaluation_runs set status = 'cancelled' where id = p_run_id returning * into v_run;

  perform record_audit_event(v_run.organization_id, 'retrieval_evaluation_run.cancelled', 'retrieval_evaluation_run', v_run.id, p_correlation_id,
    jsonb_build_object('reason', p_reason));

  return v_run;
end;
$$;

revoke all on function cancel_evaluation_run(uuid, text, uuid) from public;

-- ============================================================================
-- 9. Worker-only: context/candidate reads and atomic finalization. Every
--    function below authenticates purely via lease ownership
--    (assert_lease_owner) — never organization permissions — the exact
--    same trust boundary every other Worker-only function in this
--    codebase uses. Explicitly revoked from PUBLIC/anon/authenticated.
-- ============================================================================

create or replace function get_retrieval_evaluation_job_context(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text
) returns table (
  out_dataset_id uuid,
  out_dataset_sha256 text,
  out_run_id uuid,
  out_retriever_name text,
  out_retriever_version text,
  out_retrieval_configuration_version text,
  out_query_normalization_version text,
  out_metric_definition_version text,
  out_top_k_values int[],
  out_relevance_threshold int,
  out_query_id uuid,
  out_query_key text,
  out_normalized_query_text text,
  out_language text,
  out_category text,
  out_difficulty text,
  out_is_negative_control boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run retrieval_evaluation_runs%rowtype;
  v_dataset retrieval_evaluation_datasets%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);
  if v_job.job_type <> 'retrieval_evaluation' then
    raise exception 'job % is not a retrieval_evaluation job (actual type: %)', p_processing_job_id, v_job.job_type;
  end if;

  select * into v_run from retrieval_evaluation_runs where processing_job_id = p_processing_job_id;
  if not found then
    raise exception 'no evaluation run linked to job %', p_processing_job_id;
  end if;

  select * into v_dataset from retrieval_evaluation_datasets where id = v_run.dataset_id;
  if v_dataset.status <> 'frozen' then
    raise exception 'dataset % is no longer frozen (status: %)', v_dataset.id, v_dataset.status using errcode = 'P0001';
  end if;

  return query
  select
    v_dataset.id, v_dataset.dataset_sha256, v_run.id, v_run.retriever_name, v_run.retriever_version, v_run.retrieval_configuration_version,
    v_run.query_normalization_version, v_run.metric_definition_version, v_run.top_k_values, v_run.relevance_threshold,
    q.id, q.query_key, q.normalized_query_text, q.language, q.category, q.difficulty, q.is_negative_control
  from retrieval_evaluation_queries q
  where q.dataset_id = v_dataset.id and q.active
  order by q.display_order;
end;
$$;

revoke all on function get_retrieval_evaluation_job_context(uuid, text, text) from public;

create or replace function get_retrieval_candidates(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_dataset_id uuid,
  p_normalized_query_text text
) returns table (
  out_corpus_item_id uuid,
  out_full_text_rank numeric,
  out_normalized_search_text text,
  out_token_count int,
  out_display_order int,
  out_chunk_checksum text
)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);
  if v_job.job_type <> 'retrieval_evaluation' or v_job.dataset_id <> p_dataset_id then
    raise exception 'job % does not match dataset %', p_processing_job_id, p_dataset_id;
  end if;

  if p_normalized_query_text is null or length(trim(p_normalized_query_text)) = 0 then
    return;
  end if;

  return query
  select
    sd.corpus_item_id,
    ts_rank_cd(sd.search_vector, websearch_to_tsquery('simple', p_normalized_query_text))::numeric,
    sd.normalized_search_text,
    sd.token_count,
    c.display_order,
    c.chunk_checksum
  from retrieval_evaluation_search_documents sd
  join retrieval_evaluation_corpus_items c on c.id = sd.corpus_item_id
  where sd.dataset_id = p_dataset_id
    and sd.search_vector @@ websearch_to_tsquery('simple', p_normalized_query_text);
end;
$$;

revoke all on function get_retrieval_candidates(uuid, text, text, uuid, text) from public;

-- ----------------------------------------------------------------------------
-- finalize_retrieval_evaluation_run — atomic: inserts every ranked result,
-- every metric row, and every system-derived failure from Worker-computed
-- JSON, then marks the run succeeded and completes the job. Mirrors
-- finalize_document_chunking_run's shape one layer over.
-- ----------------------------------------------------------------------------

create or replace function finalize_retrieval_evaluation_run(
  p_run_id uuid,
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_results jsonb,
  p_metrics jsonb,
  p_failures jsonb,
  p_artifact_bucket text,
  p_artifact_path text,
  p_artifact_sha256 text,
  p_artifact_size_bytes bigint,
  p_artifact_media_type text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_run_id uuid, out_status text, out_result_count int)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run retrieval_evaluation_runs%rowtype;
  v_result jsonb;
  v_metric jsonb;
  v_failure jsonb;
  v_result_count int := 0;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from retrieval_evaluation_runs
    where organization_id = v_job.organization_id and id = p_run_id for update;
  if not found then
    raise exception 'evaluation run not found: %', p_run_id;
  end if;
  if v_run.processing_job_id <> p_processing_job_id then
    raise exception 'evaluation run % does not belong to job %', p_run_id, p_processing_job_id;
  end if;

  if v_run.status = 'succeeded' then
    return query select v_run.id, v_run.status, v_run.result_count;
    return;
  end if;
  if v_run.status <> 'running' then
    raise exception 'evaluation run % is not running (status: %)', p_run_id, v_run.status;
  end if;

  for v_result in select * from jsonb_array_elements(p_results)
  loop
    insert into retrieval_evaluation_results (
      organization_id, evaluation_run_id, query_id, corpus_item_id,
      rank, final_score, score_components, matched_terms, relevance_grade,
      reciprocal_rank_contribution, dcg_contribution, is_hit, result_checksum
    ) values (
      v_job.organization_id, v_run.id, (v_result ->> 'query_id')::uuid, (v_result ->> 'corpus_item_id')::uuid,
      (v_result ->> 'rank')::int, (v_result ->> 'final_score')::numeric,
      coalesce(v_result -> 'score_components', '{}'::jsonb), coalesce(v_result -> 'matched_terms', '[]'::jsonb),
      (v_result ->> 'relevance_grade')::int,
      (v_result ->> 'reciprocal_rank_contribution')::numeric, (v_result ->> 'dcg_contribution')::numeric,
      coalesce((v_result ->> 'is_hit')::boolean, false), v_result ->> 'result_checksum'
    );
    v_result_count := v_result_count + 1;
  end loop;

  for v_metric in select * from jsonb_array_elements(p_metrics)
  loop
    insert into retrieval_evaluation_metrics (
      organization_id, evaluation_run_id, scope_type, scope_value, metric_name, metric_value, sample_size
    ) values (
      v_job.organization_id, v_run.id, v_metric ->> 'scope_type', v_metric ->> 'scope_value',
      v_metric ->> 'metric_name', (v_metric ->> 'metric_value')::numeric, (v_metric ->> 'sample_size')::int
    );
  end loop;

  for v_failure in select * from jsonb_array_elements(coalesce(p_failures, '[]'::jsonb))
  loop
    insert into retrieval_evaluation_failures (
      organization_id, evaluation_run_id, query_id, failure_category, source
    ) values (
      v_job.organization_id, v_run.id, (v_failure ->> 'query_id')::uuid, v_failure ->> 'failure_category', 'system'
    );
  end loop;

  update retrieval_evaluation_runs set
    status = 'succeeded',
    completed_at = now(),
    query_count = (select count(distinct query_id) from retrieval_evaluation_results where evaluation_run_id = v_run.id),
    result_count = v_result_count,
    artifact_bucket = p_artifact_bucket,
    artifact_path = p_artifact_path,
    artifact_sha256 = p_artifact_sha256,
    artifact_size_bytes = p_artifact_size_bytes,
    artifact_media_type = p_artifact_media_type
  where id = v_run.id;

  perform complete_document_processing_job(
    p_processing_job_id, p_worker_instance_id, p_lease_token,
    jsonb_build_object('evaluation_run_id', v_run.id, 'result_count', v_result_count),
    p_processing_job_id::text || ':finalize', p_correlation_id
  );

  perform record_audit_event(v_job.organization_id, 'retrieval_evaluation_run.succeeded', 'retrieval_evaluation_run', v_run.id, p_correlation_id,
    jsonb_build_object('result_count', v_result_count));

  return query select v_run.id, 'succeeded'::text, v_result_count;
end;
$$;

revoke all on function finalize_retrieval_evaluation_run(uuid, uuid, text, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid) from public;

create or replace function fail_retrieval_evaluation_run(
  p_run_id uuid,
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_error_code text,
  p_error_class text,
  p_error_message_safe text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_run_id uuid, out_status text)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run retrieval_evaluation_runs%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from retrieval_evaluation_runs
    where organization_id = v_job.organization_id and id = p_run_id for update;
  if not found then
    raise exception 'evaluation run not found: %', p_run_id;
  end if;
  if v_run.status = 'running' then
    update retrieval_evaluation_runs set status = 'failed', failed_at = now() where id = v_run.id;
  end if;

  perform fail_document_processing_job(
    p_processing_job_id, p_worker_instance_id, p_lease_token,
    p_error_code, p_error_class, p_error_message_safe, true,
    p_processing_job_id::text || ':fail', p_correlation_id
  );

  perform record_audit_event(v_job.organization_id, 'retrieval_evaluation_run.failed', 'retrieval_evaluation_run', p_run_id, p_correlation_id,
    jsonb_build_object('error_code', p_error_code));

  return query select p_run_id, 'failed'::text;
end;
$$;

revoke all on function fail_retrieval_evaluation_run(uuid, uuid, text, text, text, text, text, uuid) from public;

-- ============================================================================
-- 10. Failure annotation functions (client-facing, human review)
-- ============================================================================

create or replace function create_failure_annotation(
  p_evaluation_run_id uuid,
  p_query_id uuid,
  p_failure_category text,
  p_reviewer_note text default null,
  p_recommended_experiment text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_failures
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_run retrieval_evaluation_runs%rowtype;
  v_row retrieval_evaluation_failures%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  select * into v_run from retrieval_evaluation_runs where id = p_evaluation_run_id;
  if not found then
    raise exception 'evaluation run not found: %', p_evaluation_run_id;
  end if;
  perform assert_permission(v_run.organization_id, 'retrieval_evaluation.annotate_failures');

  insert into retrieval_evaluation_failures (
    organization_id, evaluation_run_id, query_id, failure_category, source, reviewer_note, recommended_experiment, created_by
  ) values (
    v_run.organization_id, p_evaluation_run_id, p_query_id, p_failure_category, 'human', p_reviewer_note, p_recommended_experiment, v_actor
  )
  returning * into v_row;

  perform record_audit_event(v_run.organization_id, 'retrieval_evaluation_failure.annotated', 'retrieval_evaluation_run', v_run.id, p_correlation_id,
    jsonb_build_object('query_id', p_query_id, 'failure_category', p_failure_category));

  return v_row;
end;
$$;

revoke all on function create_failure_annotation(uuid, uuid, text, text, text, uuid) from public;

create or replace function update_failure_annotation(
  p_failure_id uuid,
  p_status text default null,
  p_reviewer_note text default null,
  p_recommended_experiment text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns retrieval_evaluation_failures
language plpgsql security definer set search_path = public as $$
declare
  v_failure retrieval_evaluation_failures%rowtype;
begin
  select * into v_failure from retrieval_evaluation_failures where id = p_failure_id;
  if not found then
    raise exception 'failure annotation not found: %', p_failure_id;
  end if;
  perform assert_permission(v_failure.organization_id, 'retrieval_evaluation.annotate_failures');
  if p_status is not null and p_status not in ('open', 'acknowledged', 'resolved') then
    raise exception 'invalid status: %', p_status;
  end if;

  update retrieval_evaluation_failures set
    status = coalesce(p_status, status),
    reviewer_note = coalesce(p_reviewer_note, reviewer_note),
    recommended_experiment = coalesce(p_recommended_experiment, recommended_experiment)
    where id = p_failure_id
    returning * into v_failure;

  perform record_audit_event(v_failure.organization_id, 'retrieval_evaluation_failure.resolved', 'retrieval_evaluation_run', v_failure.evaluation_run_id, p_correlation_id,
    jsonb_build_object('failure_id', p_failure_id, 'status', v_failure.status));

  return v_failure;
end;
$$;

revoke all on function update_failure_annotation(uuid, text, text, text, uuid) from public;

-- ============================================================================
-- 11. GRANTS
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
      create_retrieval_evaluation_run(uuid, int[], int, text, uuid),
      cancel_evaluation_run(uuid, text, uuid),
      create_failure_annotation(uuid, uuid, text, text, text, uuid),
      update_failure_annotation(uuid, text, text, text, uuid)
      to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function get_retrieval_evaluation_job_context(uuid, text, text) from anon;
    revoke all on function get_retrieval_candidates(uuid, text, text, uuid, text) from anon;
    revoke all on function finalize_retrieval_evaluation_run(uuid, uuid, text, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid) from anon;
    revoke all on function fail_retrieval_evaluation_run(uuid, uuid, text, text, text, text, text, uuid) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function get_retrieval_evaluation_job_context(uuid, text, text) from authenticated;
    revoke all on function get_retrieval_candidates(uuid, text, text, uuid, text) from authenticated;
    revoke all on function finalize_retrieval_evaluation_run(uuid, uuid, text, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid) from authenticated;
    revoke all on function fail_retrieval_evaluation_run(uuid, uuid, text, text, text, text, text, uuid) from authenticated;
  end if;
end
$$;

-- ============================================================================
-- End of migration 0015
-- ============================================================================
