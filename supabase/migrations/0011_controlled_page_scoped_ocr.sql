-- ============================================================================
-- Noor V1 — Migration 0011: Controlled Page-Scoped OCR
-- Council: OCR Architecture Agent + PDF Rendering Agent + Database Agent +
--          Clinical Safety Agent + Security Agent
-- ============================================================================
-- Sprint 1-D2. OCR is page-scoped: only pages an extraction review
-- explicitly marked `ocr_candidate` ever become OCR-eligible. Execution
-- (document_ocr_requests/request_pages/runs) is kept separate from human
-- technical review (document_ocr_reviews/page_reviews/findings) — the same
-- execution/review boundary ADR 0011 established for extraction, one layer
-- deeper. Native extraction text is never overwritten; OCR is a wholly
-- separate, independently-provenanced representation. See ADR 0012.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. EXTEND document_processing_jobs for job_type = 'document_ocr'
-- ----------------------------------------------------------------------------
-- One durable job per OCR-eligible page (mission §11) — document_parsing's
-- existing "one active job per document" constraint does not fit OCR, which
-- needs many simultaneously-active jobs (one per page) for the same
-- document. Adds a nullable page-linking column and a page-scoped
-- uniqueness rule alongside (not replacing) document_parsing's original
-- document-scoped rule.

alter table document_processing_jobs
  drop constraint if exists document_processing_jobs_job_type_check;
alter table document_processing_jobs
  add constraint document_processing_jobs_job_type_check
  check (job_type in ('document_parsing', 'document_ocr'));

alter table document_processing_jobs
  add column if not exists ocr_request_page_id uuid;

drop index if exists document_processing_jobs_one_active_per_document_type;

-- document_parsing keeps its original document-scoped rule.
create unique index if not exists document_processing_jobs_one_active_parsing_per_document
  on document_processing_jobs (source_document_id, job_type)
  where job_type = 'document_parsing' and status in ('queued', 'claimed', 'processing');

-- document_ocr is scoped per page instead — many pages of the same document
-- may be actively processing at once, but never two active jobs for the
-- SAME page.
create unique index if not exists document_processing_jobs_one_active_ocr_per_page
  on document_processing_jobs (source_document_id, ocr_request_page_id)
  where job_type = 'document_ocr' and status in ('queued', 'claimed', 'processing');

-- ----------------------------------------------------------------------------
-- 2. TABLE — document_ocr_requests
-- ----------------------------------------------------------------------------

create table if not exists document_ocr_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  source_document_id uuid not null,
  extraction_run_id uuid not null,
  extraction_review_id uuid not null,
  review_round int not null,

  status text not null default 'created'
    check (status in (
      'created', 'queued', 'processing', 'awaiting_review',
      'accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected',
      'cancelled', 'invalidated'
    )),

  provider_name text not null,
  provider_version text not null,
  model_identifier text not null,
  model_version text not null,
  renderer_name text not null,
  renderer_version text not null,
  render_configuration_version text not null,
  ocr_configuration_version text not null,
  language_hints text[] not null,

  requested_by uuid references auth.users(id),
  requested_at timestamptz not null default now(),
  cancelled_by uuid references auth.users(id),
  cancelled_at timestamptz,
  cancellation_reason text,

  completed_at timestamptz,
  invalidated_at timestamptz,
  invalidation_reason text,

  total_pages int not null default 0,

  correlation_id uuid not null,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id)
);

alter table document_ocr_requests
  add constraint document_ocr_requests_organization_id_source_document_fkey
  foreign key (organization_id, source_document_id) references guideline_source_documents(organization_id, id);
alter table document_ocr_requests
  add constraint document_ocr_requests_organization_id_extraction_run_fkey
  foreign key (organization_id, extraction_run_id) references document_extraction_runs(organization_id, id);
alter table document_ocr_requests
  add constraint document_ocr_requests_organization_id_extraction_review_fkey
  foreign key (organization_id, extraction_review_id) references document_extraction_reviews(organization_id, id);

-- One non-cancelled/non-invalidated OCR request per extraction review round
-- — a cancelled or invalidated request may legitimately be superseded by a
-- fresh one for the same review round.
create unique index if not exists document_ocr_requests_one_active_per_review
  on document_ocr_requests (organization_id, extraction_review_id)
  where status not in ('cancelled', 'invalidated');

create index if not exists idx_ocr_requests_run on document_ocr_requests (organization_id, extraction_run_id);
create index if not exists idx_ocr_requests_status on document_ocr_requests (status);

comment on table document_ocr_requests is
  'One row per OCR request, created from an ocr_required extraction review. Aggregate/governance status — Worker execution state lives in document_processing_jobs. See docs/domain/ocr-eligibility-and-lifecycle.md.';

-- ----------------------------------------------------------------------------
-- 3. TABLE — document_ocr_request_pages
-- ----------------------------------------------------------------------------

create table if not exists document_ocr_request_pages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  ocr_request_id uuid not null,
  source_document_id uuid not null,
  extraction_run_id uuid not null,
  extraction_page_id uuid not null,
  page_number int not null check (page_number >= 1),

  -- Exact evidence that authorized this page for OCR — never an arbitrary
  -- browser-supplied page number (mission §9/§12.2).
  eligibility_source_type text not null
    check (eligibility_source_type in ('page_review_ocr_candidate')),
  eligibility_source_id uuid not null,
  eligibility_reason text,

  processing_job_id uuid,

  status text not null default 'pending'
    check (status in (
      'pending', 'queued', 'processing', 'succeeded', 'failed', 'awaiting_review',
      'accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected',
      'cancelled', 'invalidated'
    )),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (ocr_request_id, page_number)
);

alter table document_ocr_request_pages
  add constraint document_ocr_request_pages_organization_id_request_fkey
  foreign key (organization_id, ocr_request_id) references document_ocr_requests(organization_id, id);
alter table document_ocr_request_pages
  add constraint document_ocr_request_pages_organization_id_extraction_run_fkey
  foreign key (organization_id, extraction_run_id) references document_extraction_runs(organization_id, id);
alter table document_ocr_request_pages
  add constraint document_ocr_request_pages_organization_id_page_fkey
  foreign key (organization_id, extraction_page_id) references document_extraction_pages(organization_id, id);
alter table document_ocr_request_pages
  add constraint document_ocr_request_pages_organization_id_job_fkey
  foreign key (organization_id, processing_job_id) references document_processing_jobs(organization_id, id);
alter table document_ocr_request_pages
  add constraint document_ocr_request_pages_organization_id_eligibility_fkey
  foreign key (organization_id, eligibility_source_id) references document_extraction_page_reviews(organization_id, id);

-- Now that document_ocr_request_pages exists, wire the FK from
-- document_processing_jobs.ocr_request_page_id added in section 1.
alter table document_processing_jobs
  add constraint document_processing_jobs_organization_id_ocr_page_fkey
  foreign key (organization_id, ocr_request_page_id) references document_ocr_request_pages(organization_id, id);

create index if not exists idx_ocr_request_pages_request on document_ocr_request_pages (organization_id, ocr_request_id);

comment on table document_ocr_request_pages is
  'One row per OCR-eligible page within one request. eligibility_source_id always points at the exact document_extraction_page_reviews row (review_status=ocr_candidate) that authorized this page — never client-supplied.';

-- ----------------------------------------------------------------------------
-- 4. TABLE — document_ocr_runs
-- ----------------------------------------------------------------------------
-- One row per OCR execution identity/attempt — mirrors
-- document_extraction_runs one layer deeper (pins the rendering step too,
-- since OCR input is a rendered image, not the PDF bytes directly).

create table if not exists document_ocr_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  ocr_request_id uuid not null,
  ocr_request_page_id uuid not null,
  processing_job_id uuid not null,
  processing_attempt_id uuid,

  source_document_id uuid not null,
  source_sha256 text not null,
  extraction_run_id uuid not null,
  source_page_number int not null,
  native_page_checksum text not null,

  renderer_name text not null,
  renderer_version text not null,
  render_configuration_version text not null,
  render_dpi int not null,
  render_color_mode text not null,
  render_image_format text not null,
  page_image_sha256 text not null,
  page_image_size_bytes bigint not null,

  provider_name text not null,
  provider_version text not null,
  model_identifier text not null,
  model_version text not null,
  ocr_configuration_version text not null,
  language_hints text[] not null,

  status text not null default 'running'
    check (status in ('running', 'succeeded', 'failed', 'invalidated', 'reused')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,

  raw_text text,
  normalized_text text,
  character_count int not null default 0,
  word_count int not null default 0,
  text_checksum text,

  confidence_summary jsonb not null default '{}'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  provider_metadata_safe jsonb not null default '{}'::jsonb,

  error_code text,
  error_class text,
  error_message_safe text,

  artifact_bucket text,
  artifact_path text,
  artifact_sha256 text,
  artifact_size_bytes bigint,
  artifact_media_type text,

  created_at timestamptz not null default now(),
  created_by_worker text,

  unique (organization_id, id)
);

alter table document_ocr_runs
  add constraint document_ocr_runs_organization_id_request_fkey
  foreign key (organization_id, ocr_request_id) references document_ocr_requests(organization_id, id);
alter table document_ocr_runs
  add constraint document_ocr_runs_organization_id_request_page_fkey
  foreign key (organization_id, ocr_request_page_id) references document_ocr_request_pages(organization_id, id);
alter table document_ocr_runs
  add constraint document_ocr_runs_organization_id_job_fkey
  foreign key (organization_id, processing_job_id) references document_processing_jobs(organization_id, id);
alter table document_ocr_runs
  add constraint document_ocr_runs_organization_id_extraction_run_fkey
  foreign key (organization_id, extraction_run_id) references document_extraction_runs(organization_id, id);

-- Deterministic OCR identity (mission §17): at most one SUCCEEDED run per
-- full identity. Running/failed rows are excluded — multiple failed
-- attempts at the same identity are normal (retries).
create unique index if not exists document_ocr_runs_one_succeeded_per_identity
  on document_ocr_runs (
    organization_id, source_sha256, extraction_run_id, source_page_number, native_page_checksum,
    renderer_name, renderer_version, render_configuration_version, page_image_sha256,
    provider_name, provider_version, model_identifier, model_version, ocr_configuration_version, language_hints
  )
  where status = 'succeeded';

create index if not exists idx_ocr_runs_request_page on document_ocr_runs (organization_id, ocr_request_page_id);
create index if not exists idx_ocr_runs_status on document_ocr_runs (status);

