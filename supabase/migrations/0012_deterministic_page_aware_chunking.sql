-- ============================================================================
-- Noor V1 — Migration 0012: Deterministic Page-Aware Chunking (schema + execution)
-- Council: AI/RAG Agent + Backend Agent + Database Agent + Security Agent
-- ============================================================================
-- Sprint 1-D3. Turns canonical per-page text (get_document_page_text_readiness,
-- migration 0011) into ordered, provenance-preserving chunks. See ADR 0014
-- for the full rationale (renumbered from the mission's suggested 0013,
-- which UX-1 already used).
--
-- This migration covers schema + execution (chunking runs, chunks, source
-- spans, job creation, Worker finalization). Chunk technical review,
-- findings, and embedding readiness are migration 0013 — the same
-- execution/review split every prior sprint (S1-D1, S1-D2) has used.
-- ============================================================================

-- ============================================================================
-- 1. EXTEND document_processing_jobs for job_type = 'document_chunking'
-- ============================================================================

alter table document_processing_jobs
  drop constraint if exists document_processing_jobs_job_type_check;

alter table document_processing_jobs
  add constraint document_processing_jobs_job_type_check
  check (job_type in ('document_parsing', 'document_ocr', 'document_chunking'));

-- Document-scoped, like extraction's own index (not page-scoped like OCR's) —
-- chunking needs whole-document context, so at most one active chunking job
-- may exist per document at a time.
create unique index if not exists document_processing_jobs_one_active_chunking_per_document
  on document_processing_jobs (source_document_id, job_type)
  where job_type = 'document_chunking' and status in ('queued', 'claimed', 'processing');

-- ============================================================================
-- 2. document_chunking_runs — one execution attempt at one deterministic identity
-- ============================================================================

create table if not exists document_chunking_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,

  source_document_id uuid not null,
  guideline_version_id uuid not null,
  guideline_id uuid not null,
  extraction_run_id uuid not null,
  extraction_review_id uuid not null,
  ocr_request_id uuid,
  ocr_review_id uuid,
  processing_job_id uuid not null,
  processing_attempt_id uuid,

  source_sha256 text not null,
  input_manifest jsonb not null,
  input_manifest_sha256 text not null,

  pipeline_version text not null,
  configuration_version text not null,
  normalization_version text not null,
  tokenizer_name text not null,
  tokenizer_version text not null,

  status text not null default 'running'
    check (status in ('running', 'succeeded', 'failed', 'invalidated', 'reused')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,
  invalidated_at timestamptz,
  invalidation_reason text,

  chunk_count int,
  page_count int,
  native_page_count int,
  ocr_page_count int,
  total_characters bigint,
  total_words bigint,
  total_tokens bigint,
  minimum_chunk_tokens int,
  maximum_chunk_tokens int,
  average_chunk_tokens numeric,
  chunks_below_minimum int,
  chunks_above_target int,
  chunks_at_hard_maximum int,
  hard_split_count int,
  heading_boundary_count int,
  list_boundary_count int,
  table_like_chunk_count int,
  warning_chunk_count int,
  coverage_percentage numeric,
  duplication_percentage numeric,
  metrics jsonb not null default '{}'::jsonb,
  warnings jsonb not null default '[]'::jsonb,

  artifact_bucket text,
  artifact_path text,
  artifact_sha256 text,
  artifact_size_bytes bigint,
  artifact_media_type text,

  created_at timestamptz not null default now(),
  created_by_worker text,

  unique (organization_id, id)
);

