-- ============================================================================
-- Noor V1 — Migration 0016: Embedding and pgvector Foundation
-- Council: Embedding Architecture Agent + PostgreSQL/pgvector Agent + Worker Agent + Database Agent + Security Agent
-- ============================================================================
-- Sprint 1-E2. Turns accepted, embedding-ready chunks (Sprint 1-D3,
-- get_document_embedding_readiness()) into immutable, checksum-verified
-- vectors under one approved embedding configuration
-- (intfloat/multilingual-e5-base, self-hosted). See ADR 0016.
--
-- No hybrid retrieval, no reranking, no LLM calls, no production search
-- exposure anywhere in this migration. Vector retrieval evaluation
-- (exact/indexed search, vector evaluation runs) is migration 0017.
-- ============================================================================

-- ============================================================================
-- 1. pgvector extension — hosted Supabase pre-creates an `extensions`
--    schema for exactly this purpose; a fresh local Postgres does not. A
--    plain `create extension if not exists vector` would land in
--    `public` locally and in `extensions` on hosted (or wherever a prior
--    hosted enablement placed it) — a real, confirmed divergence (this
--    exact migration failed on a fresh local pgvector/pgvector:pg16
--    container with `schema "extensions" does not exist` before this
--    fix). Explicitly creating the schema and installing into it makes
--    both environments identical, rather than guessing via search_path.
--    `set search_path` for the remainder of this migration session so
--    every subsequent `vector(768)` column/type reference below resolves
--    correctly regardless of which schema a fresh session's default
--    search_path would otherwise have used.
-- ============================================================================

create schema if not exists extensions;
create extension if not exists vector with schema extensions;
set search_path = public, extensions;

-- ============================================================================
-- 2. embedding_configurations — server-managed only; no client-facing
--    create/update function exists (mission §10: "normal users cannot
--    create or mutate configurations"). Exactly one approved configuration
--    for this sprint, seeded below, enforced by a partial unique index.
-- ============================================================================

create table if not exists embedding_configurations (
  id uuid primary key default gen_random_uuid(),
  configuration_key text not null unique,

  provider_name text not null,
  provider_type text not null check (provider_type in ('self_hosted', 'external_api')),
  provider_version text not null,
  model_identifier text not null,
  model_revision text not null,
  model_artifact_sha256 text,

  embedding_dimension int not null check (embedding_dimension > 0),
  maximum_input_tokens int not null check (maximum_input_tokens > 0),
  tokenizer_name text not null,
  tokenizer_version text not null,
  passage_input_template_version text not null,
  query_input_template_version text not null,
  output_normalization text not null check (output_normalization in ('l2_normalized', 'none')),
  distance_metric text not null check (distance_metric in ('cosine', 'l2', 'inner_product')),
  configuration_version text not null,

  data_region text,
  data_retention_summary text,
  external_processing boolean not null default false,

  approval_status text not null default 'draft' check (approval_status in ('draft', 'approved', 'retired', 'blocked')),
  approved_by uuid references profiles(id),
  approved_at timestamptz,
  retired_at timestamptz,

  created_at timestamptz not null default now()
);

-- At most one configuration may be 'approved' at a time (mission §10:
-- "Only one configuration is active for S1-E2") — a unique index on a
-- constant expression, filtered to approved rows, is the standard
-- Postgres idiom for "at most one row matching a predicate."
create unique index if not exists embedding_configurations_one_approved_idx
  on embedding_configurations ((true)) where approval_status = 'approved';

alter table embedding_configurations enable row level security;

-- The one approved configuration this sprint (ADR 0016): self-hosted
-- intfloat/multilingual-e5-base, MIT-licensed, revision pinned against
-- the live Hugging Face Hub API (not assumed from the README), 768
-- dimensions, L2-normalized output compared by cosine distance. No data
-- ever leaves Noor's own infrastructure — external_processing = false.
insert into embedding_configurations (
  configuration_key, provider_name, provider_type, provider_version,
  model_identifier, model_revision, embedding_dimension, maximum_input_tokens,
  tokenizer_name, tokenizer_version, passage_input_template_version, query_input_template_version,
  output_normalization, distance_metric, configuration_version,
  data_region, data_retention_summary, external_processing,
  approval_status, approved_at
) values (
  'noor-multilingual-e5-base-v1', 'sentence-transformers', 'self_hosted', '5.6.1',
  'intfloat/multilingual-e5-base', 'd128750597153bb5987e10b1c3493a34e5a4502a', 768, 512,
  'multilingual-e5-base-tokenizer', '1', '1', '1',
  'l2_normalized', 'cosine', '1',
  'worker-local-only', 'No data leaves Noor infrastructure — self-hosted model, zero external API calls, nothing retained by any third party.', false,
  'approved', now()
)
on conflict (configuration_key) do nothing;

-- ============================================================================
-- 3. Extend document_processing_jobs for job_type = 'document_embedding'
--    (document-scoped, like document_chunking — one accepted chunking run
--    belongs to exactly one document; the specific chunking_run_id and
--    embedding_configuration_id are resolved via context functions, not
--    stored on the job row itself, matching document_chunking's own
--    convention).
-- ============================================================================

alter table document_processing_jobs
  drop constraint if exists document_processing_jobs_job_type_check;

alter table document_processing_jobs
  add constraint document_processing_jobs_job_type_check
  check (job_type in ('document_parsing', 'document_ocr', 'document_chunking', 'retrieval_evaluation', 'document_embedding'));

-- 'document_embedding' is document-scoped like document_parsing/document_ocr/
-- document_chunking (source_document_id set, dataset_id null) — migration
-- 0015's own subject_check only listed the first three plus
-- 'retrieval_evaluation' (dataset-scoped); re-declared here to add
-- 'document_embedding' to the document-scoped branch, the same
-- extend-a-prior-migration's-CHECK-via-re-declaration pattern already used
-- for claim_next_document_processing_job (migration 0015 over 0007).
alter table document_processing_jobs
  drop constraint if exists document_processing_jobs_subject_check;

alter table document_processing_jobs
  add constraint document_processing_jobs_subject_check
  check (
    (job_type in ('document_parsing', 'document_ocr', 'document_chunking', 'document_embedding')
      and source_document_id is not null and dataset_id is null)
    or
    (job_type = 'retrieval_evaluation'
      and dataset_id is not null and source_document_id is null)
  );

create unique index if not exists document_processing_jobs_one_active_embedding_per_document
  on document_processing_jobs (source_document_id, job_type)
  where job_type = 'document_embedding' and status in ('queued', 'claimed', 'processing', 'retry_scheduled');

-- ============================================================================
-- 4. document_embedding_runs — one execution attempt at one deterministic
--    identity: (organization, source_document, chunking_run, embedding
--    configuration, chunk_manifest_sha256). A partial unique index
--    guarantees at most one succeeded/succeeded_with_reuse row per identity.
-- ============================================================================

create table if not exists document_embedding_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  source_document_id uuid not null,
  guideline_version_id uuid not null,
  chunking_run_id uuid not null,
  chunking_review_id uuid,
  embedding_configuration_id uuid not null references embedding_configurations(id),

  chunk_manifest jsonb not null,
  chunk_manifest_sha256 text not null,
  run_identity_sha256 text not null,

  total_chunk_count int not null default 0,
  pending_count int not null default 0,
  processing_count int not null default 0,
  succeeded_count int not null default 0,
  failed_count int not null default 0,
  reused_count int not null default 0,
  invalidated_count int not null default 0,

  status text not null default 'created'
    check (status in ('created', 'queued', 'processing', 'succeeded', 'succeeded_with_reuse', 'failed', 'cancelled', 'invalidated', 'reused')),
  processing_job_id uuid,
  processing_attempt_id uuid,

  started_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,
  invalidated_at timestamptz,
  invalidation_reason text,

  artifact_bucket text,
  artifact_path text,
  artifact_sha256 text,
  artifact_size_bytes bigint,
  artifact_media_type text,

  created_at timestamptz not null default now(),

  unique (organization_id, id)
);

