-- ============================================================================
-- Noor V1 — Migration 0013: Chunk Technical Review and Embedding Readiness
-- Council: Clinical Safety Agent + Backend Agent + Database Agent
-- ============================================================================
-- Sprint 1-D3. The review/execution boundary one layer deeper than S1-D1
-- (extraction) and S1-D2 (OCR): a succeeded document_chunking_runs row
-- (migration 0012) proves the pipeline ran and coverage was proven — it
-- says nothing about whether the resulting chunk boundaries are actually
-- fit for a future embedding step. eligible_for_embedding only becomes
-- true once a human technical reviewer accepts every chunk. See ADR 0014.
-- ============================================================================

-- ============================================================================
-- 1. document_chunking_reviews — one review round over one chunking run
-- ============================================================================

create table if not exists document_chunking_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  chunking_run_id uuid not null,
  review_round int not null default 1,
  review_status text not null default 'pending_review'
    check (review_status in ('pending_review', 'in_review', 'accepted', 'accepted_with_warnings', 'rechunk_required', 'rejected', 'invalidated')),

  assigned_reviewer_id uuid references auth.users(id),
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz,
  started_by uuid references auth.users(id),
  started_at timestamptz,
  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,

  decision_reason text,
  warning_summary text,

  chunks_reviewed int not null default 0,
  total_chunks int not null default 0,
  all_chunks_reviewed boolean not null default false,

  supersedes_review_id uuid,
  reopened_from_review_id uuid,
  reopen_reason text,

  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, id)
);

alter table document_chunking_reviews
  add constraint document_chunking_reviews_chunking_run_id_fkey
  foreign key (organization_id, chunking_run_id) references document_chunking_runs(organization_id, id);

-- One active (non-terminal) review round per chunking run.
create unique index if not exists document_chunking_reviews_one_active_per_run
  on document_chunking_reviews (organization_id, chunking_run_id)
  where review_status in ('pending_review', 'in_review');

create index if not exists document_chunking_reviews_by_run on document_chunking_reviews (organization_id, chunking_run_id, review_round desc);

-- Freezes a submitted round, with the one legal accepted/accepted_with_warnings
-- -> invalidated transition — identical shape to document_extraction_reviews'/
-- document_ocr_reviews' own triggers (0009/0011).
create or replace function prevent_terminal_chunking_review_mutation()
returns trigger language plpgsql as $$
begin
  if old.review_status in ('accepted', 'accepted_with_warnings', 'rechunk_required', 'rejected', 'invalidated') then
    if new.review_status = 'invalidated' and old.review_status in ('accepted', 'accepted_with_warnings') then
      new.updated_at := now();
      return new;
    end if;
    raise exception 'chunking review % is already terminal (status: %) and cannot be modified', old.id, old.review_status;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_terminal_chunking_review_mutation on document_chunking_reviews;
create trigger trg_prevent_terminal_chunking_review_mutation
  before update on document_chunking_reviews
  for each row execute function prevent_terminal_chunking_review_mutation();

alter table document_chunking_reviews enable row level security;

-- ============================================================================
-- 2. document_chunk_reviews — one decision per (round, chunk)
-- ============================================================================