comment on table document_ocr_runs is
  'One row per OCR execution attempt. Successful runs are immutable (provenance/artifact identity frozen by trigger). See docs/database/controlled-ocr-schema.md.';

create or replace function prevent_succeeded_ocr_run_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'succeeded' then
    if new.source_sha256 is distinct from old.source_sha256
       or new.native_page_checksum is distinct from old.native_page_checksum
       or new.page_image_sha256 is distinct from old.page_image_sha256
       or new.renderer_name is distinct from old.renderer_name
       or new.renderer_version is distinct from old.renderer_version
       or new.render_configuration_version is distinct from old.render_configuration_version
       or new.provider_name is distinct from old.provider_name
       or new.provider_version is distinct from old.provider_version
       or new.model_identifier is distinct from old.model_identifier
       or new.model_version is distinct from old.model_version
       or new.ocr_configuration_version is distinct from old.ocr_configuration_version
       or new.text_checksum is distinct from old.text_checksum
       or new.artifact_sha256 is distinct from old.artifact_sha256
       or new.artifact_path is distinct from old.artifact_path
    then
      raise exception 'a succeeded OCR run''s provenance, page-image, and artifact identity cannot be changed'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_succeeded_ocr_run_mutation on document_ocr_runs;
create trigger trg_prevent_succeeded_ocr_run_mutation
  before update on document_ocr_runs
  for each row execute function prevent_succeeded_ocr_run_mutation();

-- ----------------------------------------------------------------------------
-- 5. TABLE — document_ocr_reviews (mirrors document_extraction_reviews)
-- ----------------------------------------------------------------------------

create table if not exists document_ocr_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  ocr_request_id uuid not null,

  review_round int not null default 1,
  review_status text not null default 'pending_review'
    check (review_status in (
      'pending_review', 'in_review', 'accepted', 'accepted_with_warnings',
      'reprocessing_required', 'rejected', 'invalidated'
    )),

  assigned_reviewer_id uuid references auth.users(id),
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz,
  started_by uuid references auth.users(id),
  started_at timestamptz,
  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,

  overall_comments text,
  warning_summary text,
  decision_reason text,

  critical_finding_count int not null default 0,
  major_finding_count int not null default 0,
  minor_finding_count int not null default 0,
  informational_finding_count int not null default 0,

  pages_reviewed int not null default 0,
  total_pages int not null default 0,
  all_pages_reviewed boolean not null default false,

  supersedes_review_id uuid,
  reopened_from_review_id uuid,
  reopen_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),

  unique (organization_id, id)
);

alter table document_ocr_reviews
  add constraint document_ocr_reviews_organization_id_request_fkey
  foreign key (organization_id, ocr_request_id) references document_ocr_requests(organization_id, id);
alter table document_ocr_reviews
  add constraint document_ocr_reviews_organization_id_reopened_from_fkey
  foreign key (organization_id, reopened_from_review_id) references document_ocr_reviews(organization_id, id);

create unique index if not exists document_ocr_reviews_one_active_per_request
  on document_ocr_reviews (organization_id, ocr_request_id)
  where review_status in ('pending_review', 'in_review');

create index if not exists idx_ocr_reviews_request on document_ocr_reviews (organization_id, ocr_request_id, review_round desc);

comment on table document_ocr_reviews is
  'One row per OCR technical review round. Note: ocr_required is deliberately NOT a valid review_status here — an OCR review only ever decides accepted/accepted_with_warnings/reprocessing_required/rejected (mission §31).';

create or replace function prevent_terminal_ocr_review_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.review_status in ('accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected', 'invalidated') then
    if new.review_status = old.review_status then
      raise exception 'a submitted OCR review round is immutable; reopen it to create a new round'
        using errcode = '42501';
    end if;
    if not (old.review_status in ('accepted', 'accepted_with_warnings') and new.review_status = 'invalidated') then
      raise exception 'illegal OCR review transition: % -> %', old.review_status, new.review_status
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_terminal_ocr_review_mutation on document_ocr_reviews;
create trigger trg_prevent_terminal_ocr_review_mutation
  before update on document_ocr_reviews
  for each row execute function prevent_terminal_ocr_review_mutation();

-- ----------------------------------------------------------------------------
-- 6. TABLE — document_ocr_page_reviews
-- ----------------------------------------------------------------------------

create table if not exists document_ocr_page_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  ocr_review_id uuid not null,
  ocr_request_page_id uuid not null,
  ocr_run_id uuid,
  page_number int not null check (page_number >= 1),

  review_status text not null default 'unreviewed'
    check (review_status in ('unreviewed', 'accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (ocr_review_id, page_number)
);

alter table document_ocr_page_reviews
  add constraint document_ocr_page_reviews_organization_id_review_fkey
  foreign key (organization_id, ocr_review_id) references document_ocr_reviews(organization_id, id);
alter table document_ocr_page_reviews
  add constraint document_ocr_page_reviews_organization_id_request_page_fkey
  foreign key (organization_id, ocr_request_page_id) references document_ocr_request_pages(organization_id, id);
alter table document_ocr_page_reviews
  add constraint document_ocr_page_reviews_organization_id_run_fkey
  foreign key (organization_id, ocr_run_id) references document_ocr_runs(organization_id, id);

create index if not exists idx_ocr_page_reviews_review on document_ocr_page_reviews (organization_id, ocr_review_id);

create or replace function prevent_ocr_page_review_mutation_after_submission()
returns trigger
language plpgsql
as $$
declare
  v_review_status text;
begin
  select review_status into v_review_status from document_ocr_reviews where id = old.ocr_review_id;
  if v_review_status in ('accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected', 'invalidated') then
    raise exception 'OCR page review records are frozen once the parent review round is submitted' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_ocr_page_review_mutation_after_submission on document_ocr_page_reviews;
create trigger trg_prevent_ocr_page_review_mutation_after_submission
  before update on document_ocr_page_reviews
  for each row execute function prevent_ocr_page_review_mutation_after_submission();

-- ----------------------------------------------------------------------------
-- 7. TABLE — document_ocr_findings
-- ----------------------------------------------------------------------------

create table if not exists document_ocr_findings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  ocr_review_id uuid not null,
  ocr_request_page_id uuid not null,
  ocr_run_id uuid,
  page_number int not null,

  finding_type text not null check (finding_type in (
    'missing_text', 'partial_text', 'incorrect_reading_order', 'garbled_characters',
    'arabic_recognition_issue', 'english_recognition_issue', 'mixed_language_issue',
    'punctuation_loss', 'number_recognition_issue', 'table_structure_loss',
    'header_footer_noise', 'duplicate_text', 'low_confidence', 'page_segmentation_issue',
    'rotation_issue', 'unexpected_content', 'provider_error', 'other'
  )),
  severity text not null check (severity in ('informational', 'minor', 'major', 'critical')),
  status text not null default 'open'
    check (status in ('open', 'acknowledged', 'resolved', 'accepted_risk', 'dismissed')),

  title text not null,
  description text,
  suggested_action text,

  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),

  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  resolution_note text,

  unique (organization_id, id),
  check (finding_type <> 'other' or description is not null),
  check (status not in ('dismissed', 'accepted_risk') or severity not in ('major', 'critical') or resolution_note is not null)
);

alter table document_ocr_findings
  add constraint document_ocr_findings_organization_id_review_fkey
  foreign key (organization_id, ocr_review_id) references document_ocr_reviews(organization_id, id);
alter table document_ocr_findings
  add constraint document_ocr_findings_organization_id_request_page_fkey
  foreign key (organization_id, ocr_request_page_id) references document_ocr_request_pages(organization_id, id);
alter table document_ocr_findings
  add constraint document_ocr_findings_organization_id_run_fkey
  foreign key (organization_id, ocr_run_id) references document_ocr_runs(organization_id, id);

create index if not exists idx_ocr_findings_review on document_ocr_findings (organization_id, ocr_review_id);
create index if not exists idx_ocr_findings_open_severity on document_ocr_findings (ocr_review_id, severity) where status = 'open';

create or replace function prevent_ocr_finding_content_mutation()
returns trigger
language plpgsql
as $$
begin
  if new.finding_type is distinct from old.finding_type
     or new.severity is distinct from old.severity
     or new.title is distinct from old.title
     or new.description is distinct from old.description
     or new.suggested_action is distinct from old.suggested_action
     or new.ocr_request_page_id is distinct from old.ocr_request_page_id
     or new.created_by is distinct from old.created_by
  then
    raise exception 'an OCR finding''s core content is immutable once created; create a new finding instead'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_ocr_finding_content_mutation on document_ocr_findings;
create trigger trg_prevent_ocr_finding_content_mutation
  before update on document_ocr_findings
  for each row execute function prevent_ocr_finding_content_mutation();

revoke delete on document_ocr_findings from public;

-- Learned from Sprint 1-D1 (found only while cleaning up hosted test data):
-- the maintenance-override GUC is included from the very first version this
-- time, not added as a follow-up fix.
create or replace function prevent_ocr_finding_delete()
returns trigger
language plpgsql
as $$
begin
  if coalesce(current_setting('noor.allow_audit_maintenance', true), 'false') = 'true' then
    return old;
  end if;
  raise exception 'OCR findings cannot be deleted; resolve, dismiss, or accept the risk instead. '
    'See docs/database/schema.md for the documented maintenance override procedure.'
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_prevent_ocr_finding_delete on document_ocr_findings;
create trigger trg_prevent_ocr_finding_delete
  before delete on document_ocr_findings
  for each row execute function prevent_ocr_finding_delete();

-- ============================================================================
-- 8. PERMISSIONS
-- ============================================================================

insert into permissions (key, description) values
  ('guideline_ocr.read', 'Read OCR requests, page executions, runs, reviews, and findings'),
  ('guideline_ocr.create', 'Create an OCR request from an ocr_required extraction review'),
  ('guideline_ocr.cancel', 'Cancel an eligible OCR request or page job'),
  ('guideline_ocr.review', 'Start an OCR review, mark pages reviewed, and create findings'),
  ('guideline_ocr.submit_review', 'Submit a final OCR technical review decision'),
  ('guideline_ocr.reopen_review', 'Reopen a submitted OCR review as a new round'),
  ('guideline_ocr.read_artifacts', 'Read OCR artifact checksum/path metadata'),
  ('guideline_ocr.read_source', 'Obtain short-lived signed read access to the original source PDF for OCR review'),
  ('guideline_ocr.reprocess', 'Request controlled OCR reprocessing at a new identity')