create unique index if not exists document_embedding_runs_one_succeeded_per_identity
  on document_embedding_runs (organization_id, run_identity_sha256)
  where status in ('succeeded', 'succeeded_with_reuse');

create index if not exists document_embedding_runs_by_document
  on document_embedding_runs (organization_id, source_document_id, created_at desc);

alter table document_embedding_runs
  add constraint document_embedding_runs_processing_job_id_fkey
  foreign key (organization_id, processing_job_id) references document_processing_jobs(organization_id, id);

create or replace function prevent_terminal_embedding_run_mutation()
returns trigger language plpgsql as $$
begin
  if old.status in ('succeeded', 'succeeded_with_reuse', 'failed', 'cancelled', 'invalidated', 'reused') then
    if new.status = 'invalidated' and old.status in ('succeeded', 'succeeded_with_reuse', 'reused') then
      if new.invalidated_at is null or new.invalidation_reason is null then
        raise exception 'invalidating an embedding run requires invalidated_at and invalidation_reason';
      end if;
      if new.id <> old.id or new.organization_id <> old.organization_id
        or new.succeeded_count is distinct from old.succeeded_count
        or new.artifact_sha256 is distinct from old.artifact_sha256
        or new.chunk_manifest_sha256 is distinct from old.chunk_manifest_sha256
      then
        raise exception 'a terminal embedding run may only transition to invalidated, with no other field changed';
      end if;
      new.status := 'invalidated';
      return new;
    end if;
    -- Progress-counter-only updates on an otherwise-unchanged terminal row
    -- are allowed as a no-op replay (idempotent finalize retry) only when
    -- nothing besides updated_at-like bookkeeping actually changes.
    if new.status = old.status and new.artifact_sha256 is not distinct from old.artifact_sha256 then
      return new;
    end if;
    raise exception 'embedding run % is already terminal (status: %) and cannot be modified', old.id, old.status;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_terminal_embedding_run_mutation on document_embedding_runs;
