-- ============================================================================
-- Noor V1 — Migration 0009: Extraction Review and Technical Quality Gate
-- Council: Clinical Safety Agent + Extraction Quality Agent + Database Agent +
--          Security Agent + Backend Agent
-- ============================================================================
-- Sprint 1-D1. "Extraction execution succeeded" and "extraction quality is
-- accepted" are two independent facts. This migration adds the human review
-- layer on top of migration 0008's deterministic extraction — review rounds,
-- page-level and document-level findings, page-review coverage tracking,
-- append-only review events, and a single transactional submission function
-- that enforces every decision rule under lock. See ADR 0011 for the full
-- architecture rationale and the repository-pattern audit that produced it.
--
-- Explicitly NOT implemented here: OCR execution, chunk generation,
-- embeddings, retrieval, or any mutation of document_extraction_runs /
-- document_extraction_pages (those remain fully immutable — this migration
-- only ever reads them).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLE — document_extraction_reviews
-- ----------------------------------------------------------------------------
-- One row per review ROUND (not per edit). At most one row per
-- extraction_run_id may be in an active state (pending_review/in_review) at
-- a time (partial unique index below); a submitted row is immutable except
-- for the single legal accepted(-with-warnings) -> invalidated transition.

create table if not exists document_extraction_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  extraction_run_id uuid not null,

  review_round int not null default 1,
  review_status text not null default 'pending_review'
    check (review_status in (
      'pending_review', 'in_review', 'accepted', 'accepted_with_warnings',
      'ocr_required', 'reprocessing_required', 'rejected', 'invalidated'
    )),

  assigned_reviewer_id uuid references auth.users(id),
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz,

  started_by uuid references auth.users(id),
  started_at timestamptz,

  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,

  overall_comments text,
  technical_summary text,
  warning_summary text,

  critical_finding_count int not null default 0,
  major_finding_count int not null default 0,
  minor_finding_count int not null default 0,
  informational_finding_count int not null default 0,

  pages_reviewed int not null default 0,
  total_pages int not null default 0,
  all_pages_reviewed boolean not null default false,

  requires_ocr boolean not null default false,
  requires_reprocessing boolean not null default false,

  decision_reason text,
  decision_metadata jsonb not null default '{}'::jsonb,

  supersedes_review_id uuid,
  reopened_from_review_id uuid,
  reopen_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),

  unique (organization_id, id)
);

alter table document_extraction_reviews
  add constraint document_extraction_reviews_organization_id_extraction_ru_fkey
  foreign key (organization_id, extraction_run_id) references document_extraction_runs(organization_id, id);

alter table document_extraction_reviews
  add constraint document_extraction_reviews_organization_id_reopened_from__fkey
  foreign key (organization_id, reopened_from_review_id) references document_extraction_reviews(organization_id, id);

-- At most one ACTIVE (not-yet-submitted) round per extraction run. This is
-- what makes "creating duplicate active reviews" structurally impossible,
-- not just discouraged by the UI.
create unique index if not exists document_extraction_reviews_one_active_per_run
  on document_extraction_reviews (organization_id, extraction_run_id)
  where review_status in ('pending_review', 'in_review');

create index if not exists idx_extraction_reviews_run
  on document_extraction_reviews (organization_id, extraction_run_id, review_round desc);
create index if not exists idx_extraction_reviews_status
  on document_extraction_reviews (review_status);
create index if not exists idx_extraction_reviews_assigned
  on document_extraction_reviews (assigned_reviewer_id) where assigned_reviewer_id is not null;

comment on table document_extraction_reviews is
  'One row per extraction review ROUND. review_status is a completely separate state machine from document_extraction_runs.status (execution vs. human quality judgment) — see ADR 0011. See docs/domain/extraction-review-lifecycle.md.';

-- Immutability: once a round reaches a terminal decision, it is frozen —
-- the ONLY legal further transition is accepted/accepted_with_warnings ->
-- invalidated (mission §31/§11), and even then no other column may change
-- in the same statement. Reopening never mutates this row; it inserts a
-- new round instead (function below).
create or replace function prevent_terminal_extraction_review_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.review_status in ('accepted', 'accepted_with_warnings', 'ocr_required', 'reprocessing_required', 'rejected', 'invalidated') then
    if new.review_status = old.review_status then
      raise exception 'a submitted extraction review round is immutable; reopen it to create a new round'
        using errcode = '42501';
    end if;
    if not (old.review_status in ('accepted', 'accepted_with_warnings') and new.review_status = 'invalidated') then
      raise exception 'illegal extraction review transition: % -> %', old.review_status, new.review_status
        using errcode = '42501';
    end if;
    if new.decision_reason is distinct from old.decision_reason and new.review_status = 'invalidated' then
      null; -- invalidation is allowed to set/refresh decision_reason
    elsif new.submitted_by is distinct from old.submitted_by
       or new.submitted_at is distinct from old.submitted_at
       or new.overall_comments is distinct from old.overall_comments
       or new.warning_summary is distinct from old.warning_summary then
      raise exception 'invalidating a review may not also alter its original submitted decision fields'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_terminal_extraction_review_mutation on document_extraction_reviews;