create table if not exists document_chunk_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  chunking_review_id uuid not null,
  chunk_id uuid not null,
  chunk_index int not null,

  review_status text not null default 'unreviewed'
    check (review_status in ('unreviewed', 'reviewed_clear', 'reviewed_with_findings', 'rechunk_candidate', 'rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (chunking_review_id, chunk_id)
);

alter table document_chunk_reviews
  add constraint document_chunk_reviews_chunking_review_id_fkey
  foreign key (organization_id, chunking_review_id) references document_chunking_reviews(organization_id, id);

alter table document_chunk_reviews
  add constraint document_chunk_reviews_chunk_id_fkey
  foreign key (organization_id, chunk_id) references document_chunks(organization_id, id);

create index if not exists document_chunk_reviews_by_review on document_chunk_reviews (organization_id, chunking_review_id, chunk_index);

-- Rows freeze once their parent review round is terminal — same pattern as
-- document_extraction_page_reviews/document_ocr_page_reviews.
create or replace function prevent_chunk_review_mutation_after_terminal()
returns trigger language plpgsql as $$
declare
  v_review_status text;
begin
  select review_status into v_review_status from document_chunking_reviews where id = old.chunking_review_id;
  if v_review_status not in ('pending_review', 'in_review') then
    raise exception 'chunk review row % belongs to a terminal chunking review round and cannot be modified', old.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_chunk_review_mutation_after_terminal on document_chunk_reviews;
create trigger trg_prevent_chunk_review_mutation_after_terminal
  before update on document_chunk_reviews
  for each row execute function prevent_chunk_review_mutation_after_terminal();

alter table document_chunk_reviews enable row level security;

-- ============================================================================
-- 3. document_chunk_findings
-- ============================================================================

create table if not exists document_chunk_findings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  chunking_review_id uuid not null,
  chunk_id uuid,

  finding_type text not null check (finding_type in (
    'missing_content', 'duplicated_content', 'invalid_source_span', 'wrong_page_provenance',
    'wrong_representation', 'boundary_splits_sentence', 'boundary_splits_list', 'boundary_splits_table',
    'heading_detached', 'footnote_detached', 'merged_unrelated_content', 'insufficient_context',
    'oversized_chunk', 'undersized_chunk', 'hard_split_required', 'arabic_boundary_issue',
    'mixed_language_boundary_issue', 'ocr_warning_propagation', 'header_footer_noise',
    'page_boundary_issue', 'token_count_issue', 'artifact_integrity_issue', 'other'
  )),
  severity text not null check (severity in ('informational', 'minor', 'major', 'critical')),
  title text not null,
  description text,
  suggested_action text,
  check (finding_type <> 'other' or description is not null),

  status text not null default 'open'
    check (status in ('open', 'acknowledged', 'resolved', 'accepted_risk', 'dismissed')),
  resolution_note text,
  check (status not in ('dismissed', 'accepted_risk') or severity not in ('major', 'critical') or resolution_note is not null),

  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),

  unique (organization_id, id)
);

alter table document_chunk_findings
  add constraint document_chunk_findings_chunking_review_id_fkey
  foreign key (organization_id, chunking_review_id) references document_chunking_reviews(organization_id, id);

alter table document_chunk_findings
  add constraint document_chunk_findings_chunk_id_fkey
  foreign key (organization_id, chunk_id) references document_chunks(organization_id, id);

create index if not exists document_chunk_findings_by_review on document_chunk_findings (organization_id, chunking_review_id, severity);

create or replace function prevent_chunk_finding_content_mutation()
returns trigger language plpgsql as $$
begin
  if new.finding_type <> old.finding_type or new.title <> old.title or new.description is distinct from old.description
    or new.severity <> old.severity or new.chunk_id is distinct from old.chunk_id then
    raise exception 'a chunk finding''s core content is immutable once created — only status/resolution_note may change';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_prevent_chunk_finding_content_mutation on document_chunk_findings;
create trigger trg_prevent_chunk_finding_content_mutation
  before update on document_chunk_findings
  for each row execute function prevent_chunk_finding_content_mutation();

-- Same maintenance-override GUC every prior finding table uses (a real bug
-- was found in S1-D1 when this was missing from the first version — see
-- docs/verification/sprint-1-d1-extraction-review-verification.md — so it
-- is included from this table's very first version, not added later).
create or replace function prevent_chunk_finding_delete()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('noor.allow_audit_maintenance', true), 'false') <> 'true' then
    raise exception 'chunk findings cannot be deleted (immutable audit trail)';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_prevent_chunk_finding_delete on document_chunk_findings;
create trigger trg_prevent_chunk_finding_delete
  before delete on document_chunk_findings
  for each row execute function prevent_chunk_finding_delete();

alter table document_chunk_findings enable row level security;

-- ============================================================================
-- 4. document_chunking_review_events — append-only audit trail
-- ============================================================================

create table if not exists document_chunking_review_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  chunking_review_id uuid not null,
  chunking_run_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  actor_id uuid references auth.users(id),
  reason text,
  correlation_id uuid,
  created_at timestamptz not null default now()
);

alter table document_chunking_review_events
  add constraint document_chunking_review_events_chunking_review_id_fkey
  foreign key (organization_id, chunking_review_id) references document_chunking_reviews(organization_id, id);