create trigger trg_prevent_terminal_embedding_run_mutation
  before update on document_embedding_runs
  for each row execute function prevent_terminal_embedding_run_mutation();

alter table document_embedding_runs enable row level security;

-- ============================================================================
-- 5. document_chunk_embeddings — one immutable vector per (chunk,
--    embedding configuration) identity. vector_value is a FIXED-DIMENSION
--    column (ADR 0016: strongly enforces the single approved configuration
--    at the schema level rather than a generic column with runtime checks).
-- ============================================================================

create table if not exists document_chunk_embeddings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  chunk_id uuid not null,
  chunking_run_id uuid not null,
  source_document_id uuid not null,
  guideline_version_id uuid not null,
  embedding_configuration_id uuid not null references embedding_configurations(id),
  embedding_run_id uuid not null,

  chunk_checksum text not null,
  input_text_checksum text not null,
  input_token_count int not null check (input_token_count >= 0),
  embedding_identity_sha256 text not null,

  embedding_dimension int not null check (embedding_dimension = 768),
  vector_value extensions.vector(768),
  vector_checksum text,
  vector_norm double precision,
  vector_serialization_version text not null default 'vector_serialization_v1',
  provider_request_id_safe text,
  provider_metadata_safe jsonb not null default '{}'::jsonb,

  status text not null default 'running' check (status in ('running', 'succeeded', 'failed', 'invalidated', 'reused')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,
  invalidated_at timestamptz,
  invalidation_reason text,

  processing_job_id uuid not null,
  processing_attempt_id uuid,
  created_at timestamptz not null default now(),
  created_by_worker text,

  unique (organization_id, id),
  unique (embedding_run_id, chunk_id)
);

alter table document_chunk_embeddings
  add constraint document_chunk_embeddings_chunk_id_fkey
  foreign key (organization_id, chunk_id) references document_chunks(organization_id, id);

alter table document_chunk_embeddings
  add constraint document_chunk_embeddings_embedding_run_id_fkey
  foreign key (organization_id, embedding_run_id) references document_embedding_runs(organization_id, id);

-- One succeeded embedding per identity, ever — a changed chunk checksum,
-- model revision, input template, or dimension always produces a new
-- identity (ADR 0016), never a silent reuse of a semantically different
-- vector.
create unique index if not exists document_chunk_embeddings_one_succeeded_per_identity
  on document_chunk_embeddings (organization_id, embedding_identity_sha256)
  where status = 'succeeded';

create index if not exists document_chunk_embeddings_by_chunk
  on document_chunk_embeddings (organization_id, chunk_id, status);