create trigger trg_prevent_terminal_extraction_review_mutation
  before update on document_extraction_reviews
  for each row execute function prevent_terminal_extraction_review_mutation();

-- ----------------------------------------------------------------------------
-- 2. TABLE — document_extraction_review_findings
-- ----------------------------------------------------------------------------
-- One generalized findings table for both page-level (extraction_page_id
-- set) and document-level (extraction_page_id null) findings — mission
-- §10.3 explicitly prefers this over two separate tables provided the
-- taxonomy keeps it unambiguous, which the CHECK constraints below enforce.

create table if not exists document_extraction_review_findings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  extraction_review_id uuid not null,
  extraction_run_id uuid not null,
  extraction_page_id uuid,
  page_number int,

  finding_type text not null check (finding_type in (
    'missing_text', 'partial_text', 'incorrect_reading_order', 'multi_column_order_issue',
    'garbled_characters', 'unicode_normalization_issue', 'arabic_shaping_issue', 'arabic_direction_issue',
    'mixed_language_direction_issue', 'rotation_issue', 'unexpected_blank_page', 'image_only_page',
    'suspected_scanned_page', 'table_structure_loss', 'figure_caption_loss', 'footnote_loss',
    'header_footer_noise', 'duplicate_text', 'missing_page', 'page_number_mismatch',
    'metadata_mismatch', 'source_integrity_concern', 'other'
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

  supersedes_finding_id uuid,

  unique (organization_id, id),
  -- extraction_page_id present <=> page_number present (both null for a
  -- document-level finding, both set for a page-level one).
  check ((extraction_page_id is null) = (page_number is null)),
  check (finding_type <> 'other' or description is not null),
  -- dismissing/accepting-risk on a major or critical finding always needs a
  -- documented reason (mission §29/§14) — enforced at the row level, not
  -- only in the resolution function.
  check (status not in ('dismissed', 'accepted_risk') or severity not in ('major', 'critical') or resolution_note is not null)
);

alter table document_extraction_review_findings
  add constraint document_extraction_review_findings_organization_id_extra_fkey
  foreign key (organization_id, extraction_review_id) references document_extraction_reviews(organization_id, id);

alter table document_extraction_review_findings
  add constraint document_extraction_review_findings_organization_id_extra2_fkey
  foreign key (organization_id, extraction_run_id) references document_extraction_runs(organization_id, id);

alter table document_extraction_review_findings
  add constraint document_extraction_review_findings_organization_id_page_i_fkey
  foreign key (organization_id, extraction_page_id) references document_extraction_pages(organization_id, id);

alter table document_extraction_review_findings
  add constraint document_extraction_review_findings_organization_id_super_fkey
  foreign key (organization_id, supersedes_finding_id) references document_extraction_review_findings(organization_id, id);

create index if not exists idx_extraction_findings_review
  on document_extraction_review_findings (organization_id, extraction_review_id);
create index if not exists idx_extraction_findings_run
  on document_extraction_review_findings (organization_id, extraction_run_id);
create index if not exists idx_extraction_findings_open_severity
  on document_extraction_review_findings (extraction_review_id, severity) where status = 'open';

comment on table document_extraction_review_findings is
  'Page-level (extraction_page_id set) or document-level (null) technical findings against one review round. Core identity fields are immutable once created (trigger below); only status/resolution fields may change. See docs/domain/extraction-quality-findings.md.';

-- Core content is immutable once created — a correction is a new finding
-- (optionally linking supersedes_finding_id), not an edit. Resolution
-- fields remain mutable at any time the parent review is still active
-- (enforced by the function layer, not this trigger, since resolution
-- legitimately happens after creation).
create or replace function prevent_extraction_finding_content_mutation()
returns trigger
language plpgsql
as $$
begin
  if new.finding_type is distinct from old.finding_type
     or new.severity is distinct from old.severity
     or new.title is distinct from old.title
     or new.description is distinct from old.description
     or new.suggested_action is distinct from old.suggested_action
     or new.extraction_page_id is distinct from old.extraction_page_id
     or new.page_number is distinct from old.page_number
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at
  then
    raise exception 'a finding''s core content is immutable once created; create a new finding (optionally superseding this one) instead'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_extraction_finding_content_mutation on document_extraction_review_findings;
create trigger trg_prevent_extraction_finding_content_mutation
  before update on document_extraction_review_findings
  for each row execute function prevent_extraction_finding_content_mutation();

revoke delete on document_extraction_review_findings from public;

-- Reuses the same noor.allow_audit_maintenance override GUC as
-- audit_events / guideline_reviews / document_extraction_review_events,
-- rather than being unconditionally undeletable forever (found as a real
-- gap: hosted synthetic-test cleanup could not remove finding rows at
-- all until this override existed — see
-- docs/verification/sprint-1-d1-extraction-review-verification.md).
create or replace function prevent_extraction_finding_delete()
returns trigger
language plpgsql
as $$
begin
  if coalesce(current_setting('noor.allow_audit_maintenance', true), 'false') = 'true' then
    return old;
  end if;
  raise exception 'findings cannot be deleted; resolve, dismiss, or accept the risk instead. '
    'See docs/database/schema.md for the documented maintenance override procedure.'
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_prevent_extraction_finding_delete on document_extraction_review_findings;
create trigger trg_prevent_extraction_finding_delete
  before delete on document_extraction_review_findings
  for each row execute function prevent_extraction_finding_delete();

-- ----------------------------------------------------------------------------
-- 3. TABLE — document_extraction_page_reviews
-- ----------------------------------------------------------------------------
-- Explicit per-page review coverage. A page is only "reviewed" when a
-- reviewer explicitly marks it so — opening a page is never inferred as
-- review (mission §23).

create table if not exists document_extraction_page_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  extraction_review_id uuid not null,
  extraction_page_id uuid not null,
  page_number int not null check (page_number >= 1),

  review_status text not null default 'unreviewed'
    check (review_status in ('unreviewed', 'reviewed_clear', 'reviewed_with_findings', 'ocr_candidate', 'reprocessing_candidate')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id),
  unique (extraction_review_id, page_number)
);