on conflict (key) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where (r.key, p.key) in (
  ('organization_admin', 'guideline_ocr.read'),
  ('organization_admin', 'guideline_ocr.create'),
  ('organization_admin', 'guideline_ocr.cancel'),
  ('organization_admin', 'guideline_ocr.reopen_review'),
  ('organization_admin', 'guideline_ocr.read_source'),

  ('quality_manager', 'guideline_ocr.read'),
  ('quality_manager', 'guideline_ocr.create'),
  ('quality_manager', 'guideline_ocr.cancel'),
  ('quality_manager', 'guideline_ocr.review'),
  ('quality_manager', 'guideline_ocr.submit_review'),
  ('quality_manager', 'guideline_ocr.reopen_review'),
  ('quality_manager', 'guideline_ocr.read_artifacts'),
  ('quality_manager', 'guideline_ocr.read_source'),
  ('quality_manager', 'guideline_ocr.reprocess'),

  ('clinical_reviewer', 'guideline_ocr.read'),
  ('clinical_reviewer', 'guideline_ocr.review'),
  ('clinical_reviewer', 'guideline_ocr.submit_review'),
  ('clinical_reviewer', 'guideline_ocr.read_source'),

  ('safety_officer', 'guideline_ocr.read'),
  ('auditor', 'guideline_ocr.read')
)
on conflict do nothing;

-- Clinicians hold none of these permissions, by design.

-- ============================================================================
-- 9. RLS
-- ============================================================================

alter table document_ocr_requests enable row level security;
alter table document_ocr_request_pages enable row level security;
alter table document_ocr_runs enable row level security;
alter table document_ocr_reviews enable row level security;
alter table document_ocr_page_reviews enable row level security;
alter table document_ocr_findings enable row level security;

drop policy if exists document_ocr_requests_select on document_ocr_requests;
create policy document_ocr_requests_select on document_ocr_requests
  for select using (has_permission_in_organization(organization_id, 'guideline_ocr.read'));

drop policy if exists document_ocr_request_pages_select on document_ocr_request_pages;
create policy document_ocr_request_pages_select on document_ocr_request_pages
  for select using (has_permission_in_organization(organization_id, 'guideline_ocr.read'));

drop policy if exists document_ocr_runs_select on document_ocr_runs;
create policy document_ocr_runs_select on document_ocr_runs
  for select using (has_permission_in_organization(organization_id, 'guideline_ocr.read'));

drop policy if exists document_ocr_reviews_select on document_ocr_reviews;
create policy document_ocr_reviews_select on document_ocr_reviews
  for select using (has_permission_in_organization(organization_id, 'guideline_ocr.read'));

drop policy if exists document_ocr_page_reviews_select on document_ocr_page_reviews;
create policy document_ocr_page_reviews_select on document_ocr_page_reviews
  for select using (has_permission_in_organization(organization_id, 'guideline_ocr.read'));

drop policy if exists document_ocr_findings_select on document_ocr_findings;
create policy document_ocr_findings_select on document_ocr_findings
  for select using (has_permission_in_organization(organization_id, 'guideline_ocr.read'));

-- No INSERT/UPDATE/DELETE policy exists for `authenticated` on any of these
-- six tables — every write happens through the SECURITY DEFINER functions
-- below.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on document_ocr_requests, document_ocr_request_pages, document_ocr_runs,
      document_ocr_reviews, document_ocr_page_reviews, document_ocr_findings
      to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 10. FUNCTIONS — client-facing (SECURITY DEFINER, granted at the end)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 10.1 create_document_ocr_request
-- ----------------------------------------------------------------------------
-- Idempotent: an existing non-cancelled/non-invalidated request for the same
-- extraction_review_id is returned rather than duplicated.