-- Deterministic identity uniqueness — at most one succeeded run per full
-- identity tuple. A change to ANY component (including the manifest hash,
-- which itself changes if any page's accepted representation changes) is,
-- by definition, a new attempt, never a silent overwrite.
create unique index if not exists document_chunking_runs_one_succeeded_per_identity
  on document_chunking_runs (
    organization_id, source_document_id, source_sha256, input_manifest_sha256,
    pipeline_version, configuration_version, normalization_version,
    tokenizer_name, tokenizer_version
  )
  where status = 'succeeded';

create index if not exists document_chunking_runs_by_document
  on document_chunking_runs (organization_id, source_document_id, created_at desc);

alter table document_chunking_runs
  add constraint document_chunking_runs_source_document_id_fkey
  foreign key (organization_id, source_document_id) references guideline_source_documents(organization_id, id);

alter table document_chunking_runs
  add constraint document_chunking_runs_guideline_version_id_fkey
  foreign key (organization_id, guideline_version_id) references guideline_versions(organization_id, id);

alter table document_chunking_runs
  add constraint document_chunking_runs_guideline_id_fkey
  foreign key (organization_id, guideline_id) references guidelines(organization_id, id);

alter table document_chunking_runs
  add constraint document_chunking_runs_extraction_run_id_fkey
  foreign key (organization_id, extraction_run_id) references document_extraction_runs(organization_id, id);

alter table document_chunking_runs
  add constraint document_chunking_runs_extraction_review_id_fkey
  foreign key (organization_id, extraction_review_id) references document_extraction_reviews(organization_id, id);

alter table document_chunking_runs
  add constraint document_chunking_runs_ocr_request_id_fkey
  foreign key (organization_id, ocr_request_id) references document_ocr_requests(organization_id, id);

alter table document_chunking_runs
  add constraint document_chunking_runs_ocr_review_id_fkey
  foreign key (organization_id, ocr_review_id) references document_ocr_reviews(organization_id, id);

alter table document_chunking_runs
  add constraint document_chunking_runs_processing_job_id_fkey
  foreign key (organization_id, processing_job_id) references document_processing_jobs(organization_id, id);

alter table document_chunking_runs
  add constraint document_chunking_runs_processing_attempt_id_fkey
  foreign key (organization_id, processing_attempt_id) references document_processing_attempts(organization_id, id);

-- Freezes provenance/artifact columns once a run reaches a terminal state —
-- the same conditional-freeze shape as document_extraction_runs/
-- document_ocr_runs' own triggers (0008/0011), reused rather than reinvented.
create or replace function prevent_terminal_chunking_run_mutation()
returns trigger language plpgsql as $$
begin
  if old.status in ('succeeded', 'failed', 'invalidated', 'reused') then
    if new.status = 'invalidated' and old.status in ('succeeded', 'reused') then
      if new.invalidated_at is null or new.invalidation_reason is null then
        raise exception 'invalidating a chunking run requires invalidated_at and invalidation_reason';
      end if;
      -- Only invalidation-related columns may change on an otherwise-terminal row.
      if new.id <> old.id or new.organization_id <> old.organization_id
        or new.chunk_count is distinct from old.chunk_count
        or new.artifact_sha256 is distinct from old.artifact_sha256
        or new.input_manifest_sha256 is distinct from old.input_manifest_sha256
      then
        raise exception 'a terminal chunking run may only transition to invalidated, with no other field changed';
      end if;
      new.status := 'invalidated';
      return new;
    end if;
    raise exception 'chunking run % is already terminal (status: %) and cannot be modified', old.id, old.status;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_terminal_chunking_run_mutation on document_chunking_runs;
create trigger trg_prevent_terminal_chunking_run_mutation
  before update on document_chunking_runs
  for each row execute function prevent_terminal_chunking_run_mutation();

alter table document_chunking_runs enable row level security;

-- ============================================================================
-- 3. document_chunks — one immutable chunk per (run, chunk_index)
-- ============================================================================

create table if not exists document_chunks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  chunking_run_id uuid not null,
  source_document_id uuid not null,

  chunk_index int not null check (chunk_index >= 1),
  chunk_text text not null,
  chunk_checksum text not null,

  page_start int not null check (page_start >= 1),
  page_end int not null check (page_end >= 1),
  source_span_count int not null default 0,

  token_count int not null check (token_count >= 0),
  character_count int not null check (character_count >= 0),
  word_count int not null check (word_count >= 0),

  heading_context text,
  block_type_summary jsonb not null default '[]'::jsonb,
  boundary_start_reason text not null,
  boundary_end_reason text not null,

  contains_native_text boolean not null default false,
  contains_ocr_text boolean not null default false,
  warning_state boolean not null default false,
  warnings jsonb not null default '[]'::jsonb,

  created_at timestamptz not null default now(),

  -- V1 hard page-boundary policy (ADR 0014, mission §14): enforced as a
  -- real constraint, not just a convention a reviewer could miss.
  constraint document_chunks_hard_page_boundary check (page_end = page_start),

  unique (organization_id, id),
  unique (chunking_run_id, chunk_index)
);

alter table document_chunks
  add constraint document_chunks_chunking_run_id_fkey
  foreign key (organization_id, chunking_run_id) references document_chunking_runs(organization_id, id);

create index if not exists document_chunks_by_run on document_chunks (organization_id, chunking_run_id, chunk_index);

create or replace function prevent_document_chunk_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'document chunk % is immutable once created', old.id;
end;
$$;

drop trigger if exists trg_prevent_document_chunk_mutation on document_chunks;
create trigger trg_prevent_document_chunk_mutation
  before update on document_chunks
  for each row execute function prevent_document_chunk_mutation();

drop trigger if exists trg_prevent_document_chunk_delete on document_chunks;
create trigger trg_prevent_document_chunk_delete
  before delete on document_chunks
  for each row execute function prevent_document_chunk_mutation();

alter table document_chunks enable row level security;

-- ============================================================================
-- 4. document_chunk_source_spans — exact character provenance per chunk
-- ============================================================================