-- HNSW vector index (ADR 0016) — cosine distance, matching this
-- configuration's pinned distance_metric. Only meaningful once rows
-- exist; created unconditionally here since `create index if not exists`
-- on an empty table is instant and HNSW needs no size-dependent tuning
-- (unlike IVFFlat's list count).
create index if not exists document_chunk_embeddings_vector_hnsw_idx
  on document_chunk_embeddings using hnsw (vector_value extensions.vector_cosine_ops)
  where status = 'succeeded';

create or replace function prevent_document_chunk_embedding_mutation()
returns trigger language plpgsql as $$
begin
  if old.status = 'succeeded' then
    if new.status = 'invalidated' then
      if new.invalidated_at is null or new.invalidation_reason is null then
        raise exception 'invalidating a chunk embedding requires invalidated_at and invalidation_reason';
      end if;
      if new.vector_value is distinct from old.vector_value
        or new.vector_checksum is distinct from old.vector_checksum
        or new.chunk_checksum is distinct from old.chunk_checksum
        or new.embedding_configuration_id is distinct from old.embedding_configuration_id
      then
        raise exception 'a succeeded chunk embedding may only transition to invalidated, with no vector/checksum/configuration change';
      end if;
      new.status := 'invalidated';
      return new;
    end if;
    raise exception 'chunk embedding % is immutable once succeeded', old.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_document_chunk_embedding_mutation on document_chunk_embeddings;
create trigger trg_prevent_document_chunk_embedding_mutation
  before update on document_chunk_embeddings
  for each row execute function prevent_document_chunk_embedding_mutation();

alter table document_chunk_embeddings enable row level security;

-- ============================================================================
-- 6. retrieval_evaluation_query_embeddings — one immutable vector per
--    (frozen dataset query, embedding configuration) identity. Only
--    frozen datasets are eligible (mission §19: "Only frozen datasets").
-- ============================================================================

create table if not exists retrieval_evaluation_query_embeddings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  evaluation_dataset_id uuid not null,
  query_id uuid not null,
  embedding_configuration_id uuid not null references embedding_configurations(id),

  dataset_sha256 text not null,
  query_checksum text not null,
  input_text_checksum text not null,
  input_token_count int not null check (input_token_count >= 0),
  embedding_identity_sha256 text not null,

  embedding_dimension int not null check (embedding_dimension = 768),
  vector_value extensions.vector(768),
  vector_checksum text,
  vector_norm double precision,

  status text not null default 'running' check (status in ('running', 'succeeded', 'failed', 'invalidated')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  invalidated_at timestamptz,

  unique (organization_id, id),
  unique (evaluation_dataset_id, query_id, embedding_configuration_id)
);

alter table retrieval_evaluation_query_embeddings
  add constraint retrieval_evaluation_query_embeddings_dataset_id_fkey
  foreign key (organization_id, evaluation_dataset_id) references retrieval_evaluation_datasets(organization_id, id);

alter table retrieval_evaluation_query_embeddings
  add constraint retrieval_evaluation_query_embeddings_query_id_fkey
  foreign key (organization_id, query_id) references retrieval_evaluation_queries(organization_id, id);

create unique index if not exists retrieval_evaluation_query_embeddings_one_succeeded_per_identity
  on retrieval_evaluation_query_embeddings (organization_id, embedding_identity_sha256)
  where status = 'succeeded';

create index if not exists retrieval_evaluation_query_embeddings_vector_hnsw_idx
  on retrieval_evaluation_query_embeddings using hnsw (vector_value extensions.vector_cosine_ops)
  where status = 'succeeded';

create or replace function prevent_query_embedding_mutation()
returns trigger language plpgsql as $$
begin
  if old.status = 'succeeded' then
    if new.status = 'invalidated' then
      if new.invalidated_at is null then
        raise exception 'invalidating a query embedding requires invalidated_at';
      end if;
      if new.vector_value is distinct from old.vector_value or new.vector_checksum is distinct from old.vector_checksum then
        raise exception 'a succeeded query embedding may only transition to invalidated, with no vector/checksum change';
      end if;
      new.status := 'invalidated';
      return new;
    end if;
    raise exception 'query embedding % is immutable once succeeded', old.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_query_embedding_mutation on retrieval_evaluation_query_embeddings;
create trigger trg_prevent_query_embedding_mutation
  before update on retrieval_evaluation_query_embeddings
  for each row execute function prevent_query_embedding_mutation();

alter table retrieval_evaluation_query_embeddings enable row level security;

-- ============================================================================
-- 7. Permissions
-- ============================================================================

insert into permissions (key, description) values
  ('embedding_configurations.read', 'Read the approved embedding configuration'),
  ('document_embeddings.read', 'Read embedding runs and chunk-embedding status'),
  ('document_embeddings.create', 'Create a document embedding job from an accepted chunking run'),
  ('document_embeddings.cancel', 'Cancel a queued or processing embedding run'),
  ('document_embeddings.read_artifacts', 'Read embedding artifact checksum/path metadata')
on conflict (key) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where (r.key, p.key) in (
  ('organization_admin', 'embedding_configurations.read'),
  ('organization_admin', 'document_embeddings.read'),

  ('quality_manager', 'embedding_configurations.read'),
  ('quality_manager', 'document_embeddings.read'),
  ('quality_manager', 'document_embeddings.create'),
  ('quality_manager', 'document_embeddings.cancel'),
  ('quality_manager', 'document_embeddings.read_artifacts'),

  ('safety_officer', 'embedding_configurations.read'),
  ('safety_officer', 'document_embeddings.read'),
  ('auditor', 'embedding_configurations.read'),
  ('auditor', 'document_embeddings.read')
)
on conflict do nothing;

-- Deliberately no clinician mapping — clinicians never see raw vectors,
-- embedding artifacts, or embedding-run internals (mission §45).

-- ============================================================================
-- 8. RLS — SELECT-only; every write goes through a security definer function
-- ============================================================================

-- embedding_configurations is not organization-scoped (it is a single,
-- server-managed, shared record — there is one approved configuration for
-- the whole platform, not one per tenant) — so its SELECT policy checks
-- permission against ANY organization the caller is an active member of,
-- rather than a per-row organization_id column this table does not have.
drop policy if exists embedding_configurations_select on embedding_configurations;
create policy embedding_configurations_select on embedding_configurations
  for select using (
    exists (
      select 1 from current_active_organization_ids() as org_id
      where has_permission_in_organization(org_id, 'embedding_configurations.read')
    )
  );

drop policy if exists document_embedding_runs_select on document_embedding_runs;
create policy document_embedding_runs_select on document_embedding_runs
  for select using (has_permission_in_organization(organization_id, 'document_embeddings.read'));

drop policy if exists document_chunk_embeddings_select on document_chunk_embeddings;
create policy document_chunk_embeddings_select on document_chunk_embeddings
  for select using (has_permission_in_organization(organization_id, 'document_embeddings.read'));

drop policy if exists retrieval_evaluation_query_embeddings_select on retrieval_evaluation_query_embeddings;
create policy retrieval_evaluation_query_embeddings_select on retrieval_evaluation_query_embeddings
  for select using (has_permission_in_organization(organization_id, 'retrieval_evaluation.read_results'));

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on embedding_configurations, document_embedding_runs, document_chunk_embeddings, retrieval_evaluation_query_embeddings to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 9. Extend the guideline-processed Storage policy (0010, extended by
--    0011/0012/0015) to also accept document_embeddings.read_artifacts.
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
            or has_permission_in_organization((storage.foldername(name))[1]::uuid, 'document_embeddings.read_artifacts')
          )
        )
    $policy$;
  end if;