create or replace function create_document_ocr_request(
  p_extraction_review_id uuid,
  p_provider_name text,
  p_provider_version text,
  p_model_identifier text,
  p_model_version text,
  p_renderer_name text,
  p_renderer_version text,
  p_render_configuration_version text,
  p_ocr_configuration_version text,
  p_language_hints text[],
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_requests
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_extraction_reviews%rowtype;
  v_run document_extraction_runs%rowtype;
  v_existing document_ocr_requests%rowtype;
  v_request document_ocr_requests%rowtype;
  v_page_count int;
  v_page record;
  v_job_id uuid;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_extraction_reviews where id = p_extraction_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_extraction_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_ocr.create');

  if v_review.review_status <> 'ocr_required' then
    raise exception 'an OCR request can only be created from an ocr_required extraction review (current status: %)', v_review.review_status;
  end if;
  if exists (
    select 1 from document_extraction_reviews
    where organization_id = v_review.organization_id and extraction_run_id = v_review.extraction_run_id
      and review_round > v_review.review_round
  ) then
    raise exception 'this extraction review round has been superseded by a later round';
  end if;

  select * into v_run from document_extraction_runs
    where organization_id = v_review.organization_id and id = v_review.extraction_run_id;
  if v_run.status <> 'succeeded' then
    raise exception 'the underlying extraction run is no longer succeeded (status: %)', v_run.status;
  end if;

  select * into v_existing from document_ocr_requests
    where organization_id = v_review.organization_id
      and extraction_review_id = p_extraction_review_id
      and status not in ('cancelled', 'invalidated')
    limit 1;
  if found then
    return v_existing;
  end if;

  select count(*) into v_page_count from document_extraction_page_reviews
    where extraction_review_id = p_extraction_review_id and review_status = 'ocr_candidate';
  if v_page_count = 0 then
    raise exception 'no pages were marked ocr_candidate in this extraction review; nothing to request';
  end if;

  insert into document_ocr_requests (
    organization_id, source_document_id, extraction_run_id, extraction_review_id, review_round,
    status, provider_name, provider_version, model_identifier, model_version,
    renderer_name, renderer_version, render_configuration_version, ocr_configuration_version,
    language_hints, requested_by, total_pages, correlation_id
  ) values (
    v_review.organization_id, v_run.source_document_id, v_review.extraction_run_id, p_extraction_review_id, v_review.review_round,
    'queued', p_provider_name, p_provider_version, p_model_identifier, p_model_version,
    p_renderer_name, p_renderer_version, p_render_configuration_version, p_ocr_configuration_version,
    p_language_hints, v_actor, v_page_count, p_correlation_id
  )
  returning * into v_request;

  for v_page in
    select per.id as page_review_id, per.page_number, dep.id as extraction_page_id
    from document_extraction_page_reviews per
    join document_extraction_pages dep
      on dep.organization_id = per.organization_id and dep.extraction_run_id = v_review.extraction_run_id and dep.page_number = per.page_number
    where per.extraction_review_id = p_extraction_review_id and per.review_status = 'ocr_candidate'
    order by per.page_number
  loop
    insert into document_processing_jobs (
      organization_id, source_document_id, job_type, status, correlation_id, ocr_request_page_id
    ) values (
      v_review.organization_id, v_run.source_document_id, 'document_ocr', 'queued', p_correlation_id, null
    )
    returning id into v_job_id;

    insert into document_ocr_request_pages (
      organization_id, ocr_request_id, source_document_id, extraction_run_id, extraction_page_id, page_number,
      eligibility_source_type, eligibility_source_id, processing_job_id, status
    ) values (
      v_review.organization_id, v_request.id, v_run.source_document_id, v_review.extraction_run_id, v_page.extraction_page_id, v_page.page_number,
      'page_review_ocr_candidate', v_page.page_review_id, v_job_id, 'queued'
    );

    update document_processing_jobs set ocr_request_page_id = (
      select id from document_ocr_request_pages where processing_job_id = v_job_id
    ) where id = v_job_id;
  end loop;

  perform record_audit_event(v_request.organization_id, 'document_ocr_request.created', 'document_ocr_request', v_request.id, p_correlation_id,
    jsonb_build_object('extraction_review_id', p_extraction_review_id, 'page_count', v_page_count));

  return v_request;
end;
$$;

revoke all on function create_document_ocr_request(uuid, text, text, text, text, text, text, text, text, text[], uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.2 cancel_document_ocr_request
-- ----------------------------------------------------------------------------

create or replace function cancel_document_ocr_request(
  p_ocr_request_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_requests
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_request document_ocr_requests%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_request from document_ocr_requests where id = p_ocr_request_id for update;
  if not found then
    raise exception 'OCR request not found: %', p_ocr_request_id;
  end if;

  perform assert_permission(v_request.organization_id, 'guideline_ocr.cancel');

  if v_request.status in ('accepted', 'accepted_with_warnings', 'rejected', 'cancelled', 'invalidated') then
    raise exception 'this OCR request is already terminal (status: %) and cannot be cancelled', v_request.status;
  end if;

  update document_processing_jobs set status = 'cancelled', cancelled_at = now(), updated_at = now()
    where organization_id = v_request.organization_id
      and ocr_request_page_id in (select id from document_ocr_request_pages where ocr_request_id = p_ocr_request_id)
      and status in ('queued', 'claimed', 'processing');

  update document_ocr_request_pages set status = 'cancelled', updated_at = now()
    where ocr_request_id = p_ocr_request_id and status not in ('succeeded', 'failed', 'accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected');

  update document_ocr_requests set
    status = 'cancelled', cancelled_by = v_actor, cancelled_at = now(), cancellation_reason = p_reason, updated_at = now()
    where id = p_ocr_request_id
    returning * into v_request;

  perform record_audit_event(v_request.organization_id, 'document_ocr_request.cancelled', 'document_ocr_request', v_request.id, p_correlation_id,
    jsonb_build_object('reason', p_reason));

  return v_request;
end;
$$;

revoke all on function cancel_document_ocr_request(uuid, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.3 create_document_ocr_review
-- ----------------------------------------------------------------------------
-- Available once every request page has reached a terminal execution state
-- (succeeded or failed) — idempotent like create_document_extraction_review.

create or replace function create_document_ocr_review(
  p_ocr_request_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_request document_ocr_requests%rowtype;
  v_existing document_ocr_reviews%rowtype;
  v_review document_ocr_reviews%rowtype;
  v_next_round int;
  v_pending_count int;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_request from document_ocr_requests where id = p_ocr_request_id for update;
  if not found then
    raise exception 'OCR request not found: %', p_ocr_request_id;
  end if;

  perform assert_permission(v_request.organization_id, 'guideline_ocr.create');

  select count(*) into v_pending_count from document_ocr_request_pages
    where ocr_request_id = p_ocr_request_id and status not in ('succeeded', 'failed');
  if v_pending_count > 0 then
    raise exception 'all OCR page jobs must reach a terminal execution state before a review can be opened (% still pending)', v_pending_count;
  end if;

  select * into v_existing from document_ocr_reviews
    where organization_id = v_request.organization_id
      and ocr_request_id = p_ocr_request_id
      and review_status in ('pending_review', 'in_review')
    limit 1;
  if found then
    return v_existing;
  end if;

  select coalesce(max(review_round), 0) + 1 into v_next_round from document_ocr_reviews
    where organization_id = v_request.organization_id and ocr_request_id = p_ocr_request_id;

  insert into document_ocr_reviews (organization_id, ocr_request_id, review_round, review_status, total_pages, created_by)
    values (v_request.organization_id, p_ocr_request_id, v_next_round, 'pending_review', v_request.total_pages, v_actor)
    returning * into v_review;

  update document_ocr_requests set status = 'awaiting_review', updated_at = now() where id = p_ocr_request_id;

  perform record_audit_event(v_review.organization_id, 'document_ocr_review.created', 'document_ocr_review', v_review.id, p_correlation_id,
    jsonb_build_object('ocr_request_id', p_ocr_request_id, 'review_round', v_next_round));

  return v_review;
end;
$$;

revoke all on function create_document_ocr_review(uuid, uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.4 assign / claim / start OCR review — identical shape to extraction
-- review's equivalents.
-- ----------------------------------------------------------------------------

create or replace function assign_ocr_reviewer(
  p_ocr_review_id uuid,
  p_reviewer_user_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_ocr_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_ocr_reviews where id = p_ocr_review_id for update;
  if not found then
    raise exception 'OCR review not found: %', p_ocr_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_ocr.review');

  if v_review.review_status not in ('pending_review', 'in_review') then
    raise exception 'only an active OCR review round can be (re)assigned (current status: %)', v_review.review_status;
  end if;

  if not exists (
    select 1 from organization_memberships m
    join role_permissions rp on rp.role_id = m.role_id
    join permissions p on p.id = rp.permission_id
    where m.organization_id = v_review.organization_id
      and m.user_id = p_reviewer_user_id
      and m.status = 'active'
      and p.key = 'guideline_ocr.review'
  ) then
    raise exception 'reviewer % does not hold OCR review permission in this organization', p_reviewer_user_id;
  end if;

  update document_ocr_reviews set
    assigned_reviewer_id = p_reviewer_user_id, assigned_by = v_actor, assigned_at = now(), updated_at = now()
    where id = p_ocr_review_id
    returning * into v_review;

  perform record_audit_event(v_review.organization_id, 'document_ocr_review.assigned', 'document_ocr_review', v_review.id, p_correlation_id,
    jsonb_build_object('assigned_reviewer_id', p_reviewer_user_id));

  return v_review;
end;
$$;

revoke all on function assign_ocr_reviewer(uuid, uuid, uuid) from public;

create or replace function claim_ocr_review(
  p_ocr_review_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_ocr_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_ocr_reviews where id = p_ocr_review_id for update;
  if not found then
    raise exception 'OCR review not found: %', p_ocr_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_ocr.review');

  if v_review.review_status not in ('pending_review', 'in_review') then
    raise exception 'only an active OCR review round can be claimed (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is not null then
    raise exception 'this OCR review round is already assigned';
  end if;

  update document_ocr_reviews set
    assigned_reviewer_id = v_actor, assigned_by = v_actor, assigned_at = now(), updated_at = now()
    where id = p_ocr_review_id
    returning * into v_review;

  perform record_audit_event(v_review.organization_id, 'document_ocr_review.assigned', 'document_ocr_review', v_review.id, p_correlation_id,
    jsonb_build_object('assigned_reviewer_id', v_actor, 'self_claimed', true));

  return v_review;
end;
$$;

revoke all on function claim_ocr_review(uuid, uuid) from public;

create or replace function start_document_ocr_review(
  p_ocr_review_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_ocr_reviews%rowtype;
  v_request document_ocr_requests%rowtype;
  v_doc guideline_source_documents%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_ocr_reviews where id = p_ocr_review_id for update;
  if not found then
    raise exception 'OCR review not found: %', p_ocr_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_ocr.review');

  if v_review.review_status <> 'pending_review' then
    raise exception 'OCR review can only be started from pending_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is not null and v_review.assigned_reviewer_id <> v_actor then
    raise exception 'this OCR review round is assigned to a different reviewer' using errcode = '42501';
  end if;

  -- Same V1 self-review policy as start_document_extraction_review
  -- (migration 0009): whoever uploaded or registered the source document
  -- cannot also be the one who technically reviews OCR output derived
  -- from it.
  select * into v_request from document_ocr_requests
    where organization_id = v_review.organization_id and id = v_review.ocr_request_id;
  select * into v_doc from guideline_source_documents
    where organization_id = v_review.organization_id and id = v_request.source_document_id;
  if v_doc.uploaded_by = v_actor or v_doc.registered_by = v_actor then
    raise exception 'a reviewer who uploaded or registered the source document cannot review its own OCR output'
      using errcode = '42501';
  end if;

  update document_ocr_reviews set
    review_status = 'in_review',
    assigned_reviewer_id = coalesce(assigned_reviewer_id, v_actor),
    assigned_by = coalesce(assigned_by, v_actor),
    assigned_at = coalesce(assigned_at, now()),
    started_by = v_actor, started_at = now(), updated_at = now()
    where id = p_ocr_review_id
    returning * into v_review;

  perform record_audit_event(v_review.organization_id, 'document_ocr_review.started', 'document_ocr_review', v_review.id, p_correlation_id, '{}'::jsonb);

  return v_review;
end;
$$;

revoke all on function start_document_ocr_review(uuid, uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.5 mark_ocr_page_reviewed
-- ----------------------------------------------------------------------------

create or replace function mark_ocr_page_reviewed(
  p_ocr_review_id uuid,
  p_page_number int,
  p_page_review_status text,
  p_notes text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_page_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_ocr_reviews%rowtype;
  v_request_page document_ocr_request_pages%rowtype;
  v_latest_run document_ocr_runs%rowtype;
  v_page_review document_ocr_page_reviews%rowtype;
  v_pages_reviewed int;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_page_review_status not in ('accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected') then
    raise exception 'invalid OCR page review status: %', p_page_review_status;
  end if;

  select * into v_review from document_ocr_reviews where id = p_ocr_review_id for update;
  if not found then
    raise exception 'OCR review not found: %', p_ocr_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_ocr.review');

  if v_review.review_status <> 'in_review' then
    raise exception 'OCR pages can only be reviewed while the round is in_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is distinct from v_actor then
    raise exception 'only the assigned reviewer can mark OCR pages reviewed' using errcode = '42501';
  end if;

  select * into v_request_page from document_ocr_request_pages
    where organization_id = v_review.organization_id
      and ocr_request_id = v_review.ocr_request_id
      and page_number = p_page_number;
  if not found then
    raise exception 'page % is not part of this OCR request', p_page_number;
  end if;

  select * into v_latest_run from document_ocr_runs
    where ocr_request_page_id = v_request_page.id and status = 'succeeded'
    order by created_at desc limit 1;

  insert into document_ocr_page_reviews (organization_id, ocr_review_id, ocr_request_page_id, ocr_run_id, page_number, review_status, reviewed_by, reviewed_at, notes)
    values (v_review.organization_id, p_ocr_review_id, v_request_page.id, v_latest_run.id, p_page_number, p_page_review_status, v_actor, now(), p_notes)
    on conflict (ocr_review_id, page_number) do update set
      review_status = excluded.review_status, ocr_run_id = excluded.ocr_run_id,
      reviewed_by = excluded.reviewed_by, reviewed_at = excluded.reviewed_at, notes = excluded.notes, updated_at = now()
    returning * into v_page_review;

  select count(*) into v_pages_reviewed from document_ocr_page_reviews
    where ocr_review_id = p_ocr_review_id and review_status <> 'unreviewed';

  update document_ocr_reviews set
    pages_reviewed = v_pages_reviewed,
    all_pages_reviewed = (v_pages_reviewed >= total_pages and total_pages > 0),
    updated_at = now()
    where id = p_ocr_review_id;

  return v_page_review;
end;
$$;

revoke all on function mark_ocr_page_reviewed(uuid, int, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.6 create_ocr_finding / update_ocr_finding_status
-- ----------------------------------------------------------------------------

create or replace function create_ocr_finding(
  p_ocr_review_id uuid,
  p_page_number int,
  p_finding_type text,
  p_severity text,
  p_title text,
  p_description text default null,
  p_suggested_action text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_findings
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_ocr_reviews%rowtype;
  v_request_page document_ocr_request_pages%rowtype;
  v_latest_run document_ocr_runs%rowtype;
  v_finding document_ocr_findings%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_ocr_reviews where id = p_ocr_review_id for update;
  if not found then
    raise exception 'OCR review not found: %', p_ocr_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_ocr.review');

  if v_review.review_status <> 'in_review' then
    raise exception 'OCR findings can only be created while the round is in_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is distinct from v_actor then
    raise exception 'only the assigned reviewer can create OCR findings' using errcode = '42501';
  end if;

  select * into v_request_page from document_ocr_request_pages
    where organization_id = v_review.organization_id and ocr_request_id = v_review.ocr_request_id and page_number = p_page_number;
  if not found then
    raise exception 'page % is not part of this OCR request', p_page_number;
  end if;

  select * into v_latest_run from document_ocr_runs
    where ocr_request_page_id = v_request_page.id order by created_at desc limit 1;

  insert into document_ocr_findings (
    organization_id, ocr_review_id, ocr_request_page_id, ocr_run_id, page_number,
    finding_type, severity, title, description, suggested_action, created_by
  ) values (
    v_review.organization_id, p_ocr_review_id, v_request_page.id, v_latest_run.id, p_page_number,
    p_finding_type, p_severity, p_title, p_description, p_suggested_action, v_actor
  )
  returning * into v_finding;

  update document_ocr_reviews set
    critical_finding_count = (select count(*) from document_ocr_findings where ocr_review_id = p_ocr_review_id and severity = 'critical' and status = 'open'),
    major_finding_count = (select count(*) from document_ocr_findings where ocr_review_id = p_ocr_review_id and severity = 'major' and status = 'open'),
    minor_finding_count = (select count(*) from document_ocr_findings where ocr_review_id = p_ocr_review_id and severity = 'minor' and status = 'open'),
    informational_finding_count = (select count(*) from document_ocr_findings where ocr_review_id = p_ocr_review_id and severity = 'informational' and status = 'open'),
    updated_at = now()
    where id = p_ocr_review_id;

  perform record_audit_event(v_review.organization_id, 'document_ocr_finding.created', 'document_ocr_finding', v_finding.id, p_correlation_id,
    jsonb_build_object('ocr_review_id', p_ocr_review_id, 'finding_type', p_finding_type, 'severity', p_severity, 'page_number', p_page_number));

  return v_finding;
end;
$$;

revoke all on function create_ocr_finding(uuid, int, text, text, text, text, text, uuid) from public;

create or replace function update_ocr_finding_status(
  p_finding_id uuid,
  p_status text,
  p_resolution_note text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_findings
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_finding document_ocr_findings%rowtype;
  v_review document_ocr_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_status not in ('open', 'acknowledged', 'resolved', 'accepted_risk', 'dismissed') then
    raise exception 'invalid OCR finding status: %', p_status;
  end if;

  select * into v_finding from document_ocr_findings where id = p_finding_id for update;
  if not found then
    raise exception 'OCR finding not found: %', p_finding_id;
  end if;

  perform assert_permission(v_finding.organization_id, 'guideline_ocr.review');

  select * into v_review from document_ocr_reviews where id = v_finding.ocr_review_id;
  if v_review.review_status <> 'in_review' then
    raise exception 'OCR findings can only be updated while the review round is in_review (current status: %)', v_review.review_status;
  end if;

  if p_status in ('dismissed', 'accepted_risk') and v_finding.severity in ('major', 'critical') and (p_resolution_note is null or length(trim(p_resolution_note)) = 0) then
    raise exception 'dismissing or accepting the risk of a % OCR finding requires a resolution note', v_finding.severity;
  end if;

  update document_ocr_findings set
    status = p_status,
    resolved_by = case when p_status in ('resolved', 'dismissed', 'accepted_risk') then v_actor else null end,
    resolved_at = case when p_status in ('resolved', 'dismissed', 'accepted_risk') then now() else null end,
    resolution_note = p_resolution_note
    where id = p_finding_id
    returning * into v_finding;

  update document_ocr_reviews set
    critical_finding_count = (select count(*) from document_ocr_findings where ocr_review_id = v_finding.ocr_review_id and severity = 'critical' and status = 'open'),
    major_finding_count = (select count(*) from document_ocr_findings where ocr_review_id = v_finding.ocr_review_id and severity = 'major' and status = 'open'),
    minor_finding_count = (select count(*) from document_ocr_findings where ocr_review_id = v_finding.ocr_review_id and severity = 'minor' and status = 'open'),
    informational_finding_count = (select count(*) from document_ocr_findings where ocr_review_id = v_finding.ocr_review_id and severity = 'informational' and status = 'open'),
    updated_at = now()
    where id = v_finding.ocr_review_id;

  perform record_audit_event(v_finding.organization_id, 'document_ocr_finding.resolved', 'document_ocr_finding', v_finding.id, p_correlation_id,
    jsonb_build_object('status', p_status));

  return v_finding;
end;
$$;

revoke all on function update_ocr_finding_status(uuid, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.7 submit_document_ocr_review
-- ----------------------------------------------------------------------------
-- ocr_required is deliberately not a valid target (mission §31).

create or replace function submit_document_ocr_review(
  p_ocr_review_id uuid,
  p_target_status text,
  p_decision_reason text default null,
  p_warning_summary text default null,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_ocr_reviews%rowtype;
  v_request document_ocr_requests%rowtype;
  v_open_critical int;
  v_open_major int;
  v_any_findings int;
  v_can_override boolean;
  v_all_succeeded boolean;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_target_status not in ('accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected') then
    raise exception 'invalid target OCR review status: %', p_target_status;
  end if;

  select * into v_review from document_ocr_reviews where id = p_ocr_review_id for update;
  if not found then
    raise exception 'OCR review not found: %', p_ocr_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_ocr.submit_review');

  if v_review.review_status = p_target_status
     and p_idempotency_key is not null
     and (v_review.decision_reason is not distinct from p_decision_reason)
  then
    return v_review;
  end if;

  v_can_override := has_permission_in_organization(v_review.organization_id, 'guideline_ocr.reopen_review');
  if v_review.assigned_reviewer_id is distinct from v_actor and not v_can_override then
    raise exception 'only the assigned reviewer (or an authorized quality/admin override) can submit this OCR review' using errcode = '42501';
  end if;

  if v_review.review_status <> 'in_review' then
    raise exception 'an OCR review can only be submitted from in_review (current status: %)', v_review.review_status;
  end if;

  if not v_review.all_pages_reviewed or v_review.pages_reviewed < v_review.total_pages or v_review.total_pages = 0 then
    raise exception 'every OCR page must be marked reviewed before a final decision can be submitted (% of % reviewed)', v_review.pages_reviewed, v_review.total_pages;
  end if;

  select * into v_request from document_ocr_requests where id = v_review.ocr_request_id;

  -- Deliberately checked against document_ocr_runs, not
  -- document_ocr_request_pages.status: the latter is a governance rollup
  -- that this very function overwrites with the review decision a few
  -- lines below (see the update at the end of this function), so on any
  -- reopened round it would no longer read 'succeeded' even though the
  -- page's OCR execution genuinely succeeded. document_ocr_runs.status is
  -- the durable, review-independent execution record — the same
  -- execution/review separation ADR 0011 established one layer up.
  select bool_and(exists (
    select 1 from document_ocr_runs r
    where r.ocr_request_page_id = rp.id and r.status = 'succeeded'
  )) into v_all_succeeded
  from document_ocr_request_pages rp
  where rp.ocr_request_id = v_review.ocr_request_id;

  select count(*) into v_open_critical from document_ocr_findings where ocr_review_id = p_ocr_review_id and severity = 'critical' and status = 'open';
  select count(*) into v_open_major from document_ocr_findings where ocr_review_id = p_ocr_review_id and severity = 'major' and status = 'open';
  select count(*) into v_any_findings from document_ocr_findings where ocr_review_id = p_ocr_review_id;

  if p_target_status = 'accepted' then
    if not coalesce(v_all_succeeded, false) then
      raise exception 'accepted requires every requested OCR page to have succeeded';
    end if;
    if v_open_critical > 0 or v_open_major > 0 then
      raise exception 'accepted requires zero open critical or major OCR findings (open critical=%, open major=%)', v_open_critical, v_open_major;
    end if;

  elsif p_target_status = 'accepted_with_warnings' then
    if v_open_critical > 0 then
      raise exception 'accepted_with_warnings requires zero open critical OCR findings (open critical=%)', v_open_critical;
    end if;
    if p_warning_summary is null or length(trim(p_warning_summary)) = 0 then
      raise exception 'accepted_with_warnings requires a warning_summary';
    end if;

  elsif p_target_status = 'reprocessing_required' then
    if v_any_findings = 0 then
      raise exception 'reprocessing_required requires at least one supporting OCR finding';
    end if;
    if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
      raise exception 'reprocessing_required requires a decision_reason';
    end if;

  elsif p_target_status = 'rejected' then
    if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
      raise exception 'rejected requires a decision_reason';
    end if;
  end if;

  update document_ocr_reviews set
    review_status = p_target_status, submitted_by = v_actor, submitted_at = now(),
    decision_reason = p_decision_reason, warning_summary = p_warning_summary, updated_at = now()
    where id = p_ocr_review_id
    returning * into v_review;

  update document_ocr_requests set status = p_target_status, completed_at = now(), updated_at = now()
    where id = v_review.ocr_request_id;

  update document_ocr_request_pages set status = p_target_status, updated_at = now()
    where ocr_request_id = v_review.ocr_request_id and status not in ('cancelled', 'invalidated');

  perform record_audit_event(v_review.organization_id, 'document_ocr_review.' || p_target_status, 'document_ocr_review', v_review.id, p_correlation_id,
    jsonb_build_object('review_status', p_target_status, 'critical_findings', v_review.critical_finding_count, 'major_findings', v_review.major_finding_count));

  return v_review;
end;
$$;

revoke all on function submit_document_ocr_review(uuid, text, text, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.8 reopen_ocr_review / invalidate_ocr_review
-- ----------------------------------------------------------------------------

create or replace function reopen_ocr_review(
  p_ocr_review_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_old document_ocr_reviews%rowtype;
  v_new document_ocr_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reopening an OCR review requires a reason';
  end if;

  select * into v_old from document_ocr_reviews where id = p_ocr_review_id for update;
  if not found then
    raise exception 'OCR review not found: %', p_ocr_review_id;
  end if;

  perform assert_permission(v_old.organization_id, 'guideline_ocr.reopen_review');

  if v_old.review_status not in ('accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected') then
    raise exception 'only a submitted, non-invalidated OCR decision can be reopened (current status: %)', v_old.review_status;
  end if;

  insert into document_ocr_reviews (organization_id, ocr_request_id, review_round, review_status, total_pages, reopened_from_review_id, reopen_reason, created_by)
    values (v_old.organization_id, v_old.ocr_request_id, v_old.review_round + 1, 'pending_review', v_old.total_pages, v_old.id, p_reason, v_actor)
    returning * into v_new;

  update document_ocr_requests set status = 'awaiting_review', updated_at = now() where id = v_old.ocr_request_id;

  perform record_audit_event(v_new.organization_id, 'document_ocr_review.reopened', 'document_ocr_review', v_new.id, p_correlation_id,
    jsonb_build_object('reopened_from_review_id', v_old.id, 'previous_status', v_old.review_status, 'reason', p_reason));

  return v_new;
end;
$$;

revoke all on function reopen_ocr_review(uuid, text, uuid) from public;

create or replace function invalidate_ocr_review(
  p_ocr_review_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns document_ocr_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_ocr_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalidating an OCR review requires a reason';
  end if;

  select * into v_review from document_ocr_reviews where id = p_ocr_review_id for update;
  if not found then
    raise exception 'OCR review not found: %', p_ocr_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_ocr.reopen_review');

  if v_review.review_status not in ('accepted', 'accepted_with_warnings') then
    raise exception 'only an accepted or accepted_with_warnings OCR review can be invalidated (current status: %)', v_review.review_status;
  end if;

  update document_ocr_reviews set review_status = 'invalidated', decision_reason = p_reason, updated_at = now()
    where id = p_ocr_review_id
    returning * into v_review;

  update document_ocr_requests set status = 'invalidated', invalidated_at = now(), invalidation_reason = p_reason, updated_at = now()
    where id = v_review.ocr_request_id;

  perform record_audit_event(v_review.organization_id, 'document_ocr_request.invalidated', 'document_ocr_review', v_review.id, p_correlation_id,
    jsonb_build_object('reason', p_reason));

  return v_review;
end;
$$;

revoke all on function invalidate_ocr_review(uuid, text, uuid) from public;

-- ============================================================================
-- 11. WORKER-ONLY FUNCTIONS (never granted to authenticated/anon)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 11.1 create_document_ocr_run
-- ----------------------------------------------------------------------------
-- Re-verifies the claimed lease AND re-verifies page eligibility/validity as
-- a second, database-side line of defense (mirrors
-- create_document_extraction_run's own re-verification philosophy).
-- Idempotent identity reuse, same shape as extraction.

create or replace function create_document_ocr_run(
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_source_sha256 text,
  p_native_page_checksum text,
  p_renderer_name text,
  p_renderer_version text,
  p_render_configuration_version text,
  p_render_dpi int,
  p_render_color_mode text,
  p_render_image_format text,
  p_page_image_sha256 text,
  p_page_image_size_bytes bigint,
  p_provider_name text,
  p_provider_version text,
  p_model_identifier text,
  p_model_version text,
  p_ocr_configuration_version text,
  p_language_hints text[],
  p_correlation_id uuid default gen_random_uuid()
) returns table (
  out_ocr_run_id uuid,
  out_status text,
  out_reused boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_request_page document_ocr_request_pages%rowtype;
  v_request document_ocr_requests%rowtype;
  v_run document_extraction_runs%rowtype;
  v_doc guideline_source_documents%rowtype;
  v_existing document_ocr_runs%rowtype;
  v_run_id uuid;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  if v_job.job_type <> 'document_ocr' or v_job.ocr_request_page_id is null then
    raise exception 'job % is not a document_ocr page job', p_processing_job_id;
  end if;

  select * into v_request_page from document_ocr_request_pages
    where organization_id = v_job.organization_id and id = v_job.ocr_request_page_id;
  if not found then
    raise exception 'OCR request page not found for job %', p_processing_job_id;
  end if;

  select * into v_request from document_ocr_requests
    where organization_id = v_job.organization_id and id = v_request_page.ocr_request_id;
  if v_request.status in ('cancelled', 'invalidated') then
    raise exception 'this OCR request is % and no longer eligible for processing', v_request.status;
  end if;

  -- Re-verify, under lock, that the extraction review round this request
  -- was created from has not since been superseded by a later round
  -- (mission §10: reopening an extraction review must block in-flight OCR
  -- processing, not just future request creation) — mirrors the identical
  -- check create_document_ocr_request performs at creation time.
  if exists (
    select 1 from document_extraction_reviews
    where organization_id = v_job.organization_id
      and extraction_run_id = v_request.extraction_run_id
      and review_round > v_request.review_round
  ) then
    raise exception 'this OCR request''s extraction review round has been superseded and is no longer eligible for processing';
  end if;

  select * into v_run from document_extraction_runs
    where organization_id = v_job.organization_id and id = v_request_page.extraction_run_id;
  if v_run.status <> 'succeeded' then
    raise exception 'the underlying extraction run is no longer succeeded (status: %)', v_run.status;
  end if;

  select * into v_doc from guideline_source_documents
    where organization_id = v_job.organization_id and id = v_job.source_document_id;
  if v_doc.sha256 is distinct from p_source_sha256 then
    raise exception 'source checksum does not match the registered document';
  end if;

  select * into v_existing from document_ocr_runs
    where organization_id = v_job.organization_id
      and source_sha256 = p_source_sha256
      and extraction_run_id = v_request_page.extraction_run_id
      and source_page_number = v_request_page.page_number
      and native_page_checksum = p_native_page_checksum
      and renderer_name = p_renderer_name and renderer_version = p_renderer_version
      and render_configuration_version = p_render_configuration_version
      and page_image_sha256 = p_page_image_sha256
      and provider_name = p_provider_name and provider_version = p_provider_version
      and model_identifier = p_model_identifier and model_version = p_model_version
      and ocr_configuration_version = p_ocr_configuration_version
      and language_hints = p_language_hints
      and status = 'succeeded'
    limit 1;

  if found then
    -- Reused identity: the Worker (app/ocr/processor.py) deliberately never
    -- calls finalize_document_ocr_page for a reused run (there is nothing
    -- new to finalize), so this is the ONLY place that can ever mark this
    -- request page terminal. Without this, a reused page would stay
    -- 'processing' forever and create_document_ocr_review's
    -- all-pages-terminal check could never pass for it.
    update document_ocr_request_pages set status = 'succeeded', updated_at = now() where id = v_request_page.id;
    update document_ocr_requests set status = 'processing', updated_at = now() where id = v_request.id and status = 'queued';
    return query select v_existing.id, v_existing.status, true;
    return;
  end if;

  insert into document_ocr_runs (
    organization_id, ocr_request_id, ocr_request_page_id, processing_job_id,
    source_document_id, source_sha256, extraction_run_id, source_page_number, native_page_checksum,
    renderer_name, renderer_version, render_configuration_version, render_dpi, render_color_mode, render_image_format,
    page_image_sha256, page_image_size_bytes,
    provider_name, provider_version, model_identifier, model_version, ocr_configuration_version, language_hints,
    status, created_by_worker
  ) values (
    v_job.organization_id, v_request.id, v_request_page.id, p_processing_job_id,
    v_job.source_document_id, p_source_sha256, v_request_page.extraction_run_id, v_request_page.page_number, p_native_page_checksum,
    p_renderer_name, p_renderer_version, p_render_configuration_version, p_render_dpi, p_render_color_mode, p_render_image_format,
    p_page_image_sha256, p_page_image_size_bytes,
    p_provider_name, p_provider_version, p_model_identifier, p_model_version, p_ocr_configuration_version, p_language_hints,
    'running', p_worker_instance_id
  )
  returning id into v_run_id;

  update document_ocr_request_pages set status = 'processing', updated_at = now() where id = v_request_page.id;
  update document_ocr_requests set status = 'processing', updated_at = now() where id = v_request.id and status = 'queued';

  return query select v_run_id, 'running'::text, false;
end;
$$;

revoke all on function create_document_ocr_run(uuid, text, text, text, text, text, text, text, int, text, text, text, bigint, text, text, text, text, text, text[], uuid) from public;

-- ----------------------------------------------------------------------------
-- 11.2 finalize_document_ocr_page
-- ----------------------------------------------------------------------------

create or replace function finalize_document_ocr_page(
  p_ocr_run_id uuid,
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_raw_text text,
  p_normalized_text text,
  p_character_count int,
  p_word_count int,
  p_text_checksum text,
  p_confidence_summary jsonb,
  p_warnings jsonb,
  p_provider_metadata_safe jsonb,
  p_artifact_bucket text,
  p_artifact_path text,
  p_artifact_sha256 text,
  p_artifact_size_bytes bigint,
  p_artifact_media_type text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_ocr_run_id uuid, out_status text, out_completed_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_ocr_runs%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_ocr_runs
    where organization_id = v_job.organization_id and id = p_ocr_run_id
    for update;
  if not found then
    raise exception 'OCR run not found: %', p_ocr_run_id;
  end if;
  if v_run.processing_job_id is distinct from p_processing_job_id then
    raise exception 'OCR run % does not belong to job %', p_ocr_run_id, p_processing_job_id;
  end if;

  if v_run.status = 'succeeded' then
    if v_run.artifact_sha256 is distinct from p_artifact_sha256 then
      raise exception 'OCR run % already succeeded with a different artifact checksum', p_ocr_run_id;
    end if;
    return query select v_run.id, v_run.status, v_run.completed_at;
    return;
  end if;

  if v_run.status <> 'running' then
    raise exception 'OCR run % is not running (status: %); cannot finalize', p_ocr_run_id, v_run.status;
  end if;

  begin
    update document_ocr_runs set
      status = 'succeeded', completed_at = now(),
      raw_text = p_raw_text, normalized_text = p_normalized_text,
      character_count = p_character_count, word_count = p_word_count, text_checksum = p_text_checksum,
      confidence_summary = p_confidence_summary, warnings = p_warnings, provider_metadata_safe = p_provider_metadata_safe,
      artifact_bucket = p_artifact_bucket, artifact_path = p_artifact_path, artifact_sha256 = p_artifact_sha256,
      artifact_size_bytes = p_artifact_size_bytes, artifact_media_type = p_artifact_media_type
      where id = p_ocr_run_id
      returning * into v_run;
  exception
    when unique_violation then
      update document_ocr_runs set status = 'invalidated' where id = p_ocr_run_id;
      select * into v_run from document_ocr_runs
        where organization_id = v_job.organization_id
          and source_sha256 = v_run.source_sha256 and extraction_run_id = v_run.extraction_run_id
          and source_page_number = v_run.source_page_number and native_page_checksum = v_run.native_page_checksum
          and renderer_name = v_run.renderer_name and renderer_version = v_run.renderer_version
          and render_configuration_version = v_run.render_configuration_version and page_image_sha256 = v_run.page_image_sha256
          and provider_name = v_run.provider_name and provider_version = v_run.provider_version
          and model_identifier = v_run.model_identifier and model_version = v_run.model_version
          and ocr_configuration_version = v_run.ocr_configuration_version and language_hints = v_run.language_hints
          and status = 'succeeded'
        limit 1;
      return query select v_run.id, v_run.status, v_run.completed_at;
      return;
  end;

  update document_ocr_request_pages set status = 'succeeded', updated_at = now() where id = v_run.ocr_request_page_id;

  return query select v_run.id, v_run.status, v_run.completed_at;
end;
$$;

revoke all on function finalize_document_ocr_page(uuid, uuid, text, text, text, text, int, int, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 11.3 fail_document_ocr_run
-- ----------------------------------------------------------------------------

create or replace function fail_document_ocr_run(
  p_ocr_run_id uuid,
  p_processing_job_id uuid,
  p_worker_instance_id text,
  p_lease_token text,
  p_error_code text,
  p_error_class text,
  p_error_message_safe text,
  p_correlation_id uuid default gen_random_uuid()
) returns table (out_ocr_run_id uuid, out_status text)
language plpgsql security definer set search_path = public as $$
declare
  v_job document_processing_jobs%rowtype;
  v_run document_ocr_runs%rowtype;
begin
  select * into v_job from document_processing_jobs where id = p_processing_job_id for update;
  if not found then
    raise exception 'processing job not found: %', p_processing_job_id;
  end if;
  perform assert_lease_owner(v_job, p_worker_instance_id, p_lease_token);

  select * into v_run from document_ocr_runs
    where organization_id = v_job.organization_id and id = p_ocr_run_id
    for update;
  if not found then
    raise exception 'OCR run not found: %', p_ocr_run_id;
  end if;

  if v_run.status in ('failed', 'succeeded', 'invalidated') then
    return query select v_run.id, v_run.status;
    return;
  end if;

  update document_ocr_runs set
    status = 'failed', failed_at = now(), error_code = p_error_code, error_class = p_error_class, error_message_safe = p_error_message_safe
    where id = p_ocr_run_id
    returning * into v_run;

  update document_ocr_request_pages set status = 'failed', updated_at = now() where id = v_run.ocr_request_page_id;

  return query select v_run.id, v_run.status;
end;
$$;

revoke all on function fail_document_ocr_run(uuid, uuid, text, text, text, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 11.4 get_document_page_text_readiness
-- ----------------------------------------------------------------------------
-- Canonical page-text representation (mission §34). Never a physically
-- merged text column — this function is the single source of truth for
-- "which representation wins" per page, recomputed fresh every call.

create or replace function get_document_page_text_readiness(
  p_extraction_run_id uuid
) returns table (
  out_page_number int,
  out_representation_type text,
  out_representation_id uuid,
  out_text_checksum text,
  out_ready_for_chunking boolean,
  out_warning_state boolean,
  out_reason text
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_run document_extraction_runs%rowtype;
  v_review document_extraction_reviews%rowtype;
  v_ocr_request document_ocr_requests%rowtype;
  v_ocr_review document_ocr_reviews%rowtype;
begin
  select * into v_run from document_extraction_runs where id = p_extraction_run_id;
  if not found then
    raise exception 'extraction run not found: %', p_extraction_run_id;
  end if;

  perform assert_permission(v_run.organization_id, 'guideline_extractions.read');

  if v_run.status <> 'succeeded' then
    return query
      select dep.page_number, null::text, null::uuid, null::text, false, false, 'extraction_not_succeeded'::text
      from document_extraction_pages dep
      where dep.extraction_run_id = p_extraction_run_id
      order by dep.page_number;
    return;
  end if;

  select * into v_review from document_extraction_reviews
    where organization_id = v_run.organization_id and extraction_run_id = p_extraction_run_id
    order by review_round desc limit 1;

  if not found or v_review.review_status in ('pending_review', 'in_review') then
    return query
      select dep.page_number, null::text, null::uuid, null::text, false, false, 'extraction_review_not_final'::text
      from document_extraction_pages dep
      where dep.extraction_run_id = p_extraction_run_id
      order by dep.page_number;
    return;
  end if;

  if v_review.review_status in ('accepted', 'accepted_with_warnings') then
    return query
      select dep.page_number, 'native'::text, dep.id, dep.page_checksum, true,
        (v_review.review_status = 'accepted_with_warnings'), null::text
      from document_extraction_pages dep
      where dep.extraction_run_id = p_extraction_run_id
      order by dep.page_number;
    return;
  end if;

  if v_review.review_status in ('rejected', 'reprocessing_required', 'invalidated') then
    return query
      select dep.page_number, null::text, null::uuid, null::text, false, false, v_review.review_status
      from document_extraction_pages dep
      where dep.extraction_run_id = p_extraction_run_id
      order by dep.page_number;
    return;
  end if;

  -- review_status = 'ocr_required' — per-page: OCR-requested pages use the
  -- accepted OCR representation (if any); all other pages keep using native
  -- text (the reviewer did not flag them).
  select * into v_ocr_request from document_ocr_requests
    where organization_id = v_run.organization_id and extraction_review_id = v_review.id
      and status not in ('cancelled', 'invalidated')
    limit 1;

  if found then
    select * into v_ocr_review from document_ocr_reviews
      where organization_id = v_run.organization_id and ocr_request_id = v_ocr_request.id
      order by review_round desc limit 1;
  end if;

  -- Driven by the extraction review's OWN page-level decision
  -- (document_extraction_page_reviews.review_status = 'ocr_candidate'), not
  -- by whether an OCR request happens to exist yet — a page the reviewer
  -- flagged for OCR is NOT ready merely because no request was ever
  -- created (or is still in progress) for it. A page the reviewer did NOT
  -- flag keeps using its native representation regardless of what is
  -- happening to other pages' OCR work.
  return query
  select
    dep.page_number,
    case
      when per.review_status is distinct from 'ocr_candidate' then 'native'
      when opr.review_status in ('accepted', 'accepted_with_warnings') and orr.status = 'succeeded' then 'ocr'
      else null
    end,
    case
      when per.review_status is distinct from 'ocr_candidate' then dep.id
      when opr.review_status in ('accepted', 'accepted_with_warnings') and orr.status = 'succeeded' then orr.id
      else null
    end,
    case
      when per.review_status is distinct from 'ocr_candidate' then dep.page_checksum
      when opr.review_status in ('accepted', 'accepted_with_warnings') and orr.status = 'succeeded' then orr.text_checksum
      else null
    end,
    case
      when per.review_status is distinct from 'ocr_candidate' then true
      when opr.review_status in ('accepted', 'accepted_with_warnings') and orr.status = 'succeeded' then true
      else false
    end,
    case
      when per.review_status is distinct from 'ocr_candidate' then false
      when opr.review_status = 'accepted_with_warnings' and orr.status = 'succeeded' then true
      else false
    end,
    case
      when per.review_status is distinct from 'ocr_candidate' then null
      when opr.review_status in ('accepted', 'accepted_with_warnings') and orr.status = 'succeeded' then null
      when orp.id is null then 'ocr_not_yet_requested'
      when orp.status in ('pending', 'queued', 'processing') then 'ocr_pending'
      when orp.status = 'failed' then 'ocr_failed'
      when opr.review_status = 'rejected' then 'ocr_rejected'
      when opr.review_status = 'reprocessing_required' then 'ocr_reprocessing_required'
      else 'ocr_not_yet_reviewed'
    end
  from document_extraction_pages dep
  left join document_extraction_page_reviews per
    on per.extraction_review_id = v_review.id and per.page_number = dep.page_number
  left join document_ocr_request_pages orp
    on v_ocr_request.id is not null
    and orp.organization_id = dep.organization_id and orp.extraction_run_id = dep.extraction_run_id and orp.page_number = dep.page_number
    and orp.ocr_request_id = v_ocr_request.id
  left join document_ocr_page_reviews opr
    on v_ocr_review.id is not null and opr.ocr_review_id = v_ocr_review.id and opr.page_number = dep.page_number
  left join document_ocr_runs orr
    on orr.id = opr.ocr_run_id
  where dep.extraction_run_id = p_extraction_run_id
  order by dep.page_number;
end;
$$;

revoke all on function get_document_page_text_readiness(uuid) from public;

-- ----------------------------------------------------------------------------
-- 11.5 Extend get_document_extraction_review_eligibility (migration 0009) to
-- account for OCR page readiness — an ocr_required review only becomes
-- chunking-eligible once every page (OCR or native) is ready. Redefining an
-- earlier migration's function via CREATE OR REPLACE is standard forward
-- evolution (0007 already did the same to 0006's tables) — 0009's file
-- itself is never edited.
-- ----------------------------------------------------------------------------

create or replace function get_document_extraction_review_eligibility(
  p_extraction_run_id uuid
) returns table (
  out_extraction_run_id uuid,
  out_extraction_status text,
  out_latest_review_id uuid,
  out_review_status text,
  out_eligible_for_ocr boolean,
  out_eligible_for_chunking boolean,
  out_eligible_for_retrieval boolean
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_run document_extraction_runs%rowtype;
  v_latest document_extraction_reviews%rowtype;
  v_all_ready boolean;
begin
  select * into v_run from document_extraction_runs where id = p_extraction_run_id;
  if not found then
    raise exception 'extraction run not found: %', p_extraction_run_id;
  end if;

  perform assert_permission(v_run.organization_id, 'guideline_extractions.read');

  select * into v_latest from document_extraction_reviews
    where organization_id = v_run.organization_id and extraction_run_id = p_extraction_run_id
    order by review_round desc
    limit 1;

  if v_run.status <> 'succeeded' then
    return query select p_extraction_run_id, v_run.status, v_latest.id,
      v_latest.review_status, false, false, false;
    return;
  end if;

  if not found or v_latest.review_status is null then
    return query select p_extraction_run_id, v_run.status, null::uuid, null::text, false, false, false;
    return;
  end if;

  if v_latest.review_status = 'ocr_required' then
    select bool_and(out_ready_for_chunking) into v_all_ready
      from get_document_page_text_readiness(p_extraction_run_id);
    return query select p_extraction_run_id, v_run.status, v_latest.id, v_latest.review_status,
      true, coalesce(v_all_ready, false), false;
    return;
  end if;

  return query select
    p_extraction_run_id,
    v_run.status,
    v_latest.id,
    v_latest.review_status,
    false,
    (v_latest.review_status in ('accepted', 'accepted_with_warnings')),
    false;
end;
$$;

revoke all on function get_document_extraction_review_eligibility(uuid) from public;

-- ----------------------------------------------------------------------------
-- 11.6 Extend submit_document_extraction_review (migration 0009): a real
-- cross-sprint consistency gap found while testing this migration, not by
-- reading the SQL. Migration 0009's ocr_required validation only required
-- an OCR-relevant FINDING to exist — it never required any page to actually
-- be marked ocr_candidate. That made it possible to submit ocr_required
-- with zero pages create_document_ocr_request() could ever act on, and
-- get_document_page_text_readiness() would then correctly (but
-- confusingly) report every page as already native-ready, making the whole
-- document immediately chunking-eligible despite the reviewer supposedly
-- having required OCR. Fixed by additionally requiring at least one page
-- to be marked ocr_candidate — the same canonical signal
-- create_document_ocr_request() already keys off, so "ocr_required" and
-- "an OCR request can actually be created and will genuinely gate
-- eligibility" are now structurally the same fact.
-- ----------------------------------------------------------------------------

create or replace function submit_document_extraction_review(
  p_review_id uuid,
  p_target_status text,
  p_decision_reason text default null,
  p_warning_summary text default null,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_extraction_reviews%rowtype;
  v_run document_extraction_runs%rowtype;
  v_open_critical int;
  v_open_major int;
  v_ocr_candidate_pages int;
  v_any_findings int;
  v_major_or_critical_findings int;
  v_can_override boolean;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_target_status not in ('accepted', 'accepted_with_warnings', 'ocr_required', 'reprocessing_required', 'rejected') then
    raise exception 'invalid target review status: %', p_target_status;
  end if;

  select * into v_review from document_extraction_reviews where id = p_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_extraction_reviews.submit');

  if v_review.review_status = p_target_status
     and p_idempotency_key is not null
     and v_review.decision_metadata ->> 'idempotency_key' = p_idempotency_key
  then
    return v_review;
  end if;

  v_can_override := has_permission_in_organization(v_review.organization_id, 'guideline_extraction_reviews.assign');
  if v_review.assigned_reviewer_id is distinct from v_actor and not v_can_override then
    raise exception 'only the assigned reviewer (or an authorized quality/admin override) can submit this review' using errcode = '42501';
  end if;

  if v_review.review_status <> 'in_review' then
    raise exception 'a review can only be submitted from in_review (current status: %)', v_review.review_status;
  end if;

  select * into v_run from document_extraction_runs
    where organization_id = v_review.organization_id and id = v_review.extraction_run_id;
  if v_run.status <> 'succeeded' then
    raise exception 'the underlying extraction run is no longer succeeded (status: %); this review cannot be submitted', v_run.status;
  end if;

  if not v_review.all_pages_reviewed or v_review.pages_reviewed < v_review.total_pages or v_review.total_pages = 0 then
    raise exception 'every page must be marked reviewed before a final decision can be submitted (% of % reviewed)', v_review.pages_reviewed, v_review.total_pages;
  end if;

  select count(*) into v_open_critical from document_extraction_review_findings
    where extraction_review_id = p_review_id and severity = 'critical' and status = 'open';
  select count(*) into v_open_major from document_extraction_review_findings
    where extraction_review_id = p_review_id and severity = 'major' and status = 'open';
  select count(*) into v_any_findings from document_extraction_review_findings
    where extraction_review_id = p_review_id;
  select count(*) into v_major_or_critical_findings from document_extraction_review_findings
    where extraction_review_id = p_review_id and severity in ('major', 'critical');
  select count(*) into v_ocr_candidate_pages from document_extraction_page_reviews
    where extraction_review_id = p_review_id and review_status = 'ocr_candidate';

  if p_target_status = 'accepted' then
    if v_open_critical > 0 or v_open_major > 0 then
      raise exception 'accepted requires zero open critical or major findings (open critical=%, open major=%)', v_open_critical, v_open_major;
    end if;

  elsif p_target_status = 'accepted_with_warnings' then
    if v_open_critical > 0 then
      raise exception 'accepted_with_warnings requires zero open critical findings (open critical=%)', v_open_critical;
    end if;
    if p_warning_summary is null or length(trim(p_warning_summary)) = 0 then
      raise exception 'accepted_with_warnings requires a warning_summary';
    end if;

  elsif p_target_status = 'ocr_required' then
    if v_ocr_candidate_pages = 0 then
      raise exception 'ocr_required requires at least one page marked ocr_candidate';
    end if;
    if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
      raise exception 'ocr_required requires a decision_reason';
    end if;

  elsif p_target_status = 'reprocessing_required' then
    if v_any_findings = 0 then
      raise exception 'reprocessing_required requires at least one supporting finding';
    end if;
    if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
      raise exception 'reprocessing_required requires a decision_reason';
    end if;

  elsif p_target_status = 'rejected' then
    if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
      raise exception 'rejected requires a decision_reason';
    end if;
    if v_major_or_critical_findings = 0 then
      raise exception 'rejected requires at least one major or critical finding to exist';
    end if;
  end if;

  update document_extraction_reviews set
    review_status = p_target_status,
    submitted_by = v_actor,
    submitted_at = now(),
    decision_reason = p_decision_reason,
    warning_summary = p_warning_summary,
    decision_metadata = decision_metadata || jsonb_build_object('idempotency_key', p_idempotency_key),
    requires_ocr = (p_target_status = 'ocr_required'),
    requires_reprocessing = (p_target_status = 'reprocessing_required'),
    updated_at = now()
    where id = p_review_id
    returning * into v_review;

  insert into document_extraction_review_events (organization_id, extraction_review_id, extraction_run_id, event_type, from_status, to_status, actor_id, reason, correlation_id)
    values (v_review.organization_id, v_review.id, v_review.extraction_run_id, 'document_extraction_review.' || p_target_status, 'in_review', p_target_status, v_actor, p_decision_reason, p_correlation_id);
  perform record_audit_event(v_review.organization_id, 'document_extraction_review.' || p_target_status, 'document_extraction_review', v_review.id, p_correlation_id,
    jsonb_build_object('review_status', p_target_status, 'critical_findings', v_review.critical_finding_count, 'major_findings', v_review.major_finding_count));

  return v_review;
end;
$$;

revoke all on function submit_document_extraction_review(uuid, text, text, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 11.7 Extend reopen_extraction_review (migration 0009): cascade into any
-- dependent, still-active document_ocr_requests/document_ocr_reviews.
-- ----------------------------------------------------------------------------
-- Mission §10 ("OCR Invalidation Rules"): reopening an extraction review
-- must immediately block in-flight OCR processing for the round being
-- superseded, not merely a future create_document_ocr_request call.
-- create_document_ocr_run already re-verifies (11.1) that no later
-- extraction-review round exists — this cascade additionally makes the
-- supersession visible and terminal on the OCR side immediately (queued/
-- claimed jobs cancelled, request/review marked invalidated), rather than
-- leaving it to be discovered lazily the next time a Worker tries to
-- claim or create a run. No historical row is ever deleted (mission §10:
-- "no historical rows are deleted") — this only ever transitions
-- non-terminal rows to 'invalidated'/'cancelled'.

create or replace function reopen_extraction_review(
  p_review_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_old document_extraction_reviews%rowtype;
  v_new document_extraction_reviews%rowtype;
  v_ocr_request document_ocr_requests%rowtype;
  v_cascade_reason text;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reopening a review requires a reason';
  end if;

  select * into v_old from document_extraction_reviews where id = p_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_review_id;
  end if;

  perform assert_permission(v_old.organization_id, 'guideline_extraction_reviews.reopen');

  if v_old.review_status not in ('accepted', 'accepted_with_warnings', 'ocr_required', 'reprocessing_required', 'rejected') then
    raise exception 'only a submitted, non-invalidated decision can be reopened (current status: %)', v_old.review_status;
  end if;

  insert into document_extraction_reviews (
    organization_id, extraction_run_id, review_round, review_status,
    total_pages, reopened_from_review_id, reopen_reason, created_by
  ) values (
    v_old.organization_id, v_old.extraction_run_id, v_old.review_round + 1, 'pending_review',
    v_old.total_pages, v_old.id, p_reason, v_actor
  )
  returning * into v_new;

  insert into document_extraction_review_events (organization_id, extraction_review_id, extraction_run_id, event_type, from_status, to_status, actor_id, reason, correlation_id)
    values (v_new.organization_id, v_new.id, v_new.extraction_run_id, 'document_extraction_review.reopened', v_old.review_status, 'pending_review', v_actor, p_reason, p_correlation_id);
  perform record_audit_event(v_new.organization_id, 'document_extraction_review.reopened', 'document_extraction_review', v_new.id, p_correlation_id,
    jsonb_build_object('reopened_from_review_id', v_old.id, 'previous_status', v_old.review_status, 'reason', p_reason));

  -- Cascade: any OCR request tied to this extraction run that is still
  -- active (not already cancelled/invalidated) is now processing against a
  -- superseded review round.
  select * into v_ocr_request from document_ocr_requests
    where organization_id = v_old.organization_id
      and extraction_run_id = v_old.extraction_run_id
      and status not in ('cancelled', 'invalidated')
    for update;

  if found then
    v_cascade_reason := 'extraction review reopened (round ' || v_old.review_round || ' -> ' || v_new.review_round || '): ' || p_reason;

    update document_processing_jobs set status = 'cancelled', cancelled_at = now(), updated_at = now()
      where organization_id = v_ocr_request.organization_id
        and ocr_request_page_id in (select id from document_ocr_request_pages where ocr_request_id = v_ocr_request.id)
        and status in ('queued', 'claimed', 'processing');

    update document_ocr_request_pages set status = 'invalidated', updated_at = now()
      where ocr_request_id = v_ocr_request.id
        and status not in ('succeeded', 'failed', 'accepted', 'accepted_with_warnings', 'reprocessing_required', 'rejected', 'invalidated');

    update document_ocr_reviews set review_status = 'invalidated', decision_reason = v_cascade_reason, updated_at = now()
      where ocr_request_id = v_ocr_request.id and review_status in ('pending_review', 'in_review');

    update document_ocr_requests set
      status = 'invalidated', invalidated_at = now(), invalidation_reason = v_cascade_reason, updated_at = now()
      where id = v_ocr_request.id;

    perform record_audit_event(v_ocr_request.organization_id, 'document_ocr_request.invalidated', 'document_ocr_request', v_ocr_request.id, p_correlation_id,
      jsonb_build_object('reason', v_cascade_reason, 'cascaded_from_extraction_review_id', p_review_id));
  end if;

  return v_new;
end;
$$;

revoke all on function reopen_extraction_review(uuid, text, uuid) from public;

-- ============================================================================
-- 12. GRANTS — client-facing functions, guarded exactly like migration 0009
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
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
      invalidate_ocr_review(uuid, text, uuid),
      get_document_page_text_readiness(uuid),
      get_document_extraction_review_eligibility(uuid)
      to authenticated;

    revoke execute on function
      create_document_ocr_run(uuid, text, text, text, text, text, text, text, int, text, text, text, bigint, text, text, text, text, text, text[], uuid),
      finalize_document_ocr_page(uuid, uuid, text, text, text, text, int, int, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid),
      fail_document_ocr_run(uuid, uuid, text, text, text, text, text, uuid)
      from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke execute on function
      create_document_ocr_run(uuid, text, text, text, text, text, text, text, int, text, text, text, bigint, text, text, text, text, text, text[], uuid),
      finalize_document_ocr_page(uuid, uuid, text, text, text, text, int, int, text, jsonb, jsonb, jsonb, text, text, text, bigint, text, uuid),
      fail_document_ocr_run(uuid, uuid, text, text, text, text, text, uuid)
      from anon;
  end if;
end
$$;

-- ============================================================================
-- End of migration 0011
-- ============================================================================