alter table document_extraction_page_reviews
  add constraint document_extraction_page_reviews_organization_id_review_i_fkey
  foreign key (organization_id, extraction_review_id) references document_extraction_reviews(organization_id, id);

alter table document_extraction_page_reviews
  add constraint document_extraction_page_reviews_organization_id_page_id_fkey
  foreign key (organization_id, extraction_page_id) references document_extraction_pages(organization_id, id);

create index if not exists idx_extraction_page_reviews_review
  on document_extraction_page_reviews (organization_id, extraction_review_id);

comment on table document_extraction_page_reviews is
  'Explicit per-page review coverage for one review round. Frozen once the parent round reaches a terminal decision. See docs/domain/extraction-review-lifecycle.md.';

-- Frozen once the parent review round is terminal — editing page notes
-- after a final decision was submitted would silently rewrite history.
create or replace function prevent_page_review_mutation_after_submission()
returns trigger
language plpgsql
as $$
declare
  v_review_status text;
begin
  select review_status into v_review_status from document_extraction_reviews where id = old.extraction_review_id;
  if v_review_status in ('accepted', 'accepted_with_warnings', 'ocr_required', 'reprocessing_required', 'rejected', 'invalidated') then
    raise exception 'page review records are frozen once the parent review round is submitted' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_page_review_mutation_after_submission on document_extraction_page_reviews;
create trigger trg_prevent_page_review_mutation_after_submission
  before update on document_extraction_page_reviews
  for each row execute function prevent_page_review_mutation_after_submission();

-- ----------------------------------------------------------------------------
-- 4. TABLE — document_extraction_review_events (append-only)
-- ----------------------------------------------------------------------------
-- Fine-grained transition history for one review round, parallel to
-- guideline_lifecycle_events. Integrates with (does not replace) the global
-- audit_events table — every function below writes to both.

create table if not exists document_extraction_review_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  extraction_review_id uuid not null,
  extraction_run_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text not null,
  actor_id uuid references auth.users(id),
  reason text,
  correlation_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table document_extraction_review_events
  add constraint document_extraction_review_events_organization_id_review_fkey
  foreign key (organization_id, extraction_review_id) references document_extraction_reviews(organization_id, id);

create index if not exists idx_extraction_review_events_review
  on document_extraction_review_events (extraction_review_id, created_at desc);
create index if not exists idx_extraction_review_events_correlation
  on document_extraction_review_events (correlation_id);

comment on table document_extraction_review_events is
  'Append-only transition history for document_extraction_reviews, mirroring guideline_lifecycle_events. Reuses the noor.allow_audit_maintenance override GUC, not a new maintenance mechanism.';

revoke update, delete on document_extraction_review_events from public;

create or replace function prevent_extraction_review_event_mutation()
returns trigger
language plpgsql
as $$
begin
  if coalesce(current_setting('noor.allow_audit_maintenance', true), 'false') = 'true' then
    return coalesce(new, old);
  end if;
  raise exception '% is append-only. UPDATE/DELETE is blocked for all roles. '
    'See docs/database/schema.md for the documented maintenance override procedure.', TG_TABLE_NAME;
end;
$$;

drop trigger if exists trg_extraction_review_events_no_update on document_extraction_review_events;
create trigger trg_extraction_review_events_no_update
  before update on document_extraction_review_events
  for each row execute function prevent_extraction_review_event_mutation();

drop trigger if exists trg_extraction_review_events_no_delete on document_extraction_review_events;
create trigger trg_extraction_review_events_no_delete
  before delete on document_extraction_review_events
  for each row execute function prevent_extraction_review_event_mutation();