create table if not exists document_chunk_source_spans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  chunking_run_id uuid not null,
  chunk_id uuid not null,

  page_number int not null check (page_number >= 1),
  representation_type text not null check (representation_type in ('native', 'ocr')),
  representation_id uuid not null,
  representation_checksum text not null,

  -- Zero-based, start-inclusive, end-exclusive — documented once here as
  -- the one authoritative offset convention (mission §20).
  start_character_offset int not null check (start_character_offset >= 0),
  end_character_offset int not null check (end_character_offset > start_character_offset),
  source_fragment_checksum text not null,

  span_order int not null check (span_order >= 1),
  block_type_hint text,
  boundary_reason text,

  unique (organization_id, id),
  unique (chunk_id, span_order)
);

alter table document_chunk_source_spans
  add constraint document_chunk_source_spans_chunking_run_id_fkey
  foreign key (organization_id, chunking_run_id) references document_chunking_runs(organization_id, id);

alter table document_chunk_source_spans
  add constraint document_chunk_source_spans_chunk_id_fkey
  foreign key (organization_id, chunk_id) references document_chunks(organization_id, id);

create index if not exists document_chunk_source_spans_by_chunk
  on document_chunk_source_spans (organization_id, chunk_id, span_order);
create index if not exists document_chunk_source_spans_by_run_page
  on document_chunk_source_spans (organization_id, chunking_run_id, page_number);

create or replace function prevent_chunk_source_span_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'chunk source span % is immutable once created', old.id;
end;
$$;

drop trigger if exists trg_prevent_chunk_source_span_mutation on document_chunk_source_spans;
create trigger trg_prevent_chunk_source_span_mutation
  before update on document_chunk_source_spans
  for each row execute function prevent_chunk_source_span_mutation();

drop trigger if exists trg_prevent_chunk_source_span_delete on document_chunk_source_spans;
create trigger trg_prevent_chunk_source_span_delete
  before delete on document_chunk_source_spans
  for each row execute function prevent_chunk_source_span_mutation();

alter table document_chunk_source_spans enable row level security;

-- ============================================================================
-- 5. Permissions (all guideline_chunking.* keys — 0013 adds no new ones,
--    it only maps the review-lifecycle keys already declared here)
-- ============================================================================

insert into permissions (key, description) values
  ('guideline_chunking.read', 'Read chunking runs, chunks, spans, reviews, and findings'),
  ('guideline_chunking.create', 'Create a chunking job from a chunking-eligible extraction run'),
  ('guideline_chunking.read_artifacts', 'Read chunking artifact checksum/path metadata'),
  ('guideline_chunking.review', 'Start a chunk review, mark chunks reviewed, and create findings'),
  ('guideline_chunking.submit_review', 'Submit a final chunk technical review decision'),
  ('guideline_chunking.reopen_review', 'Reopen a submitted chunk review as a new round'),
  ('guideline_chunking.invalidate', 'Invalidate a succeeded chunking run')
on conflict (key) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where (r.key, p.key) in (
  ('organization_admin', 'guideline_chunking.read'),
  ('organization_admin', 'guideline_chunking.create'),
  ('organization_admin', 'guideline_chunking.reopen_review'),

  ('quality_manager', 'guideline_chunking.read'),
  ('quality_manager', 'guideline_chunking.create'),
  ('quality_manager', 'guideline_chunking.review'),
  ('quality_manager', 'guideline_chunking.submit_review'),
  ('quality_manager', 'guideline_chunking.reopen_review'),
  ('quality_manager', 'guideline_chunking.read_artifacts'),
  ('quality_manager', 'guideline_chunking.invalidate'),

  ('clinical_reviewer', 'guideline_chunking.read'),
  ('clinical_reviewer', 'guideline_chunking.review'),
  ('clinical_reviewer', 'guideline_chunking.submit_review'),

  ('safety_officer', 'guideline_chunking.read'),
  ('auditor', 'guideline_chunking.read')
)
on conflict do nothing;

-- ============================================================================
-- 6. RLS — SELECT-only for authenticated; all writes are SECURITY DEFINER
-- ============================================================================

drop policy if exists document_chunking_runs_select on document_chunking_runs;
create policy document_chunking_runs_select on document_chunking_runs
  for select using (has_permission_in_organization(organization_id, 'guideline_chunking.read'));

drop policy if exists document_chunks_select on document_chunks;
create policy document_chunks_select on document_chunks
  for select using (has_permission_in_organization(organization_id, 'guideline_chunking.read'));

drop policy if exists document_chunk_source_spans_select on document_chunk_source_spans;
create policy document_chunk_source_spans_select on document_chunk_source_spans
  for select using (has_permission_in_organization(organization_id, 'guideline_chunking.read'));

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on document_chunking_runs, document_chunks, document_chunk_source_spans to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 7. Extend migration 0010's guideline-processed Storage policy to also
--    accept guideline_chunking.read_artifacts — the chunk artifact lives in
--    the same bucket as extraction/OCR artifacts. Same guarded pattern 0010
--    itself used to replace 0003's policies; storage.objects only exists
--    against a real Supabase stack (local CLI or hosted), never plain
--    Postgres, so this is a documented no-op in the CI `database` job.
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
          )
        )
    $policy$;
  end if;