create index if not exists document_chunking_review_events_by_review on document_chunking_review_events (organization_id, chunking_review_id, created_at);

create or replace function prevent_chunking_review_event_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'document_chunking_review_events is append-only';
end;
$$;

drop trigger if exists trg_prevent_chunking_review_event_update on document_chunking_review_events;
create trigger trg_prevent_chunking_review_event_update
  before update on document_chunking_review_events
  for each row execute function prevent_chunking_review_event_mutation();

drop trigger if exists trg_prevent_chunking_review_event_delete on document_chunking_review_events;
create trigger trg_prevent_chunking_review_event_delete
  before delete on document_chunking_review_events
  for each row execute function prevent_chunking_review_event_mutation();

alter table document_chunking_review_events enable row level security;

-- ============================================================================
-- 5. RLS — SELECT-only, gated on guideline_chunking.read (permissions already
--    declared in migration 0012)
-- ============================================================================

drop policy if exists document_chunking_reviews_select on document_chunking_reviews;
create policy document_chunking_reviews_select on document_chunking_reviews
  for select using (has_permission_in_organization(organization_id, 'guideline_chunking.read'));

drop policy if exists document_chunk_reviews_select on document_chunk_reviews;
create policy document_chunk_reviews_select on document_chunk_reviews
  for select using (has_permission_in_organization(organization_id, 'guideline_chunking.read'));

drop policy if exists document_chunk_findings_select on document_chunk_findings;
create policy document_chunk_findings_select on document_chunk_findings
  for select using (has_permission_in_organization(organization_id, 'guideline_chunking.read'));

drop policy if exists document_chunking_review_events_select on document_chunking_review_events;
create policy document_chunking_review_events_select on document_chunking_review_events
  for select using (has_permission_in_organization(organization_id, 'guideline_chunking.read'));

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on document_chunking_reviews, document_chunk_reviews, document_chunk_findings, document_chunking_review_events to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 6. Review lifecycle functions
-- ============================================================================