-- ============================================================================
-- 5. PERMISSIONS
-- ============================================================================
-- Deliberately a SEPARATE namespace from guideline_extractions.* (migration
-- 0008, execution-read-only) — this structurally reinforces the
-- execution/review architecture boundary (ADR 0011) from the permission
-- model too, not just the schema.

insert into permissions (key, description) values
  ('guideline_extraction_reviews.read', 'Read extraction review rounds, page-review coverage, and findings'),
  ('guideline_extraction_reviews.create', 'Open a new extraction review round for a succeeded extraction run'),
  ('guideline_extraction_reviews.assign', 'Assign or reassign an extraction review to a reviewer'),
  ('guideline_extraction_reviews.review', 'Start a review, mark pages reviewed, and create findings against an assigned review'),
  ('guideline_extraction_reviews.submit', 'Submit a final technical review decision'),
  ('guideline_extraction_reviews.reopen', 'Reopen a submitted review as a new round'),
  ('guideline_extraction_findings.create', 'Create page-level or document-level extraction findings'),
  ('guideline_extraction_findings.resolve', 'Resolve, dismiss, or accept the risk of an extraction finding'),
  ('guideline_extraction_source.read', 'Obtain short-lived signed read access to the original source PDF for review')
on conflict (key) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where (r.key, p.key) in (
  ('organization_admin', 'guideline_extraction_reviews.read'),
  ('organization_admin', 'guideline_extraction_reviews.create'),
  ('organization_admin', 'guideline_extraction_reviews.assign'),
  ('organization_admin', 'guideline_extraction_reviews.reopen'),
  ('organization_admin', 'guideline_extraction_source.read'),

  ('quality_manager', 'guideline_extraction_reviews.read'),
  ('quality_manager', 'guideline_extraction_reviews.create'),
  ('quality_manager', 'guideline_extraction_reviews.assign'),
  ('quality_manager', 'guideline_extraction_reviews.review'),
  ('quality_manager', 'guideline_extraction_reviews.submit'),
  ('quality_manager', 'guideline_extraction_reviews.reopen'),
  ('quality_manager', 'guideline_extraction_findings.create'),
  ('quality_manager', 'guideline_extraction_findings.resolve'),
  ('quality_manager', 'guideline_extraction_source.read'),

  ('clinical_reviewer', 'guideline_extraction_reviews.read'),
  ('clinical_reviewer', 'guideline_extraction_reviews.review'),
  ('clinical_reviewer', 'guideline_extraction_reviews.submit'),
  ('clinical_reviewer', 'guideline_extraction_findings.create'),
  ('clinical_reviewer', 'guideline_extraction_findings.resolve'),
  ('clinical_reviewer', 'guideline_extraction_source.read'),

  ('safety_officer', 'guideline_extraction_reviews.read'),

  ('auditor', 'guideline_extraction_reviews.read')
)
on conflict do nothing;

-- Clinicians hold none of these permissions, by design (mission §25) — RLS
-- below structurally returns zero review/finding/page-review rows to a
-- clinician session regardless of UI.

-- ============================================================================
-- 6. RLS
-- ============================================================================

alter table document_extraction_reviews enable row level security;
alter table document_extraction_review_findings enable row level security;
alter table document_extraction_page_reviews enable row level security;
alter table document_extraction_review_events enable row level security;

drop policy if exists document_extraction_reviews_select on document_extraction_reviews;
create policy document_extraction_reviews_select on document_extraction_reviews
  for select using (has_permission_in_organization(organization_id, 'guideline_extraction_reviews.read'));

drop policy if exists document_extraction_review_findings_select on document_extraction_review_findings;
create policy document_extraction_review_findings_select on document_extraction_review_findings
  for select using (has_permission_in_organization(organization_id, 'guideline_extraction_reviews.read'));

drop policy if exists document_extraction_page_reviews_select on document_extraction_page_reviews;
create policy document_extraction_page_reviews_select on document_extraction_page_reviews
  for select using (has_permission_in_organization(organization_id, 'guideline_extraction_reviews.read'));

drop policy if exists document_extraction_review_events_select on document_extraction_review_events;
create policy document_extraction_review_events_select on document_extraction_review_events
  for select using (has_permission_in_organization(organization_id, 'guideline_extraction_reviews.read'));

-- No INSERT/UPDATE/DELETE policy exists for `authenticated` on any of the
-- four tables — every write happens through the SECURITY DEFINER functions
-- below, which re-check permissions explicitly (assert_permission) rather
-- than relying on a write-side RLS policy.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on document_extraction_reviews, document_extraction_review_findings,
      document_extraction_page_reviews, document_extraction_review_events
      to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 7. FUNCTIONS — client-facing (SECURITY DEFINER, granted to authenticated
-- at the very end, section 8)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 7.1 create_document_extraction_review
-- ----------------------------------------------------------------------------
-- Idempotent by design: if an active round already exists for this run,
-- returns it rather than raising — this is what makes "duplicate active
-- review" impossible even under a client-side double-submit, on top of the
-- partial unique index's own defense-in-depth guarantee.