end
$$;

-- ============================================================================
-- 10. Client-facing functions
-- ============================================================================

create or replace function get_approved_embedding_configuration()
returns embedding_configurations
language plpgsql stable security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_org uuid;
  v_config embedding_configurations%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  select org_id into v_org from current_active_organization_ids() as org_id
    where has_permission_in_organization(org_id, 'embedding_configurations.read') limit 1;
  if v_org is null then
    raise exception 'permission denied' using errcode = '42501';
  end if;

  select * into v_config from embedding_configurations where approval_status = 'approved' limit 1;
  if not found then
    raise exception 'no approved embedding configuration exists' using errcode = 'P0001';
  end if;
  return v_config;
end;
$$;

revoke all on function get_approved_embedding_configuration() from public;

create or replace function create_document_embedding_job(
  p_source_document_id uuid,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_job_id uuid, out_status text, out_reused boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_doc guideline_source_documents%rowtype;
  v_run document_chunking_runs%rowtype;
  v_review document_chunking_reviews%rowtype;
  v_config embedding_configurations%rowtype;
  v_existing_job document_processing_jobs%rowtype;
  v_job document_processing_jobs%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_doc from guideline_source_documents where id = p_source_document_id;
  if not found then
    raise exception 'source document not found: %', p_source_document_id;
  end if;
  perform assert_permission(v_doc.organization_id, 'document_embeddings.create');

  select * into v_run from document_chunking_runs
    where organization_id = v_doc.organization_id and source_document_id = p_source_document_id
      and status = 'succeeded'
    order by created_at desc limit 1;
  if not found then
    raise exception 'embedding_input_not_ready: no succeeded chunking run exists for this document' using errcode = 'P0001';
  end if;

  select * into v_review from document_chunking_reviews
    where organization_id = v_run.organization_id and chunking_run_id = v_run.id
    order by review_round desc limit 1;
  if not found or v_review.review_status not in ('accepted', 'accepted_with_warnings') then
    raise exception 'embedding_input_not_ready: this document is not embedding-ready (chunk review status: %)', coalesce(v_review.review_status, 'no_review')
      using errcode = 'P0001';
  end if;

  select * into v_config from embedding_configurations where approval_status = 'approved' limit 1;
  if not found then
    raise exception 'embedding_configuration_not_approved' using errcode = 'P0001';
  end if;

  select * into v_existing_job from document_processing_jobs
    where organization_id = v_doc.organization_id and source_document_id = p_source_document_id
      and job_type = 'document_embedding' and status in ('queued', 'claimed', 'processing', 'retry_scheduled')
    order by created_at desc limit 1;
  if found then
    return query select v_existing_job.id, v_existing_job.status, true;
    return;
  end if;

  insert into document_processing_jobs (
    organization_id, source_document_id, job_type, pipeline_version, status,
    requested_by, correlation_id
  ) values (
    v_doc.organization_id, p_source_document_id, 'document_embedding',
    v_config.model_identifier || '-' || v_config.model_revision, 'queued',
    v_actor, p_correlation_id
  )
  returning * into v_job;

  perform record_audit_event(v_doc.organization_id, 'document_embedding.requested', 'document_processing_job', v_job.id, p_correlation_id,
    jsonb_build_object('source_document_id', p_source_document_id, 'chunking_run_id', v_run.id, 'embedding_configuration_id', v_config.id));

  return query select v_job.id, v_job.status, false;
end;
$$;

revoke all on function create_document_embedding_job(uuid, text, uuid) from public;

create or replace function cancel_document_embedding_run(
  p_embedding_run_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns document_embedding_runs
language plpgsql security definer set search_path = public as $$
declare
  v_run document_embedding_runs%rowtype;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'cancelling an embedding run requires a reason';
  end if;
  select * into v_run from document_embedding_runs where id = p_embedding_run_id for update;
  if not found then
    raise exception 'embedding run not found: %', p_embedding_run_id;
  end if;
  perform assert_permission(v_run.organization_id, 'document_embeddings.cancel');
  if v_run.status not in ('created', 'queued', 'processing') then
    raise exception 'only a created, queued, or processing embedding run can be cancelled (current status: %)', v_run.status;
  end if;

  if v_run.processing_job_id is not null then
    perform cancel_processing_job(v_run.processing_job_id, p_reason, p_correlation_id);
  end if;

  update document_embedding_runs set status = 'cancelled' where id = p_embedding_run_id returning * into v_run;

  perform record_audit_event(v_run.organization_id, 'document_embedding_run.cancelled', 'document_embedding_run', v_run.id, p_correlation_id,
    jsonb_build_object('reason', p_reason));

  return v_run;
end;
$$;

revoke all on function cancel_document_embedding_run(uuid, text, uuid) from public;

-- ============================================================================
-- 11. Worker-only functions. Every one authenticates purely via
--     assert_lease_owner() against a claimed document_processing_jobs
--     lease — never via organization permissions, the same trust boundary
--     every other Worker-only function in this codebase uses. Explicitly
--     revoked from PUBLIC/anon/authenticated.
-- ============================================================================

-- get_document_chunking_job_context (and the review-eligibility helpers it
-- wraps) are permission-gated (assert_permission) — always false for
-- service_role's auth.uid()-less JWT. This is the Worker's own
-- un-gated equivalent, re-deriving embedding-readiness without the
-- permission check, exactly the same class of fix this codebase has
-- already made twice (get_document_chunking_job_context itself, ADR 0014;
-- claim_next_document_processing_job's dataset-scoped branch, ADR 0015).
create or replace function get_document_embedding_job_context(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text
) returns table (
  out_source_document_id uuid,
  out_guideline_version_id uuid,
  out_chunking_run_id uuid,
  out_chunking_review_id uuid,
  out_embedding_configuration_id uuid,
  out_configuration_key text,
  out_model_identifier text,
  out_model_revision text,
  out_embedding_dimension int,
  out_passage_input_template_version text,
  out_maximum_input_tokens int,
  out_chunk_id uuid,
  out_chunk_index int,
  out_chunk_checksum text,
  out_chunk_text text
)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_chunking_runs%rowtype;
  v_review document_chunking_reviews%rowtype;
  v_config embedding_configurations%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);
  if v_job.job_type <> 'document_embedding' then
    raise exception 'job % is not a document_embedding job (actual type: %)', p_processing_job_id, v_job.job_type;
  end if;

  select * into v_run from document_chunking_runs
    where organization_id = v_job.organization_id and source_document_id = v_job.source_document_id
      and status = 'succeeded'
    order by created_at desc limit 1;
  if not found then
    raise exception 'embedding_input_not_ready: no succeeded chunking run exists' using errcode = 'P0001';
  end if;

  select * into v_review from document_chunking_reviews
    where organization_id = v_run.organization_id and chunking_run_id = v_run.id
    order by review_round desc limit 1;
  if not found or v_review.review_status not in ('accepted', 'accepted_with_warnings') then
    raise exception 'embedding_input_not_ready: this document is not embedding-ready (chunk review status: %)', coalesce(v_review.review_status, 'no_review')
      using errcode = 'P0001';
  end if;

  select * into v_config from embedding_configurations where approval_status = 'approved' limit 1;
  if not found then
    raise exception 'embedding_configuration_not_approved' using errcode = 'P0001';
  end if;

  return query
  select
    v_job.source_document_id, v_run.guideline_version_id, v_run.id, v_review.id,
    v_config.id, v_config.configuration_key, v_config.model_identifier, v_config.model_revision,
    v_config.embedding_dimension, v_config.passage_input_template_version, v_config.maximum_input_tokens,
    dc.id, dc.chunk_index, dc.chunk_checksum, dc.chunk_text
  from document_chunks dc
  where dc.chunking_run_id = v_run.id
  order by dc.chunk_index;
end;
$$;

revoke all on function get_document_embedding_job_context(uuid, text, text) from public;

create or replace function create_document_embedding_run(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_chunking_run_id uuid,
  p_chunking_review_id uuid,
  p_embedding_configuration_id uuid,
  p_chunk_manifest jsonb,
  p_chunk_manifest_sha256 text,
  p_total_chunk_count int,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_embedding_run_id uuid, out_status text, out_reused boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_chunking_runs%rowtype;
  v_identity jsonb;
  v_identity_sha256 text;
  v_existing document_embedding_runs%rowtype;
  v_new document_embedding_runs%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_chunking_runs where organization_id = v_job.organization_id and id = p_chunking_run_id;
  if not found then
    raise exception 'chunking run not found: %', p_chunking_run_id;
  end if;

  v_identity := jsonb_build_object(
    'organization_id', v_job.organization_id,
    'source_document_id', v_job.source_document_id,
    'chunking_run_id', p_chunking_run_id,
    'embedding_configuration_id', p_embedding_configuration_id,
    'chunk_manifest_sha256', p_chunk_manifest_sha256
  );
  v_identity_sha256 := encode(digest(convert_to(v_identity::text, 'utf8'), 'sha256'), 'hex');

  select * into v_existing from document_embedding_runs
    where organization_id = v_job.organization_id and run_identity_sha256 = v_identity_sha256
      and status in ('succeeded', 'succeeded_with_reuse');
  if found then
    return query select v_existing.id, v_existing.status, true;
    return;
  end if;

  select * into v_existing from document_embedding_runs
    where processing_job_id = p_processing_job_id and run_identity_sha256 = v_identity_sha256;
  if found then
    return query select v_existing.id, v_existing.status, false;
    return;
  end if;

  insert into document_embedding_runs (
    organization_id, source_document_id, guideline_version_id, chunking_run_id, chunking_review_id,
    embedding_configuration_id, chunk_manifest, chunk_manifest_sha256, run_identity_sha256,
    total_chunk_count, pending_count, status, processing_job_id
  ) values (
    v_job.organization_id, v_job.source_document_id, v_run.guideline_version_id, p_chunking_run_id, p_chunking_review_id,
    p_embedding_configuration_id, p_chunk_manifest, p_chunk_manifest_sha256, v_identity_sha256,
    p_total_chunk_count, p_total_chunk_count, 'processing', p_processing_job_id
  )
  returning * into v_new;

  perform record_audit_event(v_job.organization_id, 'document_embedding_run.created', 'document_embedding_run', v_new.id, p_correlation_id,
    jsonb_build_object('run_identity_sha256', v_identity_sha256, 'total_chunk_count', p_total_chunk_count));

  return query select v_new.id, v_new.status, false;
end;
$$;

revoke all on function create_document_embedding_run(uuid, text, text, uuid, uuid, uuid, jsonb, text, int, uuid) from public;

-- Atomic per-item finalization (mission §29) — called once per chunk,
-- after the Worker has a validated vector in hand. Supports safe partial
-- resume: a retried batch simply re-calls this for whatever chunks are
-- still pending, and an already-succeeded identity is returned unchanged
-- (idempotent), never re-inserted or re-scored against the provider.
create or replace function record_document_chunk_embedding(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_embedding_run_id uuid,
  p_chunk_id uuid,
  p_embedding_identity_sha256 text,
  p_input_text_checksum text,
  p_input_token_count int,
  p_vector_value extensions.vector,
  p_vector_checksum text,
  p_vector_norm double precision,
  p_provider_metadata_safe jsonb default '{}'::jsonb,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunk_embeddings
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_embedding_runs%rowtype;
  v_chunk document_chunks%rowtype;
  v_config embedding_configurations%rowtype;
  v_existing document_chunk_embeddings%rowtype;
  v_row document_chunk_embeddings%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_embedding_runs where organization_id = v_job.organization_id and id = p_embedding_run_id for update;
  if not found then
    raise exception 'embedding run not found: %', p_embedding_run_id;
  end if;
  if v_run.processing_job_id <> p_processing_job_id then
    raise exception 'embedding run % does not belong to job %', p_embedding_run_id, p_processing_job_id;
  end if;

  select * into v_chunk from document_chunks where organization_id = v_job.organization_id and id = p_chunk_id;
  if not found or v_chunk.chunking_run_id <> v_run.chunking_run_id then
    raise exception 'chunk % does not belong to this embedding run', p_chunk_id;
  end if;

  select * into v_config from embedding_configurations where id = v_run.embedding_configuration_id;

  -- Idempotent replay: an identical successful identity already exists.
  select * into v_existing from document_chunk_embeddings
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

  insert into document_chunk_embeddings (
    organization_id, chunk_id, chunking_run_id, source_document_id, guideline_version_id,
    embedding_configuration_id, embedding_run_id,
    chunk_checksum, input_text_checksum, input_token_count, embedding_identity_sha256,
    embedding_dimension, vector_value, vector_checksum, vector_norm, provider_metadata_safe,
    status, completed_at, processing_job_id, created_by_worker
  ) values (
    v_job.organization_id, p_chunk_id, v_run.chunking_run_id, v_run.source_document_id, v_run.guideline_version_id,
    v_run.embedding_configuration_id, p_embedding_run_id,
    v_chunk.chunk_checksum, p_input_text_checksum, p_input_token_count, p_embedding_identity_sha256,
    v_config.embedding_dimension, p_vector_value, p_vector_checksum, p_vector_norm, coalesce(p_provider_metadata_safe, '{}'::jsonb),
    'succeeded', now(), p_processing_job_id, p_worker_instance_id
  )
  on conflict (embedding_run_id, chunk_id) do update set
    status = 'succeeded', completed_at = now(),
    vector_value = excluded.vector_value, vector_checksum = excluded.vector_checksum, vector_norm = excluded.vector_norm,
    provider_metadata_safe = excluded.provider_metadata_safe
  returning * into v_row;

  update document_embedding_runs set
    succeeded_count = (select count(*) from document_chunk_embeddings where embedding_run_id = p_embedding_run_id and status = 'succeeded'),
    pending_count = greatest(0, total_chunk_count - (select count(*) from document_chunk_embeddings where embedding_run_id = p_embedding_run_id and status = 'succeeded'))
  where id = p_embedding_run_id;

  return v_row;
end;
$$;

revoke all on function record_document_chunk_embedding(uuid, text, text, uuid, uuid, text, text, int, extensions.vector, text, double precision, jsonb, uuid) from public;

create or replace function finalize_document_embedding_run(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_embedding_run_id uuid,
  p_artifact_bucket text,
  p_artifact_path text,
  p_artifact_sha256 text,
  p_artifact_size_bytes bigint,
  p_artifact_media_type text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_embedding_run_id uuid, out_status text, out_succeeded_count int)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_embedding_runs%rowtype;
  v_succeeded_count int;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_embedding_runs where organization_id = v_job.organization_id and id = p_embedding_run_id for update;
  if not found then
    raise exception 'embedding run not found: %', p_embedding_run_id;
  end if;
  if v_run.processing_job_id <> p_processing_job_id then
    raise exception 'embedding run % does not belong to job %', p_embedding_run_id, p_processing_job_id;
  end if;

  if v_run.status in ('succeeded', 'succeeded_with_reuse') then
    return query select v_run.id, v_run.status, v_run.succeeded_count;
    return;
  end if;

  select count(*) into v_succeeded_count from document_chunk_embeddings
    where embedding_run_id = p_embedding_run_id and status = 'succeeded';

  if v_succeeded_count <> v_run.total_chunk_count then
    raise exception 'embedding_coverage_incomplete: % of % chunks have a succeeded embedding', v_succeeded_count, v_run.total_chunk_count
      using errcode = 'P0001';
  end if;

  update document_embedding_runs set
    status = 'succeeded',
    completed_at = now(),
    succeeded_count = v_succeeded_count,
    pending_count = 0,
    artifact_bucket = p_artifact_bucket,
    artifact_path = p_artifact_path,
    artifact_sha256 = p_artifact_sha256,
    artifact_size_bytes = p_artifact_size_bytes,
    artifact_media_type = p_artifact_media_type
  where id = p_embedding_run_id;

  perform complete_document_processing_job(
    p_processing_job_id, p_worker_instance_id, p_lease_token,
    jsonb_build_object('embedding_run_id', p_embedding_run_id, 'succeeded_count', v_succeeded_count),
    p_processing_job_id::text || ':finalize', p_correlation_id
  );

  perform record_audit_event(v_job.organization_id, 'document_embedding_run.succeeded', 'document_embedding_run', p_embedding_run_id, p_correlation_id,
    jsonb_build_object('succeeded_count', v_succeeded_count));

  return query select p_embedding_run_id, 'succeeded'::text, v_succeeded_count;
end;
$$;

revoke all on function finalize_document_embedding_run(uuid, text, text, uuid, text, text, text, bigint, text, uuid) from public;

create or replace function fail_document_embedding_run(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_embedding_run_id uuid,
  p_error_code text,
  p_error_class text,
  p_error_message_safe text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_embedding_run_id uuid, out_status text)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_embedding_runs%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_embedding_runs where organization_id = v_job.organization_id and id = p_embedding_run_id for update;
  if not found then
    raise exception 'embedding run not found: %', p_embedding_run_id;
  end if;
  if v_run.status = 'processing' or v_run.status = 'created' or v_run.status = 'queued' then
    update document_embedding_runs set status = 'failed', failed_at = now() where id = p_embedding_run_id;
  end if;

  perform fail_document_processing_job(
    p_processing_job_id, p_worker_instance_id, p_lease_token,
    p_error_code, p_error_class, p_error_message_safe, true,
    p_processing_job_id::text || ':fail', p_correlation_id
  );

  perform record_audit_event(v_job.organization_id, 'document_embedding_run.failed', 'document_embedding_run', p_embedding_run_id, p_correlation_id,
    jsonb_build_object('error_code', p_error_code));

  return query select p_embedding_run_id, 'failed'::text;
end;
$$;

revoke all on function fail_document_embedding_run(uuid, text, text, uuid, text, text, text, uuid) from public;

-- ============================================================================
-- 12. Guarded double-revoke from authenticated/anon (mission's own
--     documented hosted-only default-privilege fact, migration 0007) for
--     every Worker-only function above.
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke execute on function
      get_document_embedding_job_context(uuid, text, text),
      create_document_embedding_run(uuid, text, text, uuid, uuid, uuid, jsonb, text, int, uuid),
      record_document_chunk_embedding(uuid, text, text, uuid, uuid, text, text, int, extensions.vector, text, double precision, jsonb, uuid),
      finalize_document_embedding_run(uuid, text, text, uuid, text, text, text, bigint, text, uuid),
      fail_document_embedding_run(uuid, text, text, uuid, text, text, text, uuid)
      from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke execute on function
      get_document_embedding_job_context(uuid, text, text),
      create_document_embedding_run(uuid, text, text, uuid, uuid, uuid, jsonb, text, int, uuid),
      record_document_chunk_embedding(uuid, text, text, uuid, uuid, text, text, int, extensions.vector, text, double precision, jsonb, uuid),
      finalize_document_embedding_run(uuid, text, text, uuid, text, text, text, bigint, text, uuid),
      fail_document_embedding_run(uuid, text, text, uuid, text, text, text, uuid)
      from anon;
  end if;
end
$$;

-- ============================================================================
-- 13. Guarded grants for client-facing functions
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
      get_approved_embedding_configuration(),
      create_document_embedding_job(uuid, text, uuid),
      cancel_document_embedding_run(uuid, text, uuid)
      to authenticated;
  end if;
end
$$;