create or replace function create_document_chunking_review(
  p_chunking_run_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunking_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_run document_chunking_runs%rowtype;
  v_existing document_chunking_reviews%rowtype;
  v_review document_chunking_reviews%rowtype;
  v_chunk_count int;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_run from document_chunking_runs where id = p_chunking_run_id for update;
  if not found then
    raise exception 'chunking run not found: %', p_chunking_run_id;
  end if;

  perform assert_permission(v_run.organization_id, 'guideline_chunking.create');

  if v_run.status <> 'succeeded' then
    raise exception 'a chunking review can only be created for a succeeded run (current status: %)', v_run.status;
  end if;

  select * into v_existing from document_chunking_reviews
    where organization_id = v_run.organization_id and chunking_run_id = p_chunking_run_id
      and review_status not in ('rejected', 'invalidated')
    order by review_round desc limit 1;
  if found then
    return v_existing;
  end if;

  select count(*) into v_chunk_count from document_chunks where chunking_run_id = p_chunking_run_id;

  insert into document_chunking_reviews (
    organization_id, chunking_run_id, review_round, review_status, total_chunks, created_by
  ) values (
    v_run.organization_id, p_chunking_run_id, 1, 'pending_review', v_chunk_count, v_actor
  )
  returning * into v_review;

  insert into document_chunk_reviews (organization_id, chunking_review_id, chunk_id, chunk_index)
    select v_run.organization_id, v_review.id, id, chunk_index from document_chunks where chunking_run_id = p_chunking_run_id;

  insert into document_chunking_review_events (organization_id, chunking_review_id, chunking_run_id, event_type, from_status, to_status, actor_id, correlation_id)
    values (v_review.organization_id, v_review.id, p_chunking_run_id, 'document_chunking_review.created', null, 'pending_review', v_actor, p_correlation_id);
  perform record_audit_event(v_review.organization_id, 'document_chunking_review.created', 'document_chunking_review', v_review.id, p_correlation_id,
    jsonb_build_object('chunking_run_id', p_chunking_run_id, 'total_chunks', v_chunk_count));

  return v_review;
end;
$$;

revoke all on function create_document_chunking_review(uuid, uuid) from public;

create or replace function assign_chunking_reviewer(
  p_review_id uuid,
  p_reviewer_user_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunking_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_chunking_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_chunking_reviews where id = p_review_id for update;
  if not found then
    raise exception 'chunking review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_chunking.review');

  if v_review.review_status not in ('pending_review', 'in_review') then
    raise exception 'only an active chunking review round can be (re)assigned (current status: %)', v_review.review_status;
  end if;

  if not exists (
    select 1 from organization_memberships m
    join role_permissions rp on rp.role_id = m.role_id
    join permissions p on p.id = rp.permission_id
    where m.organization_id = v_review.organization_id and m.user_id = p_reviewer_user_id
      and m.status = 'active' and p.key = 'guideline_chunking.review'
  ) then
    raise exception 'reviewer % does not hold chunking review permission in this organization', p_reviewer_user_id;
  end if;

  update document_chunking_reviews set
    assigned_reviewer_id = p_reviewer_user_id, assigned_by = v_actor, assigned_at = now(), updated_at = now()
    where id = p_review_id
    returning * into v_review;

  perform record_audit_event(v_review.organization_id, 'document_chunking_review.assigned', 'document_chunking_review', v_review.id, p_correlation_id,
    jsonb_build_object('assigned_reviewer_id', p_reviewer_user_id));

  return v_review;
end;
$$;

revoke all on function assign_chunking_reviewer(uuid, uuid, uuid) from public;

create or replace function claim_chunking_review(
  p_review_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunking_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_chunking_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_chunking_reviews where id = p_review_id for update;
  if not found then
    raise exception 'chunking review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_chunking.review');

  if v_review.review_status <> 'pending_review' then
    raise exception 'only a pending_review round can be self-claimed (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is not null then
    raise exception 'this review round is already assigned';
  end if;

  update document_chunking_reviews set
    assigned_reviewer_id = v_actor, assigned_by = v_actor, assigned_at = now(), updated_at = now()
    where id = p_review_id
    returning * into v_review;

  perform record_audit_event(v_review.organization_id, 'document_chunking_review.assigned', 'document_chunking_review', v_review.id, p_correlation_id,
    jsonb_build_object('assigned_reviewer_id', v_actor, 'self_claimed', true));

  return v_review;
end;
$$;

revoke all on function claim_chunking_review(uuid, uuid) from public;

create or replace function start_document_chunking_review(
  p_review_id uuid,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunking_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_chunking_reviews%rowtype;
  v_run document_chunking_runs%rowtype;
  v_doc guideline_source_documents%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_chunking_reviews where id = p_review_id for update;
  if not found then
    raise exception 'chunking review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_chunking.review');

  if v_review.review_status <> 'pending_review' then
    raise exception 'chunking review can only be started from pending_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is not null and v_review.assigned_reviewer_id <> v_actor then
    raise exception 'this chunking review round is assigned to a different reviewer' using errcode = '42501';
  end if;

  select * into v_run from document_chunking_runs where organization_id = v_review.organization_id and id = v_review.chunking_run_id;
  select * into v_doc from guideline_source_documents where organization_id = v_review.organization_id and id = v_run.source_document_id;
  if v_doc.uploaded_by = v_actor or v_doc.registered_by = v_actor then
    raise exception 'a reviewer who uploaded or registered the source document cannot review its own chunking output'
      using errcode = '42501';
  end if;

  update document_chunking_reviews set
    review_status = 'in_review', started_by = v_actor, started_at = now(),
    assigned_reviewer_id = coalesce(assigned_reviewer_id, v_actor), updated_at = now()
    where id = p_review_id
    returning * into v_review;

  insert into document_chunking_review_events (organization_id, chunking_review_id, chunking_run_id, event_type, from_status, to_status, actor_id, correlation_id)
    values (v_review.organization_id, v_review.id, v_review.chunking_run_id, 'document_chunking_review.started', 'pending_review', 'in_review', v_actor, p_correlation_id);

  return v_review;
end;
$$;

revoke all on function start_document_chunking_review(uuid, uuid) from public;

create or replace function mark_chunk_reviewed(
  p_review_id uuid,
  p_chunk_index int,
  p_review_status text,
  p_notes text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunk_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_chunking_reviews%rowtype;
  v_row document_chunk_reviews%rowtype;
  v_reviewed_count int;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_review_status not in ('reviewed_clear', 'reviewed_with_findings', 'rechunk_candidate', 'rejected') then
    raise exception 'invalid chunk review status: %', p_review_status;
  end if;

  select * into v_review from document_chunking_reviews where id = p_review_id for update;
  if not found then
    raise exception 'chunking review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_chunking.review');

  if v_review.review_status <> 'in_review' then
    raise exception 'chunks can only be marked while the review is in_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id <> v_actor then
    raise exception 'only the assigned reviewer can mark chunks reviewed' using errcode = '42501';
  end if;

  update document_chunk_reviews set
    review_status = p_review_status, reviewed_by = v_actor, reviewed_at = now(), notes = p_notes, updated_at = now()
    where chunking_review_id = p_review_id and chunk_index = p_chunk_index
    returning * into v_row;
  if not found then
    raise exception 'chunk index % not found in this review', p_chunk_index;
  end if;

  select count(*) into v_reviewed_count from document_chunk_reviews
    where chunking_review_id = p_review_id and review_status <> 'unreviewed';

  update document_chunking_reviews set
    chunks_reviewed = v_reviewed_count,
    all_chunks_reviewed = (v_reviewed_count >= total_chunks and total_chunks > 0),
    updated_at = now()
    where id = p_review_id;

  return v_row;
end;
$$;

revoke all on function mark_chunk_reviewed(uuid, int, text, text, uuid) from public;

create or replace function create_chunk_finding(
  p_review_id uuid,
  p_finding_type text,
  p_severity text,
  p_title text,
  p_chunk_index int default null,
  p_description text default null,
  p_suggested_action text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunk_findings
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_chunking_reviews%rowtype;
  v_chunk_id uuid;
  v_finding document_chunk_findings%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_review from document_chunking_reviews where id = p_review_id for update;
  if not found then
    raise exception 'chunking review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_chunking.review');

  if v_review.review_status <> 'in_review' then
    raise exception 'findings can only be created while the review is in_review (current status: %)', v_review.review_status;
  end if;

  if p_chunk_index is not null then
    select chunk_id into v_chunk_id from document_chunk_reviews
      where chunking_review_id = p_review_id and chunk_index = p_chunk_index;
    if v_chunk_id is null then
      raise exception 'chunk index % not found in this review', p_chunk_index;
    end if;
  end if;

  insert into document_chunk_findings (
    organization_id, chunking_review_id, chunk_id, finding_type, severity, title, description, suggested_action, created_by, updated_by
  ) values (
    v_review.organization_id, p_review_id, v_chunk_id, p_finding_type, p_severity, p_title, p_description, p_suggested_action, v_actor, v_actor
  )
  returning * into v_finding;

  perform record_audit_event(v_review.organization_id, 'document_chunk_finding.created', 'document_chunk_findings', v_finding.id, p_correlation_id,
    jsonb_build_object('finding_type', p_finding_type, 'severity', p_severity, 'chunk_index', p_chunk_index));

  return v_finding;
end;
$$;

revoke all on function create_chunk_finding(uuid, text, text, text, int, text, text, uuid) from public;

create or replace function update_chunk_finding_status(
  p_finding_id uuid,
  p_status text,
  p_resolution_note text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunk_findings
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_finding document_chunk_findings%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_status not in ('open', 'acknowledged', 'resolved', 'accepted_risk', 'dismissed') then
    raise exception 'invalid finding status: %', p_status;
  end if;

  select * into v_finding from document_chunk_findings where id = p_finding_id for update;
  if not found then
    raise exception 'chunk finding not found: %', p_finding_id;
  end if;

  perform assert_permission(v_finding.organization_id, 'guideline_chunking.review');

  update document_chunk_findings set
    status = p_status, resolution_note = coalesce(p_resolution_note, resolution_note), updated_by = v_actor, updated_at = now()
    where id = p_finding_id
    returning * into v_finding;

  perform record_audit_event(v_finding.organization_id, 'document_chunk_finding.resolved', 'document_chunk_findings', v_finding.id, p_correlation_id,
    jsonb_build_object('status', p_status));

  return v_finding;
end;
$$;

revoke all on function update_chunk_finding_status(uuid, text, text, uuid) from public;

create or replace function submit_document_chunking_review(
  p_review_id uuid,
  p_target_status text,
  p_decision_reason text default null,
  p_warning_summary text default null,
  p_idempotency_key text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunking_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_review document_chunking_reviews%rowtype;
  v_run document_chunking_runs%rowtype;
  v_open_critical int;
  v_open_major int;
  v_any_findings int;
  v_major_or_critical int;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_target_status not in ('accepted', 'accepted_with_warnings', 'rechunk_required', 'rejected') then
    raise exception 'invalid target chunking review status: %', p_target_status;
  end if;

  select * into v_review from document_chunking_reviews where id = p_review_id for update;
  if not found then
    raise exception 'chunking review not found: %', p_review_id;
  end if;

  perform assert_permission(v_review.organization_id, 'guideline_chunking.submit_review');

  if v_review.review_status <> 'in_review' then
    raise exception 'a chunking review can only be submitted from in_review (current status: %)', v_review.review_status;
  end if;
  if v_review.assigned_reviewer_id is distinct from v_actor then
    raise exception 'only the assigned reviewer can submit this chunking review' using errcode = '42501';
  end if;
  if not v_review.all_chunks_reviewed then
    raise exception 'every chunk must be marked reviewed before a final decision can be submitted (% of % reviewed)',
      v_review.chunks_reviewed, v_review.total_chunks;
  end if;

  select * into v_run from document_chunking_runs where organization_id = v_review.organization_id and id = v_review.chunking_run_id;
  if v_run.status <> 'succeeded' then
    raise exception 'the underlying chunking run is no longer succeeded (status: %); this review cannot be submitted', v_run.status;
  end if;

  select count(*) into v_open_critical from document_chunk_findings where chunking_review_id = p_review_id and severity = 'critical' and status = 'open';
  select count(*) into v_open_major from document_chunk_findings where chunking_review_id = p_review_id and severity = 'major' and status = 'open';
  select count(*) into v_any_findings from document_chunk_findings where chunking_review_id = p_review_id;
  select count(*) into v_major_or_critical from document_chunk_findings where chunking_review_id = p_review_id and severity in ('major', 'critical');

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
  elsif p_target_status = 'rechunk_required' then
    if v_any_findings = 0 then
      raise exception 'rechunk_required requires at least one supporting finding';
    end if;
    if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
      raise exception 'rechunk_required requires a decision_reason';
    end if;
  elsif p_target_status = 'rejected' then
    if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
      raise exception 'rejected requires a decision_reason';
    end if;
    if v_major_or_critical = 0 then
      raise exception 'rejected requires at least one major or critical finding to exist';
    end if;
  end if;

  update document_chunking_reviews set
    review_status = p_target_status, submitted_by = v_actor, submitted_at = now(),
    decision_reason = p_decision_reason, warning_summary = p_warning_summary, updated_at = now()
    where id = p_review_id
    returning * into v_review;

  insert into document_chunking_review_events (organization_id, chunking_review_id, chunking_run_id, event_type, from_status, to_status, actor_id, reason, correlation_id)
    values (v_review.organization_id, v_review.id, v_review.chunking_run_id, 'document_chunking_review.' || p_target_status, 'in_review', p_target_status, v_actor, p_decision_reason, p_correlation_id);
  perform record_audit_event(v_review.organization_id, 'document_chunking_review.' || p_target_status, 'document_chunking_review', v_review.id, p_correlation_id,
    jsonb_build_object('review_status', p_target_status));

  return v_review;
end;
$$;

revoke all on function submit_document_chunking_review(uuid, text, text, text, text, uuid) from public;

create or replace function reopen_chunking_review(
  p_review_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunking_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_old document_chunking_reviews%rowtype;
  v_new document_chunking_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reopening a chunking review requires a reason';
  end if;

  select * into v_old from document_chunking_reviews where id = p_review_id for update;
  if not found then
    raise exception 'chunking review not found: %', p_review_id;
  end if;

  perform assert_permission(v_old.organization_id, 'guideline_chunking.reopen_review');

  if v_old.review_status not in ('accepted', 'accepted_with_warnings', 'rechunk_required', 'rejected') then
    raise exception 'only a submitted, non-invalidated chunking decision can be reopened (current status: %)', v_old.review_status;
  end if;

  insert into document_chunking_reviews (
    organization_id, chunking_run_id, review_round, review_status,
    total_chunks, reopened_from_review_id, reopen_reason, created_by
  ) values (
    v_old.organization_id, v_old.chunking_run_id, v_old.review_round + 1, 'pending_review',
    v_old.total_chunks, v_old.id, p_reason, v_actor
  )
  returning * into v_new;

  insert into document_chunk_reviews (organization_id, chunking_review_id, chunk_id, chunk_index)
    select v_old.organization_id, v_new.id, id, chunk_index from document_chunks where chunking_run_id = v_old.chunking_run_id;

  insert into document_chunking_review_events (organization_id, chunking_review_id, chunking_run_id, event_type, from_status, to_status, actor_id, reason, correlation_id)
    values (v_new.organization_id, v_new.id, v_new.chunking_run_id, 'document_chunking_review.reopened', v_old.review_status, 'pending_review', v_actor, p_reason, p_correlation_id);
  perform record_audit_event(v_new.organization_id, 'document_chunking_review.reopened', 'document_chunking_review', v_new.id, p_correlation_id,
    jsonb_build_object('reopened_from_review_id', v_old.id, 'previous_status', v_old.review_status));

  return v_new;
end;
$$;

revoke all on function reopen_chunking_review(uuid, text, uuid) from public;

create or replace function invalidate_document_chunking_run(
  p_chunking_run_id uuid,
  p_reason text,
  p_correlation_id uuid default gen_random_uuid()
) returns document_chunking_runs
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_run document_chunking_runs%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalidating a chunking run requires a reason';
  end if;

  select * into v_run from document_chunking_runs where id = p_chunking_run_id for update;
  if not found then
    raise exception 'chunking run not found: %', p_chunking_run_id;
  end if;

  perform assert_permission(v_run.organization_id, 'guideline_chunking.invalidate');

  if v_run.status not in ('succeeded', 'reused') then
    raise exception 'only a succeeded or reused chunking run can be invalidated (current status: %)', v_run.status;
  end if;

  update document_chunking_runs set
    status = 'invalidated', invalidated_at = now(), invalidation_reason = p_reason
    where id = p_chunking_run_id
    returning * into v_run;

  perform record_audit_event(v_run.organization_id, 'document_chunking.invalidated', 'document_chunking_run', v_run.id, p_correlation_id,
    jsonb_build_object('reason', p_reason));

  return v_run;
end;
$$;

revoke all on function invalidate_document_chunking_run(uuid, text, uuid) from public;

-- ============================================================================
-- 7. get_document_embedding_readiness — the canonical derived function
--    (mission §47). Never a stored flag — recomputed live every call, same
--    discipline as get_document_extraction_review_eligibility.
-- ============================================================================

create or replace function get_document_embedding_readiness(
  p_source_document_id uuid
) returns table (
  out_source_document_id uuid,
  out_chunking_run_id uuid,
  out_chunking_status text,
  out_review_status text,
  out_eligible_for_embedding boolean,
  out_eligible_for_retrieval boolean,
  out_reason text
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_doc guideline_source_documents%rowtype;
  v_run document_chunking_runs%rowtype;
  v_review document_chunking_reviews%rowtype;
  v_elig record;
begin
  select * into v_doc from guideline_source_documents where id = p_source_document_id;
  if not found then
    raise exception 'source document not found: %', p_source_document_id;
  end if;

  perform assert_permission(v_doc.organization_id, 'guideline_chunking.read');

  select * into v_run from document_chunking_runs
    where organization_id = v_doc.organization_id and source_document_id = p_source_document_id
    order by created_at desc limit 1;

  if not found then
    return query select p_source_document_id, null::uuid, null::text, null::text, false, false, 'no_chunking_run'::text;
    return;
  end if;

  if v_run.status <> 'succeeded' then
    return query select p_source_document_id, v_run.id, v_run.status, null::text, false, false,
      case v_run.status when 'running' then 'chunking_running' when 'failed' then 'chunking_failed' else 'chunking_invalidated' end;
    return;
  end if;

  -- Live-revalidate the upstream extraction/OCR state — this is the
  -- authoritative safety net (not just a stored flag) if extraction or OCR
  -- was invalidated/reopened after this chunking run succeeded.
  select * into v_elig from get_document_extraction_review_eligibility(v_run.extraction_run_id);
  if not v_elig.out_eligible_for_chunking then
    return query select p_source_document_id, v_run.id, v_run.status, null::text, false, false, 'upstream_input_no_longer_eligible'::text;
    return;
  end if;

  select * into v_review from document_chunking_reviews
    where organization_id = v_doc.organization_id and chunking_run_id = v_run.id
    order by review_round desc limit 1;

  if not found or v_review.review_status in ('pending_review', 'in_review') then
    return query select p_source_document_id, v_run.id, v_run.status,
      coalesce(v_review.review_status, 'not_reviewed'), false, false, 'chunk_review_not_final'::text;
    return;
  end if;

  if v_review.review_status in ('accepted', 'accepted_with_warnings') then
    return query select p_source_document_id, v_run.id, v_run.status, v_review.review_status, true, false, null::text;
    return;
  end if;

  return query select p_source_document_id, v_run.id, v_run.status, v_review.review_status, false, false, v_review.review_status;
end;
$$;

revoke all on function get_document_embedding_readiness(uuid) from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
      create_document_chunking_review(uuid, uuid),
      assign_chunking_reviewer(uuid, uuid, uuid),
      claim_chunking_review(uuid, uuid),
      start_document_chunking_review(uuid, uuid),
      mark_chunk_reviewed(uuid, int, text, text, uuid),
      create_chunk_finding(uuid, text, text, text, int, text, text, uuid),
      update_chunk_finding_status(uuid, text, text, uuid),
      submit_document_chunking_review(uuid, text, text, text, text, uuid),
      reopen_chunking_review(uuid, text, uuid),
      invalidate_document_chunking_run(uuid, text, uuid),
      get_document_embedding_readiness(uuid)
      to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 8. Cascade: reopening/invalidating the upstream extraction review
--    invalidates any still-succeeded dependent chunking run — the same
--    cascade discipline S1-D2 added for OCR requests (migration 0011),
--    applied one layer further downstream. CREATE OR REPLACE of migration
--    0011's own already-overridden reopen_extraction_review (NOT 0009's
--    original — 0011 already added the OCR-request cascade block below;
--    this must be a superset of that, or it would silently revert 0011's
--    behavior. Verified against the actual installed function body, not
--    assumed — see supabase/tests/rls/011_controlled_ocr.sql TEST 21,
--    which caught exactly this class of regression during local
--    verification.) invalidate_extraction_review is NOT overridden by
--    0011, so its 0009 body is the correct base as-is.
-- ============================================================================

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

  -- Cascade (migration 0011): any OCR request tied to this extraction run
  -- that is still active (not already cancelled/invalidated) is now
  -- processing against a superseded review round.
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

  -- New cascade (S1-D3): a still-succeeded chunking run built on this
  -- extraction run is now built on stale input — invalidate it.
  update document_chunking_runs set
    status = 'invalidated', invalidated_at = now(),
    invalidation_reason = 'upstream extraction review was reopened'
    where organization_id = v_old.organization_id and extraction_run_id = v_old.extraction_run_id
      and status in ('succeeded', 'reused');

  return v_new;
end;
$$;

revoke all on function reopen_extraction_review(uuid, text, uuid) from public;

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

  -- New cascade (S1-D3): see reopen_extraction_review above.
  update document_chunking_runs set
    status = 'invalidated', invalidated_at = now(),
    invalidation_reason = 'upstream extraction review was invalidated'
    where organization_id = v_review.organization_id and extraction_run_id = v_review.extraction_run_id
      and status in ('succeeded', 'reused');

  insert into document_extraction_review_events (organization_id, extraction_review_id, extraction_run_id, event_type, from_status, to_status, actor_id, reason, correlation_id)
    values (v_review.organization_id, v_review.id, v_review.extraction_run_id, 'document_extraction_review.invalidated', v_review.review_status, 'invalidated', v_actor, p_reason, p_correlation_id);
  perform record_audit_event(v_review.organization_id, 'document_extraction_review.invalidated', 'document_extraction_review', v_review.id, p_correlation_id,
    jsonb_build_object('reason', p_reason));

  return v_review;
end;
$$;

revoke all on function invalidate_extraction_review(uuid, text, uuid) from public;

-- ============================================================================
-- End of migration 0013
-- ============================================================================
