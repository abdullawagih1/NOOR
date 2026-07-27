-- ============================================================================
-- Noor V1 — Migration 0008: Deterministic PDF Page and Text Extraction
-- Council: Extraction Architecture Agent + PDF Engineering Agent +
--          Database Agent + Security Agent
-- ============================================================================
-- Sprint 1.2B. Plugs a real, deterministic PDF extraction processor into
-- the durable orchestration control plane migration 0007 already proved
-- correct (claim/lease/heartbeat/retry/recovery/cancel). This migration
-- adds ONLY the persistence layer for extraction provenance — the actual
-- PDF parsing (pypdf) runs in the Worker (apps/worker/app/pdf_extraction/*).
--
-- Deterministic extraction identity (never changes once a run succeeds):
--   organization_id + source_sha256 + pipeline_version +
--   configuration_version + extractor_name + extractor_version
-- One succeeded run per identity (partial unique index, below) — a second
-- claim of the same source document with the same versions reuses the
-- existing result rather than re-extracting or creating a conflicting one.
--
-- Reuses migration 0007's job_type: `document_parsing` already means "this
-- job's payload is a PDF that needs its text extracted" — this sprint is
-- what actually implements that job type for real, replacing the
-- controlled no-op processor for it. No new job_type value was introduced
-- (the mission's suggested WORKER_ENABLED_JOB_TYPES=document_extraction is
-- implemented using the existing `document_parsing` job_type value — see
-- docs/domain/document-extraction-lifecycle.md for the naming
-- reconciliation).
--
-- Trust boundary: the three new functions below follow the exact same
-- hardened pattern migration 0007 was corrected to use after hosted
-- verification found a real gap — narrow `search_path = public` (none of
-- these three need pgcrypto), and an explicit, guarded revoke from
-- `authenticated`/`anon` in addition to `revoke ... from public`, not
-- relying on the PUBLIC-pseudo-role revoke alone. See
-- supabase/tests/rls/007_security_hardening_review.sql and ADR 0009's
-- addendum.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLE — document_extraction_runs
-- ----------------------------------------------------------------------------
-- One row per extraction attempt at a given identity. Mutable in place
-- while `running` (mirrors document_processing_jobs/attempts, not the
-- append-only convention) — but once `succeeded`, its provenance and
-- artifact identity columns become permanently immutable via a trigger
-- below, not just a grant. `invalidated` is schema-ready but no function
-- sets it this sprint (reserved for a future controlled administrative
-- process — mission §21, §11.1).

create table if not exists document_extraction_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  source_document_id uuid not null,
  processing_job_id uuid not null,
  processing_attempt_id uuid,

  source_sha256 text not null,
  source_size_bytes bigint not null check (source_size_bytes > 0),

  pipeline_version text not null,
  configuration_version text not null,
  extractor_name text not null,
  extractor_version text not null,

  status text not null default 'running'
    check (status in ('running', 'succeeded', 'failed', 'invalidated')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,

  page_count int,
  pages_with_text int,
  blank_page_count int,
  suspected_scanned_page_count int,
  total_character_count bigint,
  total_word_count bigint,

  error_code text,
  error_class text,
  error_message_safe text,

  warning_count int not null default 0,
  warnings jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,

  artifact_bucket text,
  artifact_path text,
  artifact_sha256 text,
  artifact_size_bytes bigint,
  artifact_media_type text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_worker text,

  unique (organization_id, id)
);

alter table document_extraction_runs
  add constraint document_extraction_runs_organization_id_source_document_i_fkey
  foreign key (organization_id, source_document_id) references guideline_source_documents(organization_id, id);

alter table document_extraction_runs
  add constraint document_extraction_runs_organization_id_processing_job_id_fkey
  foreign key (organization_id, processing_job_id) references document_processing_jobs(organization_id, id);

alter table document_extraction_runs
  add constraint document_extraction_runs_organization_id_processing_attemp_fkey
  foreign key (organization_id, processing_attempt_id) references document_processing_attempts(organization_id, id);

-- Deterministic extraction identity: at most one SUCCEEDED run may exist
-- per (org, source checksum, exact pipeline/config/extractor versions).
-- Running/failed rows are deliberately excluded from this constraint —
-- multiple failed attempts at the same identity are normal (retries).
create unique index if not exists document_extraction_runs_one_succeeded_per_identity
  on document_extraction_runs (organization_id, source_sha256, pipeline_version, configuration_version, extractor_name, extractor_version)
  where status = 'succeeded';

create index if not exists idx_extraction_runs_org_document
  on document_extraction_runs (organization_id, source_document_id);
create index if not exists idx_extraction_runs_processing_job
  on document_extraction_runs (organization_id, processing_job_id);
create index if not exists idx_extraction_runs_status
  on document_extraction_runs (status);

comment on table document_extraction_runs is
  'One row per PDF extraction attempt. Provenance-complete: identifies the exact source document, checksum, processing job/attempt, and pipeline/extractor versions that produced (or attempted to produce) an artifact. See docs/database/deterministic-pdf-extraction-schema.md.';

-- Immutability: once succeeded, provenance and artifact identity can never
-- change — mirrors guideline_source_documents' conditional trigger
-- (migration 0006), not the unconditional append-only pattern, because
-- this row legitimately mutates in place from `running` to its terminal
-- status.
create or replace function prevent_succeeded_extraction_run_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'succeeded' then
    if new.source_sha256 is distinct from old.source_sha256
       or new.source_size_bytes is distinct from old.source_size_bytes
       or new.pipeline_version is distinct from old.pipeline_version
       or new.configuration_version is distinct from old.configuration_version
       or new.extractor_name is distinct from old.extractor_name
       or new.extractor_version is distinct from old.extractor_version
       or new.artifact_bucket is distinct from old.artifact_bucket
       or new.artifact_path is distinct from old.artifact_path
       or new.artifact_sha256 is distinct from old.artifact_sha256
       or new.artifact_size_bytes is distinct from old.artifact_size_bytes
       or new.page_count is distinct from old.page_count
    then
      raise exception 'a succeeded extraction run''s provenance and artifact identity cannot be changed'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_succeeded_extraction_run_mutation on document_extraction_runs;
create trigger trg_prevent_succeeded_extraction_run_mutation
  before update on document_extraction_runs
  for each row execute function prevent_succeeded_extraction_run_mutation();

-- ----------------------------------------------------------------------------
-- 2. TABLE — document_extraction_pages
-- ----------------------------------------------------------------------------
-- One row per extracted page. Fully immutable once inserted — there is no
-- legitimate reason to ever update a page row (a reprocessing attempt
-- creates a new extraction_run with its own fresh page rows instead).

create table if not exists document_extraction_pages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  extraction_run_id uuid not null,
  source_document_id uuid not null,

  page_number int not null check (page_number >= 1),
  width_points numeric,
  height_points numeric,
  rotation_degrees int not null default 0,

  raw_text text,
  normalized_text text,
  character_count int not null default 0,
  word_count int not null default 0,

  is_blank boolean not null default false,
  suspected_scanned boolean not null default false,
  extraction_status text not null
    check (extraction_status in ('text_extracted', 'blank_page', 'no_text_layer', 'partial_text', 'extraction_warning', 'failed')),
  warnings jsonb not null default '[]'::jsonb,
  page_checksum text not null,

  created_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (extraction_run_id, page_number)
);

alter table document_extraction_pages
  add constraint document_extraction_pages_organization_id_extraction_run__fkey
  foreign key (organization_id, extraction_run_id) references document_extraction_runs(organization_id, id);

alter table document_extraction_pages
  add constraint document_extraction_pages_organization_id_source_document__fkey
  foreign key (organization_id, source_document_id) references guideline_source_documents(organization_id, id);

create index if not exists idx_extraction_pages_source_document
  on document_extraction_pages (organization_id, source_document_id);
create index if not exists idx_extraction_pages_status
  on document_extraction_pages (extraction_status);
create index if not exists idx_extraction_pages_suspected_scanned
  on document_extraction_pages (suspected_scanned) where suspected_scanned;

comment on table document_extraction_pages is
  'One row per extracted PDF page. Immutable once inserted (trigger-enforced) — raw_text/normalized_text are kept queryable in Postgres rather than only inside the artifact, since a later reviewer workflow needs to query individual pages without re-downloading and parsing the whole JSON artifact. See docs/database/deterministic-pdf-extraction-schema.md for the storage-duplication tradeoff.';

create or replace function prevent_extraction_page_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'document_extraction_pages rows are immutable once inserted; create a new extraction run to reprocess'
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_prevent_extraction_page_update on document_extraction_pages;
create trigger trg_prevent_extraction_page_update
  before update on document_extraction_pages
  for each row execute function prevent_extraction_page_mutation();

-- ============================================================================
-- 3. PERMISSIONS
-- ============================================================================

insert into permissions (key, description) values
  ('guideline_extractions.read', 'Read extraction run status, versions, and technical metrics'),
  ('guideline_extractions.read_pages', 'Read individual extracted page text and per-page metrics'),
  ('guideline_extractions.read_artifacts', 'Read artifact checksum/path metadata'),
  ('guideline_extractions.invalidate', 'Reserved — no function checks this yet; a future controlled administrative invalidation workflow'),
  ('guideline_extractions.retry', 'Reserved — no function checks this yet; a future manual re-extraction trigger')
on conflict (key) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where (r.key, p.key) in (
  ('organization_admin', 'guideline_extractions.read'),
  ('organization_admin', 'guideline_extractions.read_pages'),
  ('organization_admin', 'guideline_extractions.read_artifacts'),
  ('organization_admin', 'guideline_extractions.invalidate'),
  ('organization_admin', 'guideline_extractions.retry'),

  ('knowledge_manager', 'guideline_extractions.read'),
  ('knowledge_manager', 'guideline_extractions.read_pages'),
  ('knowledge_manager', 'guideline_extractions.read_artifacts'),

  ('clinical_reviewer', 'guideline_extractions.read'),
  ('clinical_reviewer', 'guideline_extractions.read_pages'),

  ('quality_manager', 'guideline_extractions.read'),
  ('quality_manager', 'guideline_extractions.read_pages'),
  ('quality_manager', 'guideline_extractions.read_artifacts'),
  ('quality_manager', 'guideline_extractions.invalidate'),
  ('quality_manager', 'guideline_extractions.retry'),

  ('safety_officer', 'guideline_extractions.read'),
  ('safety_officer', 'guideline_extractions.read_pages'),
  ('safety_officer', 'guideline_extractions.read_artifacts'),

  ('auditor', 'guideline_extractions.read')
)
on conflict do nothing;

-- Clinicians hold none of these permissions, by design (mission §28) —
-- RLS below structurally returns zero extraction rows to a clinician
-- session regardless of UI.

-- ============================================================================
-- 4. RLS
-- ============================================================================

alter table document_extraction_runs enable row level security;
alter table document_extraction_pages enable row level security;

drop policy if exists document_extraction_runs_select on document_extraction_runs;
create policy document_extraction_runs_select on document_extraction_runs
  for select using (has_permission_in_organization(organization_id, 'guideline_extractions.read'));

drop policy if exists document_extraction_pages_select on document_extraction_pages;
create policy document_extraction_pages_select on document_extraction_pages
  for select using (has_permission_in_organization(organization_id, 'guideline_extractions.read_pages'));

-- No INSERT/UPDATE/DELETE policy exists for `authenticated` on either
-- table at all — every write happens through the SECURITY DEFINER
-- functions below (service_role only) or, for page rows, a direct
-- service_role table insert (RLS does not apply to service_role; see
-- docs/security/pdf-extraction-security.md).

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on document_extraction_runs, document_extraction_pages to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 5. FUNCTIONS — Worker-only (never granted to `authenticated`/`anon`)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 5.1 create_document_extraction_run
-- ----------------------------------------------------------------------------
-- Called once per extraction attempt, immediately after the Worker has
-- independently re-verified the downloaded source object's checksum
-- (Python-side) and before any page extraction begins. Re-verifies the
-- claimed lease AND re-verifies the source document's registered status
-- and checksum as a second, database-side line of defense — the Worker's
-- own Python-side check must never be the only thing standing between an
-- unverified/tampered source and an extraction artifact.
--
-- Idempotent reuse: if a SUCCEEDED run already exists for this exact
-- deterministic identity, returns it directly (out_reused = true) instead
-- of creating a new `running` row — the Worker can then skip extraction
-- entirely and complete the job immediately, reusing the existing
-- artifact.

create or replace function create_document_extraction_run(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_source_sha256 text,
  p_source_size_bytes bigint,
  p_pipeline_version text,
  p_configuration_version text,
  p_extractor_name text,
  p_extractor_version text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (
  out_extraction_run_id uuid,
  out_status text,
  out_reused boolean,
  out_source_document_id uuid,
  out_organization_id uuid
)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_doc guideline_source_documents%rowtype;
  v_attempt_id uuid;
  v_existing document_extraction_runs%rowtype;
  v_run_id uuid;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_doc from guideline_source_documents
    where organization_id = v_job.organization_id and id = v_job.source_document_id;
  if not found then
    raise exception 'source document not found for job %', p_processing_job_id;
  end if;

  if v_doc.status not in ('verified', 'registered') then
    raise exception 'source document is not verified or registered (status: %)', v_doc.status;
  end if;
  if v_doc.sha256 is distinct from p_source_sha256 then
    raise exception 'source checksum does not match the registered document';
  end if;
  if v_doc.size_bytes is distinct from p_source_size_bytes then
    raise exception 'source size does not match the registered document';
  end if;

  select id into v_attempt_id from document_processing_attempts
    where organization_id = v_job.organization_id
      and processing_job_id = p_processing_job_id
      and attempt_number = v_job.attempt_count;

  -- Identity reuse / concurrency handling: at most one row may ever exist
  -- per identity in a non-terminal-failed state (running or succeeded).
  --   - succeeded  -> reuse it outright (out_reused = true), never re-extract.
  --   - running, same attempt -> the same attempt calling again (a retried
  --     HTTP call, not a new extraction) — attach to the same row rather
  --     than creating a duplicate (this is exactly what TEST 4 in
  --     008_pdf_extraction.sql proves).
  --   - running, a DIFFERENT (older) attempt -> orphaned: that attempt's
  --     Worker crashed or lost its lease before finalizing/failing the
  --     run. Supersede it (mark it failed) and create a fresh row for the
  --     current attempt — never leave two 'running' rows at the same
  --     identity, and never block forever on a dead attempt's row.
  select * into v_existing from document_extraction_runs
    where organization_id = v_job.organization_id
      and source_sha256 = p_source_sha256
      and pipeline_version = p_pipeline_version
      and configuration_version = p_configuration_version
      and extractor_name = p_extractor_name
      and extractor_version = p_extractor_version
      and status in ('running', 'succeeded')
    order by (status = 'succeeded') desc, created_at desc
    limit 1
    for update;

  if found and v_existing.status = 'succeeded' then
    return query select v_existing.id, v_existing.status, true, v_doc.id, v_job.organization_id;
    return;
  end if;

  if found and v_existing.status = 'running' and v_existing.processing_attempt_id is not distinct from v_attempt_id then
    return query select v_existing.id, v_existing.status, false, v_doc.id, v_job.organization_id;
    return;
  end if;

  if found and v_existing.status = 'running' then
    update document_extraction_runs set
      status = 'failed', failed_at = now(),
      error_code = 'superseded_by_retry', error_class = 'superseded_by_retry',
      error_message_safe = 'superseded by a later processing attempt at the same extraction identity',
      updated_at = now()
      where id = v_existing.id;
  end if;

  insert into document_extraction_runs (
    organization_id, source_document_id, processing_job_id, processing_attempt_id,
    source_sha256, source_size_bytes, pipeline_version, configuration_version,
    extractor_name, extractor_version, status, created_by_worker
  ) values (
    v_job.organization_id, v_doc.id, p_processing_job_id, v_attempt_id,
    p_source_sha256, p_source_size_bytes, p_pipeline_version, p_configuration_version,
    p_extractor_name, p_extractor_version, 'running', p_worker_instance_id
  )
  returning id into v_run_id;

  insert into document_intake_events (organization_id, source_document_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_job.organization_id, v_doc.id, p_processing_job_id, 'document_extraction.started', null, p_correlation_id,
      jsonb_build_object('extraction_run_id', v_run_id, 'worker_instance_id', p_worker_instance_id));
  insert into document_intake_events (organization_id, source_document_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_job.organization_id, v_doc.id, p_processing_job_id, 'document_extraction.source_verified', null, p_correlation_id,
      jsonb_build_object('extraction_run_id', v_run_id, 'source_sha256', p_source_sha256));

  return query select v_run_id, 'running'::text, false, v_doc.id, v_job.organization_id;
end;
$$;

revoke all on function create_document_extraction_run(uuid, text, text, text, bigint, text, text, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 5.2 finalize_document_extraction_run
-- ----------------------------------------------------------------------------
-- Called after all page rows have been inserted (via a direct service-role
-- table insert — see docs/security/pdf-extraction-security.md for why no
-- wrapper function is needed there) and the artifact has been uploaded and
-- independently re-verified. Confirms the actual persisted page count
-- matches what the Worker expects before marking anything succeeded — a
-- defense against a partial page-insert (crash mid-upload) silently being
-- accepted as a complete extraction.

create or replace function finalize_document_extraction_run(
  p_extraction_run_id uuid,
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_expected_page_count int,
  p_artifact_bucket text,
  p_artifact_path text,
  p_artifact_sha256 text,
  p_artifact_size_bytes bigint,
  p_artifact_media_type text,
  p_document_metadata jsonb default '{}'::jsonb,
  p_pages_with_text int default 0,
  p_blank_page_count int default 0,
  p_suspected_scanned_page_count int default 0,
  p_total_character_count bigint default 0,
  p_total_word_count bigint default 0,
  p_warning_count int default 0,
  p_warnings jsonb default '[]'::jsonb,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_extraction_run_id uuid, out_status text, out_completed_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_extraction_runs%rowtype;
  v_actual_page_count int;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_extraction_runs
    where organization_id = v_job.organization_id and id = p_extraction_run_id
    for update;
  if not found then
    raise exception 'extraction run not found: %', p_extraction_run_id;
  end if;
  if v_run.processing_job_id is distinct from p_processing_job_id then
    raise exception 'extraction run % does not belong to job %', p_extraction_run_id, p_processing_job_id;
  end if;

  -- Idempotent replay: already finalized with this exact artifact.
  if v_run.status = 'succeeded' then
    if v_run.artifact_sha256 is distinct from p_artifact_sha256 then
      raise exception 'extraction run % already succeeded with a different artifact checksum', p_extraction_run_id;
    end if;
    return query select v_run.id, v_run.status, v_run.completed_at;
    return;
  end if;

  -- This run may have been superseded by create_document_extraction_run()
  -- while this Worker was still mid-extraction (a real, observed race: the
  -- claim/create/insert-pages/finalize sequence is several separate
  -- auto-committed statements, not one spanning transaction, so a
  -- DIFFERENT job's attempt at the same identity can legitimately mark
  -- this run 'failed' with error_code='superseded_by_retry' in between).
  -- Rather than raise a raw "not running" error, check whether the
  -- identity already has a winner to adopt; if not, fail clearly and
  -- retryably — a later retry's create_document_extraction_run call will
  -- cleanly reuse whichever attempt eventually succeeds.
  if v_run.status = 'failed' and v_run.error_code = 'superseded_by_retry' then
    declare
      v_winner document_extraction_runs%rowtype;
    begin
      select * into v_winner from document_extraction_runs
        where organization_id = v_job.organization_id
          and source_sha256 = v_run.source_sha256
          and pipeline_version = v_run.pipeline_version
          and configuration_version = v_run.configuration_version
          and extractor_name = v_run.extractor_name
          and extractor_version = v_run.extractor_version
          and status = 'succeeded'
        limit 1;
      if found then
        return query select v_winner.id, v_winner.status, v_winner.completed_at;
        return;
      end if;
    end;
    raise exception 'extraction run % was superseded by a later attempt at the same identity before this attempt could finalize', p_extraction_run_id;
  end if;

  if v_run.status <> 'running' then
    raise exception 'extraction run % is not running (status: %); cannot finalize', p_extraction_run_id, v_run.status;
  end if;

  select count(*) into v_actual_page_count from document_extraction_pages
    where organization_id = v_job.organization_id and extraction_run_id = p_extraction_run_id;
  if v_actual_page_count <> p_expected_page_count then
    raise exception 'page count mismatch for extraction run % (expected %, found %) — refusing to finalize a partial extraction',
      p_extraction_run_id, p_expected_page_count, v_actual_page_count;
  end if;

  begin
    update document_extraction_runs set
      status = 'succeeded',
      completed_at = now(),
      page_count = p_expected_page_count,
      pages_with_text = p_pages_with_text,
      blank_page_count = p_blank_page_count,
      suspected_scanned_page_count = p_suspected_scanned_page_count,
      total_character_count = p_total_character_count,
      total_word_count = p_total_word_count,
      warning_count = p_warning_count,
      warnings = p_warnings,
      metadata = p_document_metadata,
      artifact_bucket = p_artifact_bucket,
      artifact_path = p_artifact_path,
      artifact_sha256 = p_artifact_sha256,
      artifact_size_bytes = p_artifact_size_bytes,
      artifact_media_type = p_artifact_media_type,
      updated_at = now()
      where id = p_extraction_run_id
      returning * into v_run;
  exception
    when unique_violation then
      -- Two genuinely concurrent attempts both created a `running` row at
      -- the same identity (create_document_extraction_run only locks an
      -- *existing* row — nothing to lock the first time both callers
      -- raced in). This attempt lost the race to
      -- document_extraction_runs_one_succeeded_per_identity: the OTHER
      -- run already won and succeeded first. Rather than surface a raw
      -- constraint-violation error, gracefully mark this run
      -- `invalidated` (its artifact upload is simply orphaned — bounded,
      -- rare, harmless waste, not an unbounded accumulation) and return
      -- the winning run instead, so the caller can complete its job
      -- exactly as if it had reused that result from the start.
      update document_extraction_runs set
        status = 'invalidated', updated_at = now(),
        error_code = 'superseded_by_concurrent_success',
        error_class = 'superseded_by_concurrent_success',
        error_message_safe = 'a concurrent extraction attempt at the same identity succeeded first'
        where id = p_extraction_run_id;

      -- v_run still holds the pre-failed-update row (its identity columns
      -- are immutable and untouched by the rolled-back UPDATE above), so
      -- its own source_sha256/pipeline_version/etc. are exactly what the
      -- winning row must match.
      select * into v_run from document_extraction_runs
        where organization_id = v_job.organization_id
          and source_sha256 = v_run.source_sha256
          and pipeline_version = v_run.pipeline_version
          and configuration_version = v_run.configuration_version
          and extractor_name = v_run.extractor_name
          and extractor_version = v_run.extractor_version
          and status = 'succeeded'
        limit 1;

      return query select v_run.id, v_run.status, v_run.completed_at;
      return;
  end;

  insert into document_intake_events (organization_id, source_document_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_run.organization_id, v_run.source_document_id, p_processing_job_id, 'document_extraction.artifact_created', null, p_correlation_id,
      jsonb_build_object('extraction_run_id', v_run.id, 'artifact_sha256', p_artifact_sha256, 'artifact_size_bytes', p_artifact_size_bytes));
  insert into document_intake_events (organization_id, source_document_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_run.organization_id, v_run.source_document_id, p_processing_job_id, 'document_extraction.succeeded', null, p_correlation_id,
      jsonb_build_object('extraction_run_id', v_run.id, 'page_count', p_expected_page_count, 'warning_count', p_warning_count));

  return query select v_run.id, v_run.status, v_run.completed_at;
end;
$$;

revoke all on function finalize_document_extraction_run(uuid, uuid, text, text, int, text, text, text, bigint, text, jsonb, int, int, int, bigint, bigint, int, jsonb, uuid) from public;

-- ----------------------------------------------------------------------------
-- 5.3 fail_document_extraction_run
-- ----------------------------------------------------------------------------
-- Marks the extraction run itself failed. Does NOT touch
-- document_processing_jobs — the Worker separately calls the existing,
-- unchanged fail_document_processing_job() (migration 0007) with the same
-- error classification to drive retry/dead-letter behavior at the job
-- level. Keeping these concerns separate avoids duplicating retry policy
-- inside a new function.

create or replace function fail_document_extraction_run(
  p_extraction_run_id uuid,
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_error_code text,
  p_error_class text,
  p_error_message_safe text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_extraction_run_id uuid, out_status text)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_extraction_runs%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_extraction_runs
    where organization_id = v_job.organization_id and id = p_extraction_run_id
    for update;
  if not found then
    raise exception 'extraction run not found: %', p_extraction_run_id;
  end if;

  -- Idempotent: already terminal (failed, or a prior finalize won a race).
  if v_run.status in ('failed', 'succeeded', 'invalidated') then
    return query select v_run.id, v_run.status;
    return;
  end if;

  update document_extraction_runs set
    status = 'failed',
    failed_at = now(),
    error_code = p_error_code,
    error_class = p_error_class,
    error_message_safe = p_error_message_safe,
    updated_at = now()
    where id = p_extraction_run_id
    returning * into v_run;

  insert into document_intake_events (organization_id, source_document_id, processing_job_id, event_type, actor_id, correlation_id, metadata)
    values (v_run.organization_id, v_run.source_document_id, p_processing_job_id, 'document_extraction.failed', null, p_correlation_id,
      jsonb_build_object('extraction_run_id', v_run.id, 'error_code', p_error_code, 'error_class', p_error_class));

  return query select v_run.id, v_run.status;
end;
$$;

revoke all on function fail_document_extraction_run(uuid, uuid, text, text, text, text, text, uuid) from public;

-- ============================================================================
-- 6. GRANTS — explicit revoke from `authenticated`/`anon` on all three new
-- Worker-only functions, guarded independently exactly as
-- 0007's post-hosted-verification fix does (local Postgres has an
-- `authenticated` role for RLS test purposes but no `anon` role at all —
-- see supabase/tests/rls/007_security_hardening_review.sql).
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke execute on function
      create_document_extraction_run(uuid, text, text, text, bigint, text, text, text, text, uuid),
      finalize_document_extraction_run(uuid, uuid, text, text, int, text, text, text, bigint, text, jsonb, int, int, int, bigint, bigint, int, jsonb, uuid),
      fail_document_extraction_run(uuid, uuid, text, text, text, text, text, uuid)
      from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke execute on function
      create_document_extraction_run(uuid, text, text, text, bigint, text, text, text, text, uuid),
      finalize_document_extraction_run(uuid, uuid, text, text, int, text, text, text, bigint, text, jsonb, int, int, int, bigint, bigint, int, jsonb, uuid),
      fail_document_extraction_run(uuid, uuid, text, text, text, text, text, uuid)
      from anon;
  end if;
end
$$;

-- ============================================================================
-- End of migration 0008
-- ============================================================================