end
$$;

-- ============================================================================
-- 8. create_document_chunking_job — client-facing job creation
-- ============================================================================

create or replace function create_document_chunking_job(
  p_source_document_id uuid,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (
  out_job_id uuid,
  out_status text,
  out_reused boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_doc guideline_source_documents%rowtype;
  v_run document_extraction_runs%rowtype;
  v_elig record;
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

  perform assert_permission(v_doc.organization_id, 'guideline_chunking.create');

  if v_doc.status <> 'registered' then
    raise exception 'source document is not registered (status: %)', v_doc.status;
  end if;

  select * into v_run from document_extraction_runs
    where organization_id = v_doc.organization_id and source_document_id = p_source_document_id
      and status = 'succeeded'
    order by created_at desc limit 1;
  if not found then
    raise exception 'no succeeded extraction run exists for this document';
  end if;

  select * into v_elig from get_document_extraction_review_eligibility(v_run.id);
  if not v_elig.out_eligible_for_chunking then
    raise exception 'this document is not chunking-eligible (review status: %)', v_elig.out_review_status;
  end if;

  -- Idempotent: an active (queued/claimed/processing) chunking job for this
  -- document is reused rather than duplicated.
  select * into v_existing_job from document_processing_jobs
    where organization_id = v_doc.organization_id and source_document_id = p_source_document_id
      and job_type = 'document_chunking' and status in ('queued', 'claimed', 'processing', 'retry_scheduled')
    order by created_at desc limit 1;
  if found then
    return query select v_existing_job.id, v_existing_job.status, true;
    return;
  end if;

  -- idempotency_key is deliberately left null on the job row itself (same
  -- pattern as create_document_ocr_request's job insert, migration 0011):
  -- unlike document_parsing (one job ever per document), a document may
  -- legitimately get more than one document_chunking job over its lifetime
  -- (e.g. after a rechunk), so a permanent per-org idempotency_key would
  -- collide with document_processing_jobs' own unique(organization_id,
  -- idempotency_key) constraint on the second attempt. Idempotency here is
  -- enforced by the "existing active job" check above instead.
  insert into document_processing_jobs (
    organization_id, source_document_id, job_type, pipeline_version, status,
    requested_by, correlation_id
  ) values (
    v_doc.organization_id, p_source_document_id, 'document_chunking', 'controlled-page-aware-chunking-v1', 'queued',
    v_actor, p_correlation_id
  )
  returning * into v_job;

  perform record_audit_event(v_doc.organization_id, 'document_chunking.requested', 'document_processing_job', v_job.id, p_correlation_id,
    jsonb_build_object('source_document_id', p_source_document_id, 'extraction_run_id', v_run.id));

  return query select v_job.id, v_job.status, false;
end;
$$;

revoke all on function create_document_chunking_job(uuid, text, uuid) from public;

-- ============================================================================
-- 9. Worker-only: get_document_chunking_job_context (readiness + text, the
--    Worker's own un-gated equivalent of get_document_page_text_readiness),
--    create_document_chunking_run (identity-based idempotent creation), and
--    finalize_document_chunking_run (atomic chunk insertion + coverage
--    revalidation + success)
-- ============================================================================

-- get_document_page_text_readiness (migration 0011) and
-- get_document_extraction_review_eligibility (migration 0009/0011) both call
-- assert_permission(), which checks auth.uid() membership — that is correct
-- for their real caller (an authenticated browser session in the reviewer
-- UI) but auth.uid() is always null for this Worker's service_role RPC
-- calls, so those two functions can never be called from here (they would
-- unconditionally raise "permission denied"). Every Worker-only function in
-- this codebase instead authenticates via lease ownership
-- (assert_lease_owner) rather than organization permissions — this function
-- follows that same established boundary, re-deriving the identical
-- readiness logic get_document_page_text_readiness implements (including
-- actual page text, which that function does not return) without the
-- permission gate. See ADR 0014.
create or replace function get_document_chunking_job_context(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text
) returns table (
  out_source_document_id uuid,
  out_extraction_run_id uuid,
  out_extraction_review_id uuid,
  out_ocr_request_id uuid,
  out_ocr_review_id uuid,
  out_page_number int,
  out_representation_type text,
  out_representation_id uuid,
  out_text_checksum text,
  out_normalized_text text,
  out_character_count int,
  out_word_count int,
  out_warning_state boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_extraction_runs%rowtype;
  v_review document_extraction_reviews%rowtype;
  v_ocr_request document_ocr_requests%rowtype;
  v_ocr_review document_ocr_reviews%rowtype;
  v_all_ready boolean;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);
  if v_job.job_type <> 'document_chunking' then
    raise exception 'job % is not a document_chunking job (actual type: %)', p_processing_job_id, v_job.job_type;
  end if;

  select * into v_run from document_extraction_runs
    where organization_id = v_job.organization_id and source_document_id = v_job.source_document_id
      and status = 'succeeded'
    order by created_at desc limit 1;
  if not found then
    raise exception 'no succeeded extraction run exists for this document' using errcode = 'P0001';
  end if;

  select * into v_review from document_extraction_reviews
    where organization_id = v_run.organization_id and extraction_run_id = v_run.id
    order by review_round desc limit 1;
  if not found or v_review.review_status not in ('accepted', 'accepted_with_warnings', 'ocr_required') then
    raise exception 'this document is not chunking-eligible (review status: %)', coalesce(v_review.review_status, 'no_review')
      using errcode = 'P0001';
  end if;

  if v_review.review_status in ('accepted', 'accepted_with_warnings') then
    return query
      select v_job.source_document_id, v_run.id, v_review.id, null::uuid, null::uuid,
        dep.page_number, 'native'::text, dep.id, dep.page_checksum,
        dep.normalized_text, dep.character_count, dep.word_count,
        (v_review.review_status = 'accepted_with_warnings')
      from document_extraction_pages dep
      where dep.extraction_run_id = v_run.id
      order by dep.page_number;
    return;
  end if;

  -- review_status = 'ocr_required' — same per-page native/OCR resolution
  -- get_document_page_text_readiness implements, joined to actual text.
  select * into v_ocr_request from document_ocr_requests
    where organization_id = v_run.organization_id and extraction_review_id = v_review.id
      and status not in ('cancelled', 'invalidated')
    limit 1;

  if found then
    select * into v_ocr_review from document_ocr_reviews
      where organization_id = v_run.organization_id and ocr_request_id = v_ocr_request.id
      order by review_round desc limit 1;
  end if;

  select bool_and(
    case
      when per.review_status is distinct from 'ocr_candidate' then true
      when opr.review_status in ('accepted', 'accepted_with_warnings') and orr.status = 'succeeded' then true
      else false
    end
  ) into v_all_ready
  from document_extraction_pages dep
  left join document_extraction_page_reviews per
    on per.extraction_review_id = v_review.id and per.page_number = dep.page_number
  left join document_ocr_page_reviews opr
    on v_ocr_review.id is not null and opr.ocr_review_id = v_ocr_review.id and opr.page_number = dep.page_number
  left join document_ocr_runs orr
    on orr.id = opr.ocr_run_id
  where dep.extraction_run_id = v_run.id;

  if not coalesce(v_all_ready, false) then
    raise exception 'this document is not chunking-eligible (one or more pages are not OCR-ready)' using errcode = 'P0001';
  end if;

  return query
  select
    v_job.source_document_id, v_run.id, v_review.id, v_ocr_request.id, v_ocr_review.id,
    dep.page_number,
    case when per.review_status is distinct from 'ocr_candidate' then 'native' else 'ocr' end,
    case when per.review_status is distinct from 'ocr_candidate' then dep.id else orr.id end,
    case when per.review_status is distinct from 'ocr_candidate' then dep.page_checksum else orr.text_checksum end,
    case when per.review_status is distinct from 'ocr_candidate' then dep.normalized_text else orr.normalized_text end,
    case when per.review_status is distinct from 'ocr_candidate' then dep.character_count else orr.character_count end,
    case when per.review_status is distinct from 'ocr_candidate' then dep.word_count else orr.word_count end,
    case when per.review_status is distinct from 'ocr_candidate' then false else (opr.review_status = 'accepted_with_warnings') end
  from document_extraction_pages dep
  left join document_extraction_page_reviews per
    on per.extraction_review_id = v_review.id and per.page_number = dep.page_number
  left join document_ocr_page_reviews opr
    on v_ocr_review.id is not null and opr.ocr_review_id = v_ocr_review.id and opr.page_number = dep.page_number
  left join document_ocr_runs orr
    on orr.id = opr.ocr_run_id
  where dep.extraction_run_id = v_run.id
  order by dep.page_number;
end;
$$;

revoke all on function get_document_chunking_job_context(uuid, text, text) from public;

create or replace function create_document_chunking_run(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_extraction_run_id uuid,
  p_extraction_review_id uuid,
  p_source_sha256 text,
  p_input_manifest jsonb,
  p_input_manifest_sha256 text,
  p_pipeline_version text,
  p_configuration_version text,
  p_normalization_version text,
  p_tokenizer_name text,
  p_tokenizer_version text,
  -- Trailing with defaults (Postgres requires defaulted params last): both
  -- are genuinely absent for a native-only chunking run (no OCR involved),
  -- and PostgREST's named-parameter RPC calling convention requires every
  -- non-default parameter to be present in the request body — omitting
  -- these two when null (as app/orchestration_client.py's _rpc() does for
  -- every optional field) would otherwise make PostgREST unable to resolve
  -- the function at all.
  p_ocr_request_id uuid default null,
  p_ocr_review_id uuid default null,
  p_correlation_id uuid default gen_random_uuid()
) returns table (
  out_chunking_run_id uuid,
  out_status text,
  out_reused boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_doc guideline_source_documents%rowtype;
  v_extraction_run document_extraction_runs%rowtype;
  v_review document_extraction_reviews%rowtype;
  v_existing document_chunking_runs%rowtype;
  v_run document_chunking_runs%rowtype;
  v_guideline_version_id uuid;
  v_guideline_id uuid;
  v_attempt_id uuid;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);
  if v_job.job_type <> 'document_chunking' then
    raise exception 'job % is not a document_chunking job (actual type: %)', p_processing_job_id, v_job.job_type;
  end if;

  select id into v_attempt_id from document_processing_attempts
    where organization_id = v_job.organization_id
      and processing_job_id = p_processing_job_id
      and attempt_number = v_job.attempt_count;

  select * into v_doc from guideline_source_documents where organization_id = v_job.organization_id and id = v_job.source_document_id;
  if v_doc.sha256 is distinct from p_source_sha256 then
    raise exception 'source checksum does not match the registered document' using errcode = 'P0001';
  end if;

  -- Revalidate live readiness at run-creation time — the Worker's own
  -- manifest reflects readiness at claim time, which may already be stale.
  -- Cannot call get_document_extraction_review_eligibility() here (see the
  -- comment on get_document_chunking_job_context above) — the equivalent
  -- direct-table check is inlined instead.
  select * into v_extraction_run from document_extraction_runs where id = p_extraction_run_id;
  if not found or v_extraction_run.status <> 'succeeded' then
    raise exception 'this extraction run is no longer chunking-eligible (status: %)', coalesce(v_extraction_run.status, 'not_found')
      using errcode = 'P0001';
  end if;
  select * into v_review from document_extraction_reviews
    where organization_id = v_extraction_run.organization_id and extraction_run_id = p_extraction_run_id
    order by review_round desc limit 1;
  if not found or v_review.review_status not in ('accepted', 'accepted_with_warnings', 'ocr_required') then
    raise exception 'this extraction run is no longer chunking-eligible (review status: %)', coalesce(v_review.review_status, 'no_review')
      using errcode = 'P0001';
  end if;

  select guideline_version_id into v_guideline_version_id from guideline_source_documents
    where organization_id = v_job.organization_id and id = v_job.source_document_id;
  select guideline_id into v_guideline_id from guideline_versions
    where organization_id = v_job.organization_id and id = v_guideline_version_id;

  -- Identity-based idempotent reuse — same shape as create_document_extraction_run/create_document_ocr_run.
  select * into v_existing from document_chunking_runs
    where organization_id = v_job.organization_id
      and source_document_id = v_job.source_document_id
      and source_sha256 = p_source_sha256
      and input_manifest_sha256 = p_input_manifest_sha256
      and pipeline_version = p_pipeline_version
      and configuration_version = p_configuration_version
      and normalization_version = p_normalization_version
      and tokenizer_name = p_tokenizer_name
      and tokenizer_version = p_tokenizer_version
      and status = 'succeeded';

  if found then
    return query select v_existing.id, 'reused'::text, true;
    return;
  end if;

  insert into document_chunking_runs (
    organization_id, source_document_id, guideline_version_id, guideline_id,
    extraction_run_id, extraction_review_id, ocr_request_id, ocr_review_id,
    processing_job_id, processing_attempt_id,
    source_sha256, input_manifest, input_manifest_sha256,
    pipeline_version, configuration_version, normalization_version, tokenizer_name, tokenizer_version,
    status, created_by_worker
  ) values (
    v_job.organization_id, v_job.source_document_id, v_guideline_version_id, v_guideline_id,
    p_extraction_run_id, p_extraction_review_id, p_ocr_request_id, p_ocr_review_id,
    p_processing_job_id, v_attempt_id,
    p_source_sha256, p_input_manifest, p_input_manifest_sha256,
    p_pipeline_version, p_configuration_version, p_normalization_version, p_tokenizer_name, p_tokenizer_version,
    'running', p_worker_instance_id
  )
  returning * into v_run;

  perform record_audit_event(v_job.organization_id, 'document_chunking.input_manifest_created', 'document_chunking_run', v_run.id, p_correlation_id,
    jsonb_build_object('input_manifest_sha256', p_input_manifest_sha256));

  return query select v_run.id, v_run.status, false;
end;
$$;

revoke all on function create_document_chunking_run(uuid, text, text, uuid, uuid, text, jsonb, text, text, text, text, text, text, uuid, uuid, uuid) from public;

-- ----------------------------------------------------------------------------
-- finalize_document_chunking_run — atomic: inserts every chunk + its source
-- spans from Worker-computed jsonb arrays, revalidates counts/coverage, and
-- marks the run succeeded + completes the job, in one transaction. Payload
-- size is bounded in practice by this sprint's synthetic fixtures (a few
-- pages); a future revision may need batched inserts for very large real
-- documents — see docs/operations/chunking-worker-runbook.md.
-- ----------------------------------------------------------------------------

create or replace function finalize_document_chunking_run(
  p_chunking_run_id uuid,
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_chunks jsonb,
  p_metrics jsonb,
  p_warnings jsonb,
  p_artifact_bucket text,
  p_artifact_path text,
  p_artifact_sha256 text,
  p_artifact_size_bytes bigint,
  p_artifact_media_type text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_chunking_run_id uuid, out_status text, out_chunk_count int)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_chunking_runs%rowtype;
  v_chunk jsonb;
  v_span jsonb;
  v_chunk_id uuid;
  v_chunk_count int := 0;
  v_coverage numeric;
  v_duplication numeric;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_chunking_runs
    where organization_id = v_job.organization_id and id = p_chunking_run_id for update;
  if not found then
    raise exception 'chunking run not found: %', p_chunking_run_id;
  end if;
  if v_run.processing_job_id <> p_processing_job_id then
    raise exception 'chunking run % does not belong to job %', p_chunking_run_id, p_processing_job_id;
  end if;

  if v_run.status = 'succeeded' then
    -- Replay-safe: already finalized (e.g. a retried RPC after a network
    -- blip) — return the existing result rather than erroring or duplicating.
    return query select v_run.id, v_run.status, v_run.chunk_count;
    return;
  end if;
  if v_run.status <> 'running' then
    raise exception 'chunking run % is not running (status: %)', p_chunking_run_id, v_run.status;
  end if;

  v_coverage := (p_metrics ->> 'coverage_percentage')::numeric;
  v_duplication := (p_metrics ->> 'duplication_percentage')::numeric;
  if v_coverage is distinct from 100 then
    raise exception 'coverage_validation_failed: coverage_percentage = % (must be 100)', v_coverage using errcode = 'P0001';
  end if;
  if v_duplication is distinct from 0 then
    raise exception 'unexpected_duplication_detected: duplication_percentage = % (must be 0)', v_duplication using errcode = 'P0001';
  end if;

  for v_chunk in select * from jsonb_array_elements(p_chunks)
  loop
    insert into document_chunks (
      organization_id, chunking_run_id, source_document_id,
      chunk_index, chunk_text, chunk_checksum,
      page_start, page_end, source_span_count,
      token_count, character_count, word_count,
      heading_context, block_type_summary, boundary_start_reason, boundary_end_reason,
      contains_native_text, contains_ocr_text, warning_state, warnings
    ) values (
      v_job.organization_id, v_run.id, v_run.source_document_id,
      (v_chunk ->> 'chunk_index')::int, v_chunk ->> 'chunk_text', v_chunk ->> 'chunk_checksum',
      (v_chunk ->> 'page_start')::int, (v_chunk ->> 'page_end')::int,
      jsonb_array_length(v_chunk -> 'source_spans'),
      (v_chunk ->> 'token_count')::int, (v_chunk ->> 'character_count')::int, (v_chunk ->> 'word_count')::int,
      v_chunk ->> 'heading_context', coalesce(v_chunk -> 'block_type_summary', '[]'::jsonb),
      v_chunk ->> 'boundary_start_reason', v_chunk ->> 'boundary_end_reason',
      coalesce((v_chunk ->> 'contains_native_text')::boolean, false),
      coalesce((v_chunk ->> 'contains_ocr_text')::boolean, false),
      coalesce((v_chunk ->> 'warning_state')::boolean, false),
      coalesce(v_chunk -> 'warnings', '[]'::jsonb)
    )
    returning id into v_chunk_id;

    for v_span in select * from jsonb_array_elements(v_chunk -> 'source_spans')
    loop
      insert into document_chunk_source_spans (
        organization_id, chunking_run_id, chunk_id,
        page_number, representation_type, representation_id, representation_checksum,
        start_character_offset, end_character_offset, source_fragment_checksum,
        span_order, block_type_hint, boundary_reason
      ) values (
        v_job.organization_id, v_run.id, v_chunk_id,
        (v_span ->> 'page_number')::int, v_span ->> 'representation_type',
        (v_span ->> 'representation_id')::uuid, v_span ->> 'representation_checksum',
        (v_span ->> 'start_offset')::int, (v_span ->> 'end_offset')::int, v_span ->> 'source_fragment_checksum',
        (v_span ->> 'span_order')::int, v_span ->> 'block_type_hint', v_span ->> 'boundary_reason'
      );
    end loop;

    v_chunk_count := v_chunk_count + 1;
  end loop;

  update document_chunking_runs set
    status = 'succeeded',
    completed_at = now(),
    chunk_count = v_chunk_count,
    page_count = (p_metrics ->> 'page_count')::int,
    native_page_count = (p_metrics ->> 'native_representation_page_count')::int,
    ocr_page_count = (p_metrics ->> 'ocr_representation_page_count')::int,
    total_characters = (p_metrics ->> 'total_characters')::bigint,
    total_words = (p_metrics ->> 'total_words')::bigint,
    total_tokens = (p_metrics ->> 'total_tokens')::bigint,
    minimum_chunk_tokens = (p_metrics ->> 'minimum_chunk_tokens')::int,
    maximum_chunk_tokens = (p_metrics ->> 'maximum_chunk_tokens')::int,
    average_chunk_tokens = (p_metrics ->> 'average_chunk_tokens')::numeric,
    chunks_below_minimum = (p_metrics ->> 'chunks_below_minimum')::int,
    chunks_above_target = (p_metrics ->> 'chunks_above_target')::int,
    chunks_at_hard_maximum = (p_metrics ->> 'chunks_at_hard_maximum')::int,
    hard_split_count = (p_metrics ->> 'hard_split_count')::int,
    heading_boundary_count = (p_metrics ->> 'heading_boundary_count')::int,
    list_boundary_count = (p_metrics ->> 'list_boundary_count')::int,
    table_like_chunk_count = (p_metrics ->> 'table_like_chunk_count')::int,
    warning_chunk_count = (p_metrics ->> 'warning_chunk_count')::int,
    coverage_percentage = v_coverage,
    duplication_percentage = v_duplication,
    metrics = p_metrics,
    warnings = p_warnings,
    artifact_bucket = p_artifact_bucket,
    artifact_path = p_artifact_path,
    artifact_sha256 = p_artifact_sha256,
    artifact_size_bytes = p_artifact_size_bytes,
    artifact_media_type = p_artifact_media_type
  where id = v_run.id;

  perform complete_document_processing_job(
    p_processing_job_id, p_worker_instance_id, p_lease_token,
    jsonb_build_object('chunking_run_id', v_run.id, 'chunk_count', v_chunk_count),
    p_processing_job_id::text || ':finalize', p_correlation_id
  );

  perform record_audit_event(v_job.organization_id, 'document_chunking.succeeded', 'document_chunking_run', v_run.id, p_correlation_id,
    jsonb_build_object('chunk_count', v_chunk_count, 'coverage_percentage', v_coverage));

  return query select v_run.id, 'succeeded'::text, v_chunk_count;
end;
$$;

revoke all on function finalize_document_chunking_run(uuid, uuid, text, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid) from public;

create or replace function fail_document_chunking_run(
  p_chunking_run_id uuid,
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_error_code text,
  p_error_class text,
  p_error_message_safe text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_chunking_run_id uuid, out_status text)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_chunking_runs%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_chunking_runs
    where organization_id = v_job.organization_id and id = p_chunking_run_id for update;
  if not found then
    raise exception 'chunking run not found: %', p_chunking_run_id;
  end if;
  if v_run.status = 'running' then
    update document_chunking_runs set status = 'failed', failed_at = now() where id = v_run.id;
  end if;

  perform fail_document_processing_job(
    p_processing_job_id, p_worker_instance_id, p_lease_token,
    p_error_code, p_error_class, p_error_message_safe, true,
    p_processing_job_id::text || ':fail', p_correlation_id
  );

  perform record_audit_event(v_job.organization_id, 'document_chunking.failed', 'document_chunking_run', p_chunking_run_id, p_correlation_id,
    jsonb_build_object('error_code', p_error_code));

  return query select p_chunking_run_id, 'failed'::text;
end;
$$;

revoke all on function fail_document_chunking_run(uuid, uuid, text, text, text, text, text, uuid) from public;

-- ============================================================================
-- 10. GRANTS — client-facing functions only; Worker-only functions explicitly
--     revoked from authenticated/anon, guarded exactly like migrations 0009/0011
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function create_document_chunking_job(uuid, text, uuid) to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function get_document_chunking_job_context(uuid, text, text) from anon;
    revoke all on function create_document_chunking_run(uuid, text, text, uuid, uuid, text, jsonb, text, text, text, text, text, text, uuid, uuid, uuid) from anon;
    revoke all on function finalize_document_chunking_run(uuid, uuid, text, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid) from anon;
    revoke all on function fail_document_chunking_run(uuid, uuid, text, text, text, text, text, uuid) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function get_document_chunking_job_context(uuid, text, text) from authenticated;
    revoke all on function create_document_chunking_run(uuid, text, text, uuid, uuid, text, jsonb, text, text, text, text, text, text, uuid, uuid, uuid) from authenticated;
    revoke all on function finalize_document_chunking_run(uuid, uuid, text, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid) from authenticated;
    revoke all on function fail_document_chunking_run(uuid, uuid, text, text, text, text, text, uuid) from authenticated;
  end if;
end
$$;

-- ============================================================================
-- End of migration 0012
-- ============================================================================