create or replace function create_document_extraction_review(
  p_extraction_run_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_run document_extraction_runs%rowtype;
  v_existing document_extraction_reviews%rowtype;
  v_review document_extraction_reviews%rowtype;
  v_next_round int;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_run from document_extraction_runs where id = p_extraction_run_id;
  if not found then
    raise exception 'extraction run not found: %', p_extraction_run_id;
  end if;

  perform assert_permission(v_run.organization_id, 'guideline_extraction_reviews.create');

  if v_run.status <> 'succeeded' then
    raise exception 'extraction review can only be opened for a succeeded extraction run (current status: %)', v_run.status;
  end if;

  select * into v_existing from document_extraction_reviews
    where organization_id = v_run.organization_id
      and extraction_run_id = p_extraction_run_id
      and review_status in ('pending_review', 'in_review')
    limit 1;
  if found then
    return v_existing;
  end if;

  select coalesce(max(review_round), 0) + 1 into v_next_round from document_extraction_reviews
    where organization_id = v_run.organization_id and extraction_run_id = p_extraction_run_id;

  insert into document_extraction_reviews (
    organization_id, extraction_run_id, review_round, review_status,
    total_pages, created_by
  ) values (
    v_run.organization_id, p_extraction_run_id, v_next_round, 'pending_review',
    coalesce(v_run.page_count, 0), v_actor
  )
  returning * into v_review;

  insert into document_extraction_review_events (organization_id, extraction_review_id, extraction_run_id, event_type, from_status, to_status, actor_id, correlation_id)
    values (v_review.organization_id, v_review.id, p_extraction_run_id, 'document_extraction_review.created', null, 'pending_review', v_actor, p_correlation_id);
  perform record_audit_event(v_review.organization_id, 'document_extraction_review.created', 'document_extraction_review', v_review.id, p_correlation_id,
    jsonb_build_object('extraction_run_id', p_extraction_run_id, 'review_round', v_next_round));

  return v_review;
end;
$$;

revoke all on function create_document_extraction_review(uuid, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.2 assign_extraction_reviewer
-- ----------------------------------------------------------------------------

create or replace function assign_extraction_reviewer(
  p_review_id uuid,
  p_reviewer_user_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_extraction_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_extraction_reviews where id = p_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_extraction_reviews.assign');

  if v_review.review_status not in ('pending_review', 'in_review') then
    raise exception 'only an active review round can be (re)assigned (current status: %)', v_review.review_status;
  end if;

  if not exists (
    select 1 from organization_memberships m
    join role_permissions rp on rp.role_id = m.role_id
    join permissions p on p.id = rp.permission_id
    where m.organization_id = v_review.organization_id
      and m.user_id = p_reviewer_user_id
      and m.status = 'active'
      and p.key = 'guideline_extraction_reviews.review'
  ) then
    raise exception 'reviewer % does not hold review permission in this organization', p_reviewer_user_id;
  end if;

  update document_extraction_reviews set
    assigned_reviewer_id = p_reviewer_user_id, assigned_by = v_actor, assigned_at = now(), updated_at = now()
    where id = p_review_id
    returning * into v_review;

  insert into document_extraction_review_events (organization_id, extraction_review_id, extraction_run_id, event_type, from_status, to_status, actor_id, correlation_id, metadata)
    values (v_review.organization_id, v_review.id, v_review.extraction_run_id, 'document_extraction_review.assigned', v_review.review_status, v_review.review_status, v_actor, p_correlation_id,
      jsonb_build_object('assigned_reviewer_id', p_reviewer_user_id));
  perform record_audit_event(v_review.organization_id, 'document_extraction_review.assigned', 'document_extraction_review', v_review.id, p_correlation_id,
    jsonb_build_object('assigned_reviewer_id', p_reviewer_user_id));

  return v_review;
end;
$$;

revoke all on function assign_extraction_reviewer(uuid, uuid, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.3 claim_extraction_review
-- ----------------------------------------------------------------------------

create or replace function claim_extraction_review(
  p_review_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_extraction_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_extraction_reviews where id = p_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_extraction_reviews.review');

  if v_review.review_status not in ('pending_review', 'in_review') then
    raise exception 'only an active review round can be claimed (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is not null then
    raise exception 'this review round is already assigned';
  end if;

  update document_extraction_reviews set
    assigned_reviewer_id = v_actor, assigned_by = v_actor, assigned_at = now(), updated_at = now()
    where id = p_review_id
    returning * into v_review;

  insert into document_extraction_review_events (organization_id, extraction_review_id, extraction_run_id, event_type, from_status, to_status, actor_id, correlation_id)
    values (v_review.organization_id, v_review.id, v_review.extraction_run_id, 'document_extraction_review.assigned', v_review.review_status, v_review.review_status, v_actor, p_correlation_id);
  perform record_audit_event(v_review.organization_id, 'document_extraction_review.assigned', 'document_extraction_review', v_review.id, p_correlation_id,
    jsonb_build_object('assigned_reviewer_id', v_actor, 'self_claimed', true));

  return v_review;
end;
$$;

revoke all on function claim_extraction_review(uuid, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.4 start_document_extraction_review
-- ----------------------------------------------------------------------------
-- Self-review block (ADR 0011 §3.6): a reviewer who uploaded or registered
-- the underlying source document may not start (and therefore never
-- submit) a review of its extraction. Unassigned reviews auto-claim on
-- start.

create or replace function start_document_extraction_review(
  p_review_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_extraction_reviews%rowtype;
  v_run document_extraction_runs%rowtype;
  v_doc guideline_source_documents%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_extraction_reviews where id = p_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_extraction_reviews.review');

  if v_review.review_status <> 'pending_review' then
    raise exception 'review can only be started from pending_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is not null and v_review.assigned_reviewer_id <> v_actor then
    raise exception 'this review round is assigned to a different reviewer' using errcode = '42501';
  end if;

  select * into v_run from document_extraction_runs
    where organization_id = v_review.organization_id and id = v_review.extraction_run_id;
  if v_run.status <> 'succeeded' then
    raise exception 'the underlying extraction run is no longer succeeded (status: %)', v_run.status;
  end if;

  select * into v_doc from guideline_source_documents
    where organization_id = v_review.organization_id and id = v_run.source_document_id;
  if v_doc.uploaded_by = v_actor or v_doc.registered_by = v_actor then
    raise exception 'a reviewer who uploaded or registered the source document cannot review its own extraction'
      using errcode = '42501';
  end if;

  update document_extraction_reviews set
    review_status = 'in_review',
    assigned_reviewer_id = coalesce(assigned_reviewer_id, v_actor),
    assigned_by = coalesce(assigned_by, v_actor),
    assigned_at = coalesce(assigned_at, now()),
    started_by = v_actor, started_at = now(), updated_at = now()
    where id = p_review_id
    returning * into v_review;

  insert into document_extraction_review_events (organization_id, extraction_review_id, extraction_run_id, event_type, from_status, to_status, actor_id, correlation_id)
    values (v_review.organization_id, v_review.id, v_review.extraction_run_id, 'document_extraction_review.started', 'pending_review', 'in_review', v_actor, p_correlation_id);
  perform record_audit_event(v_review.organization_id, 'document_extraction_review.started', 'document_extraction_review', v_review.id, p_correlation_id, '{}'::jsonb);

  return v_review;
end;
$$;

revoke all on function start_document_extraction_review(uuid, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.5 mark_extraction_page_reviewed
-- ----------------------------------------------------------------------------

create or replace function mark_extraction_page_reviewed(
  p_review_id uuid,
  p_page_number int,
  p_page_review_status text,
  p_notes text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_page_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_extraction_reviews%rowtype;
  v_page document_extraction_pages%rowtype;
  v_page_review document_extraction_page_reviews%rowtype;
  v_pages_reviewed int;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_page_review_status not in ('reviewed_clear', 'reviewed_with_findings', 'ocr_candidate', 'reprocessing_candidate') then
    raise exception 'invalid page review status: %', p_page_review_status;
  end if;

  select * into v_review from document_extraction_reviews where id = p_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_extraction_reviews.review');

  if v_review.review_status <> 'in_review' then
    raise exception 'pages can only be reviewed while the round is in_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is distinct from v_actor then
    raise exception 'only the assigned reviewer can mark pages reviewed' using errcode = '42501';
  end if;

  select * into v_page from document_extraction_pages
    where organization_id = v_review.organization_id
      and extraction_run_id = v_review.extraction_run_id
      and page_number = p_page_number;
  if not found then
    raise exception 'page % not found for extraction run %', p_page_number, v_review.extraction_run_id;
  end if;

  insert into document_extraction_page_reviews (organization_id, extraction_review_id, extraction_page_id, page_number, review_status, reviewed_by, reviewed_at, notes)
    values (v_review.organization_id, p_review_id, v_page.id, p_page_number, p_page_review_status, v_actor, now(), p_notes)
    on conflict (extraction_review_id, page_number) do update set
      review_status = excluded.review_status, reviewed_by = excluded.reviewed_by,
      reviewed_at = excluded.reviewed_at, notes = excluded.notes, updated_at = now()
    returning * into v_page_review;

  select count(*) into v_pages_reviewed from document_extraction_page_reviews
    where extraction_review_id = p_review_id and review_status <> 'unreviewed';

  update document_extraction_reviews set
    pages_reviewed = v_pages_reviewed,
    all_pages_reviewed = (v_pages_reviewed >= total_pages and total_pages > 0),
    updated_at = now()
    where id = p_review_id;

  perform record_audit_event(v_review.organization_id, 'document_extraction_review.page_reviewed', 'document_extraction_page_review', v_page_review.id, p_correlation_id,
    jsonb_build_object('extraction_review_id', p_review_id, 'page_number', p_page_number, 'review_status', p_page_review_status));

  return v_page_review;
end;
$$;

revoke all on function mark_extraction_page_reviewed(uuid, int, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.6 create_extraction_finding
-- ----------------------------------------------------------------------------

create or replace function create_extraction_finding(
  p_review_id uuid,
  p_finding_type text,
  p_severity text,
  p_title text,
  p_extraction_page_id uuid default null,
  p_description text default null,
  p_suggested_action text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_review_findings
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_extraction_reviews%rowtype;
  v_page document_extraction_pages%rowtype;
  v_page_number int := null;
  v_finding document_extraction_review_findings%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_extraction_reviews where id = p_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_extraction_findings.create');

  if v_review.review_status <> 'in_review' then
    raise exception 'findings can only be created while the round is in_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is distinct from v_actor then
    raise exception 'only the assigned reviewer can create findings' using errcode = '42501';
  end if;

  if p_extraction_page_id is not null then
    select * into v_page from document_extraction_pages
      where organization_id = v_review.organization_id
        and id = p_extraction_page_id
        and extraction_run_id = v_review.extraction_run_id;
    if not found then
      raise exception 'page % does not belong to this review''s extraction run', p_extraction_page_id;
    end if;
    v_page_number := v_page.page_number;
  end if;

  insert into document_extraction_review_findings (
    organization_id, extraction_review_id, extraction_run_id, extraction_page_id, page_number,
    finding_type, severity, title, description, suggested_action, created_by
  ) values (
    v_review.organization_id, p_review_id, v_review.extraction_run_id, p_extraction_page_id, v_page_number,
    p_finding_type, p_severity, p_title, p_description, p_suggested_action, v_actor
  )
  returning * into v_finding;

  update document_extraction_reviews set
    critical_finding_count = (select count(*) from document_extraction_review_findings where extraction_review_id = p_review_id and severity = 'critical' and status = 'open'),
    major_finding_count = (select count(*) from document_extraction_review_findings where extraction_review_id = p_review_id and severity = 'major' and status = 'open'),
    minor_finding_count = (select count(*) from document_extraction_review_findings where extraction_review_id = p_review_id and severity = 'minor' and status = 'open'),
    informational_finding_count = (select count(*) from document_extraction_review_findings where extraction_review_id = p_review_id and severity = 'informational' and status = 'open'),
    updated_at = now()
    where id = p_review_id;

  perform record_audit_event(v_review.organization_id, 'document_extraction_finding.created', 'document_extraction_review_finding', v_finding.id, p_correlation_id,
    jsonb_build_object('extraction_review_id', p_review_id, 'finding_type', p_finding_type, 'severity', p_severity, 'page_number', v_page_number));

  return v_finding;
end;
$$;

revoke all on function create_extraction_finding(uuid, text, text, text, uuid, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.7 update_extraction_finding_status
-- ----------------------------------------------------------------------------

create or replace function update_extraction_finding_status(
  p_finding_id uuid,
  p_status text,
  p_resolution_note text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_review_findings
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_finding document_extraction_review_findings%rowtype;
  v_review document_extraction_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_status not in ('open', 'acknowledged', 'resolved', 'accepted_risk', 'dismissed') then
    raise exception 'invalid finding status: %', p_status;
  end if;

  select * into v_finding from document_extraction_review_findings where id = p_finding_id for update;
  if not found then
    raise exception 'finding not found: %', p_finding_id;
  end if;

  perform assert_permission(v_finding.organization_id, 'guideline_extraction_findings.resolve');

  select * into v_review from document_extraction_reviews where id = v_finding.extraction_review_id;
  if v_review.review_status <> 'in_review' then
    raise exception 'findings can only be updated while the review round is in_review (current status: %)', v_review.review_status;
  end if;

  if p_status in ('dismissed', 'accepted_risk') and v_finding.severity in ('major', 'critical') and (p_resolution_note is null or length(trim(p_resolution_note)) = 0) then
    raise exception 'dismissing or accepting the risk of a % finding requires a resolution note', v_finding.severity;
  end if;

  update document_extraction_review_findings set
    status = p_status,
    resolved_by = case when p_status in ('resolved', 'dismissed', 'accepted_risk') then v_actor else null end,
    resolved_at = case when p_status in ('resolved', 'dismissed', 'accepted_risk') then now() else null end,
    resolution_note = p_resolution_note
    where id = p_finding_id
    returning * into v_finding;

  update document_extraction_reviews set
    critical_finding_count = (select count(*) from document_extraction_review_findings where extraction_review_id = v_finding.extraction_review_id and severity = 'critical' and status = 'open'),
    major_finding_count = (select count(*) from document_extraction_review_findings where extraction_review_id = v_finding.extraction_review_id and severity = 'major' and status = 'open'),
    minor_finding_count = (select count(*) from document_extraction_review_findings where extraction_review_id = v_finding.extraction_review_id and severity = 'minor' and status = 'open'),
    informational_finding_count = (select count(*) from document_extraction_review_findings where extraction_review_id = v_finding.extraction_review_id and severity = 'informational' and status = 'open'),
    updated_at = now()
    where id = v_finding.extraction_review_id;

  perform record_audit_event(v_finding.organization_id, 'document_extraction_finding.resolved', 'document_extraction_review_finding', v_finding.id, p_correlation_id,
    jsonb_build_object('status', p_status));

  return v_finding;
end;
$$;

revoke all on function update_extraction_finding_status(uuid, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.8 submit_document_extraction_review
-- ----------------------------------------------------------------------------
-- The single narrow transactional entry point for every terminal decision
-- (mission §28). Re-validates everything under lock — the database is the
-- actual gate, the UI's own validation exists only for user experience.

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
  v_ocr_relevant_findings int;
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

  -- Idempotent replay: same target status, same idempotency key already recorded.
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
  select count(*) into v_ocr_relevant_findings from document_extraction_review_findings
    where extraction_review_id = p_review_id
      and finding_type in ('missing_text', 'partial_text', 'image_only_page', 'suspected_scanned_page', 'unexpected_blank_page');

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
    if v_ocr_relevant_findings = 0 then
      raise exception 'ocr_required requires at least one supporting finding (image_only_page, suspected_scanned_page, missing_text, partial_text, or unexpected_blank_page)';
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
-- 7.9 reopen_extraction_review
-- ----------------------------------------------------------------------------
-- Never mutates the prior submitted round back into draft (mission §30) —
-- inserts a fresh round instead, with full page-review coverage required
-- again from zero (findings are not copied forward; a clean round keeps
-- the eligibility/coverage invariant simple and unambiguous).

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

  return v_new;
end;
$$;

revoke all on function reopen_extraction_review(uuid, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.10 invalidate_extraction_review
-- ----------------------------------------------------------------------------
-- The one legal terminal->terminal transition (mission §11/§31): an
-- accepted or accepted_with_warnings round may be administratively
-- invalidated (e.g. the underlying extraction is later found defective)
-- without needing a brand-new review round — eligibility becomes false
-- immediately, the original decision text is preserved untouched.

create or replace function invalidate_extraction_review(
  p_review_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns document_extraction_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_extraction_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalidating a review requires a reason';
  end if;

  select * into v_review from document_extraction_reviews where id = p_review_id for update;
  if not found then
    raise exception 'extraction review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_extraction_reviews.reopen');

  if v_review.review_status not in ('accepted', 'accepted_with_warnings') then
    raise exception 'only an accepted or accepted_with_warnings review can be invalidated (current status: %)', v_review.review_status;
  end if;

  update document_extraction_reviews set
    review_status = 'invalidated', decision_reason = p_reason, updated_at = now()
    where id = p_review_id
    returning * into v_review;

  insert into document_extraction_review_events (organization_id, extraction_review_id, extraction_run_id, event_type, from_status, to_status, actor_id, reason, correlation_id)
    values (v_review.organization_id, v_review.id, v_review.extraction_run_id, 'document_extraction_review.invalidated', v_review.review_status, 'invalidated', v_actor, p_reason, p_correlation_id);
  perform record_audit_event(v_review.organization_id, 'document_extraction_review.invalidated', 'document_extraction_review', v_review.id, p_correlation_id,
    jsonb_build_object('reason', p_reason));

  return v_review;
end;
$$;

revoke all on function invalidate_extraction_review(uuid, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 7.11 get_document_extraction_review_eligibility
-- ----------------------------------------------------------------------------
-- Server-derived downstream eligibility (mission §15) — there is no
-- client-writable eligibility column anywhere. Always evaluated from the
-- LATEST review round plus the extraction run's own execution status, so
-- reopening or invalidation take effect the instant they happen with no
-- separate bookkeeping.

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

  return query select
    p_extraction_run_id,
    v_run.status,
    v_latest.id,
    v_latest.review_status,
    (v_latest.review_status = 'ocr_required'),
    (v_latest.review_status in ('accepted', 'accepted_with_warnings')),
    false;
end;
$$;

revoke all on function get_document_extraction_review_eligibility(uuid) from public;

-- ============================================================================
-- 8. GRANTS — client-facing functions, guarded exactly like migration
-- 0005/0008 (the `authenticated` role does not exist at CI's plain-Postgres
-- migration-apply time, so this block is a documented no-op there — the RLS
-- test file must issue its own explicit grants, mirroring 003/005/008's
-- convention and the real bug that convention was created to prevent).
-- ============================================================================

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
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
  end if;
end
$$;

-- ============================================================================
-- End of migration 0009
-- ============================================================================
