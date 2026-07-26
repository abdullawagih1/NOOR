-- ============================================================================
-- Noor V1 — Migration 0005: Guideline Registry Schema and Lifecycle
-- Council: Database Agent + Clinical Safety Agent + Security Agent
-- ============================================================================
-- Sprint 1, first vertical slice. Establishes the controlled source-of-truth
-- registry for clinical guidelines:
--
--   Clinical Domain -> Guideline Authority -> Guideline -> Guideline Version
--     -> Clinical Review -> Approval -> Activation -> Supersession -> Withdrawal
--
-- Explicitly separate from document-processing (upload/OCR/parsing/chunking/
-- embeddings) — see ADR 0007. No file-processing workflow is implemented here.
--
-- Design decisions (see docs/database/guideline-registry-schema.md for the
-- full write-up):
--
--   1. Tenant integrity via composite foreign keys, not triggers, wherever
--      declarative composite FKs can express it (organization_id travels
--      alongside every parent reference). Triggers are used only where a
--      composite FK cannot express the rule (self-review prevention;
--      append-only enforcement).
--   2. Every write (create/update/review/lifecycle-transition) goes through
--      a narrow SECURITY DEFINER function that: resolves auth.uid(), checks
--      an organization-scoped permission, performs the write, and records an
--      audit_events row — atomically, in one Postgres call. No table in this
--      migration grants INSERT/UPDATE/DELETE to `authenticated` directly;
--      RLS + explicit REVOKEs make the functions the only write path. This
--      generalizes the "no partial writes" requirement (Sprint 1 mission §9)
--      to every mutation, not only lifecycle transitions, and avoids the
--      two-separate-HTTP-request consistency gap that a client-side RLS
--      write followed by a separate service-role audit write would have.
--   3. `guideline_versions.lifecycle_status` can ONLY be changed by
--      `transition_guideline_version()`. No table in this migration has an
--      UPDATE (or INSERT/DELETE) RLS policy for `authenticated` at all —
--      every write, draft edits included, is mediated by a SECURITY DEFINER
--      function (section 10), so a raw client PATCH/POST against these
--      tables is rejected by RLS before it can touch a row.
--   4. One active version per guideline is a partial unique index, not an
--      application check (Sprint 1 mission §7.4).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CLINICAL DOMAINS
-- ----------------------------------------------------------------------------

create table if not exists clinical_domains (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  unique (organization_id, code),
  unique (organization_id, id)
);

-- ----------------------------------------------------------------------------
-- 2. GUIDELINE AUTHORITIES
-- ----------------------------------------------------------------------------

create table if not exists guideline_authorities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  short_name text,
  authority_type text,
  country_or_region text,
  official_website text,
  -- Verification is an explicit clinical-governance decision, never inferred
  -- from the presence of a URL (Sprint 1 mission §7.2).
  is_verified boolean not null default false,
  verification_notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  unique (organization_id, name),
  unique (organization_id, id)
);

-- ----------------------------------------------------------------------------
-- 3. GUIDELINES (logical publication identity, spans versions)
-- ----------------------------------------------------------------------------

create table if not exists guidelines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  clinical_domain_id uuid not null,
  authority_id uuid not null,
  internal_code text not null,
  canonical_title text not null,
  short_title text,
  jurisdiction text,
  default_language text not null default 'en' check (default_language in ('en', 'ar')),
  description text,
  -- FK added below, after guideline_versions exists (circular reference).
  current_active_version_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  archived_at timestamptz,
  unique (organization_id, internal_code),
  unique (organization_id, id),
  foreign key (organization_id, clinical_domain_id) references clinical_domains (organization_id, id),
  foreign key (organization_id, authority_id) references guideline_authorities (organization_id, id)
);

create index if not exists idx_guidelines_org_domain on guidelines (organization_id, clinical_domain_id);
create index if not exists idx_guidelines_org_authority on guidelines (organization_id, authority_id);

-- ----------------------------------------------------------------------------
-- 4. GUIDELINE VERSIONS (the clinical publication lifecycle — see ADR 0007)
-- ----------------------------------------------------------------------------

create table if not exists guideline_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  guideline_id uuid not null,
  version_label text not null,
  edition text,
  publication_date date,
  effective_date date,
  review_due_date date,
  expiry_date date,
  language text not null default 'en' check (language in ('en', 'ar')),
  source_url text,
  external_identifier text,

  -- Registry-only metadata. No file/processing reference exists on this
  -- table by design — see ADR 0007.
  evidence_scope text,
  target_population text,
  excluded_population text,
  methodology_summary text,
  notes text,

  lifecycle_status text not null default 'draft'
    check (lifecycle_status in ('draft', 'ready_for_review', 'approved', 'active', 'superseded', 'withdrawn')),

  -- Supersession lineage: which version (of the SAME guideline) this one
  -- replaces. Enforced by the composite FK below, not a trigger.
  supersedes_version_id uuid,

  approved_at timestamptz,
  approved_by uuid references auth.users(id),
  activated_at timestamptz,
  activated_by uuid references auth.users(id),
  superseded_at timestamptz,
  superseded_by uuid references auth.users(id),
  withdrawn_at timestamptz,
  withdrawn_by uuid references auth.users(id),
  withdrawal_reason text,

  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),

  unique (guideline_id, version_label),
  -- Both composite uniques are needed as FK targets: (guideline_id, id) for
  -- same-guideline supersession + the guidelines->versions reverse FK;
  -- (organization_id, id) for reviews/lifecycle-events FKs and the
  -- guidelines.current_active_version_id FK.
  unique (guideline_id, id),
  unique (organization_id, id),

  foreign key (organization_id, guideline_id) references guidelines (organization_id, id),
  -- Same-guideline-only supersession, declaratively — no trigger needed.
  -- Organization equality follows transitively: this version's org must
  -- match its guideline_id's org (FK above), and the superseded version's
  -- org must match the SAME guideline_id's org (same FK on that row), so
  -- cross-tenant supersession is structurally impossible.
  foreign key (guideline_id, supersedes_version_id) references guideline_versions (guideline_id, id),

  check (supersedes_version_id is null or supersedes_version_id <> id),
  check (effective_date is null or publication_date is null or effective_date >= publication_date),
  check (expiry_date is null or effective_date is null or expiry_date > effective_date),
  check (lifecycle_status <> 'withdrawn' or withdrawal_reason is not null)
);

-- One active version per guideline — a database guarantee, not an
-- application check (Sprint 1 mission §7.4).
create unique index if not exists guideline_versions_one_active_per_guideline
  on guideline_versions (guideline_id)
  where lifecycle_status = 'active';

create index if not exists idx_guideline_versions_guideline_status on guideline_versions (guideline_id, lifecycle_status);
create index if not exists idx_guideline_versions_org_status on guideline_versions (organization_id, lifecycle_status);

-- Close the circular reference: current_active_version_id must be a version
-- of THIS guideline (composite FK against guideline_versions(guideline_id, id)).
alter table guidelines
  add constraint guidelines_current_active_version_fk
  foreign key (id, current_active_version_id) references guideline_versions (guideline_id, id);

-- ----------------------------------------------------------------------------
-- 5. GUIDELINE REVIEWS (append-only clinical review decisions)
-- ----------------------------------------------------------------------------

create table if not exists guideline_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  guideline_version_id uuid not null,
  reviewer_id uuid not null references auth.users(id),
  review_status text not null check (review_status in ('pending', 'changes_requested', 'recommended_for_approval', 'rejected')),
  clinical_comments text,
  safety_concerns text,
  requested_changes text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, guideline_version_id) references guideline_versions (organization_id, id)
);

create index if not exists idx_guideline_reviews_version on guideline_reviews (guideline_version_id, created_at desc);

-- ----------------------------------------------------------------------------
-- 6. GUIDELINE LIFECYCLE EVENTS (append-only history; integrates with audit_events)
-- ----------------------------------------------------------------------------

create table if not exists guideline_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  guideline_version_id uuid not null,
  from_status text,
  to_status text not null,
  reason text,
  actor_id uuid references auth.users(id),
  correlation_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (organization_id, guideline_version_id) references guideline_versions (organization_id, id)
);

create index if not exists idx_lifecycle_events_version on guideline_lifecycle_events (guideline_version_id, created_at desc);
create index if not exists idx_lifecycle_events_correlation on guideline_lifecycle_events (correlation_id);

-- ============================================================================
-- 7. PERMISSIONS
-- ============================================================================

insert into permissions (key, description) values
  ('guidelines.read_active', 'Read active, approved guideline versions'),
  ('guidelines.read_all', 'Read guidelines and versions in any lifecycle state'),
  ('guidelines.create', 'Create new guidelines and guideline versions'),
  ('guidelines.update_draft', 'Edit guideline and guideline-version metadata while in draft'),
  ('guidelines.submit_for_review', 'Submit a draft guideline version for clinical review'),
  ('guidelines.review', 'Submit a clinical review decision on a guideline version'),
  ('guidelines.approve', 'Approve a reviewed guideline version'),
  ('guidelines.activate', 'Activate an approved guideline version'),
  ('guidelines.supersede', 'Manually supersede an active guideline version'),
  ('guidelines.withdraw', 'Withdraw a guideline version from use'),
  ('guideline_authorities.manage', 'Create and manage guideline authorities'),
  ('clinical_domains.manage', 'Create and manage clinical domains')
on conflict (key) do nothing;

-- Role -> permission mapping (Sprint 1 mission §10, extended to also use the
-- existing `knowledge_manager` role — declared in 0001 specifically for
-- "registers and manages guideline documents" — for the authoring
-- permissions, in addition to organization_admin as the mission's suggested
-- baseline lists. `safety_officer` additionally gets guidelines.withdraw,
-- consistent with its documented purpose ("owns incident response and
-- emergency shutdown") — a Clinical Safety Agent extension beyond the
-- mission's literal suggested table, recorded here for transparency.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from (values
  ('clinician', 'guidelines.read_active'),
  ('clinical_pharmacist', 'guidelines.read_active'),
  ('clinical_reviewer', 'guidelines.read_all'),
  ('clinical_reviewer', 'guidelines.review'),
  ('knowledge_manager', 'guidelines.read_all'),
  ('knowledge_manager', 'guidelines.create'),
  ('knowledge_manager', 'guidelines.update_draft'),
  ('knowledge_manager', 'guidelines.submit_for_review'),
  ('knowledge_manager', 'guideline_authorities.manage'),
  ('knowledge_manager', 'clinical_domains.manage'),
  ('quality_manager', 'guidelines.read_all'),
  ('quality_manager', 'guidelines.approve'),
  ('quality_manager', 'guidelines.activate'),
  ('quality_manager', 'guidelines.supersede'),
  ('quality_manager', 'guidelines.withdraw'),
  ('safety_officer', 'guidelines.read_all'),
  ('safety_officer', 'guidelines.withdraw'),
  ('organization_admin', 'guidelines.read_all'),
  ('organization_admin', 'guidelines.create'),
  ('organization_admin', 'guidelines.update_draft'),
  ('organization_admin', 'guidelines.submit_for_review'),
  ('organization_admin', 'guideline_authorities.manage'),
  ('organization_admin', 'clinical_domains.manage'),
  ('auditor', 'guidelines.read_all')
) as mapping(role_key, permission_key)
join roles r on r.key = mapping.role_key
join permissions p on p.key = mapping.permission_key
on conflict (role_id, permission_id) do nothing;

-- ============================================================================
-- 8. RLS
-- ============================================================================

alter table clinical_domains enable row level security;
alter table guideline_authorities enable row level security;
alter table guidelines enable row level security;
alter table guideline_versions enable row level security;
alter table guideline_reviews enable row level security;
alter table guideline_lifecycle_events enable row level security;

-- Read paths are ordinary RLS SELECT policies. Every write goes through the
-- SECURITY DEFINER functions in section 10 — no INSERT/UPDATE/DELETE policy
-- exists on any of these six tables for `authenticated` (see section 9 for
-- the accompanying explicit REVOKE, since Supabase's default privileges
-- would otherwise grant `authenticated` full table-level CRUD).

create policy clinical_domains_select_member on clinical_domains
  for select using (organization_id in (select current_active_organization_ids()));

create policy guideline_authorities_select_member on guideline_authorities
  for select using (organization_id in (select current_active_organization_ids()));

create policy guidelines_select_member on guidelines
  for select using (organization_id in (select current_active_organization_ids()));

-- Clinicians (and anyone without guidelines.read_all) see ONLY active
-- versions. Privileged roles (reviewer/quality/admin/auditor) see every
-- lifecycle state via the second, additional permissive policy.
create policy guideline_versions_select_active_for_members on guideline_versions
  for select using (
    organization_id in (select current_active_organization_ids())
    and lifecycle_status = 'active'
  );

create policy guideline_versions_select_all_for_privileged on guideline_versions
  for select using (has_permission_in_organization(organization_id, 'guidelines.read_all'));

create policy guideline_reviews_select_privileged on guideline_reviews
  for select using (
    has_permission_in_organization(organization_id, 'guidelines.read_all')
    or has_permission_in_organization(organization_id, 'guidelines.review')
    or reviewer_id = auth.uid()
  );

create policy guideline_lifecycle_events_select_privileged on guideline_lifecycle_events
  for select using (
    has_permission_in_organization(organization_id, 'guidelines.read_all')
    or has_permission_in_organization(organization_id, 'audit.read')
  );

-- ============================================================================
-- 9. GRANTS — explicit, matching the SECURITY DEFINER-only write model
-- ============================================================================
-- Guarded exactly like 0004's anon-hardening: on the hosted project the
-- `authenticated` role always exists (Supabase-provisioned) and already has
-- broad default-privilege table grants, which must be narrowed here. In the
-- CI plain-Postgres container, `authenticated` does not exist until the RLS
-- test files create it — this block is then a documented no-op, and the
-- test file grants SELECT-only explicitly, mirroring production.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select on clinical_domains, guideline_authorities, guidelines,
      guideline_versions, guideline_reviews, guideline_lifecycle_events
      to authenticated;
    revoke insert, update, delete on clinical_domains, guideline_authorities,
      guidelines, guideline_versions, guideline_reviews, guideline_lifecycle_events
      from authenticated;
  end if;
end
$$;

-- ============================================================================
-- 10. FUNCTIONS
-- ============================================================================
-- Every client-facing function below is created with `revoke all ... from
-- public` immediately after its definition (safe at migration-apply time on
-- both plain Postgres and hosted, since the PUBLIC pseudo-role always
-- exists). The matching `grant execute ... to authenticated` is deliberately
-- NOT issued inline — at CI's plain-Postgres migration-apply time the
-- `authenticated` role does not exist yet (it's created later by the RLS
-- test files), so an inline grant would fail the migration outright. All
-- ten EXECUTE grants are instead consolidated into ONE guarded block at the
-- end of this section (10.8), using the same `if exists (select 1 from
-- pg_roles where rolname = 'authenticated')` guard as section 9.

-- ----------------------------------------------------------------------------
-- 10.1 Internal helpers (not directly callable by clients)
-- ----------------------------------------------------------------------------

create or replace function assert_permission(p_organization_id uuid, p_permission_key text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_permission_in_organization(p_organization_id, p_permission_key) then
    raise exception 'permission denied: % required in organization %', p_permission_key, p_organization_id
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function assert_permission(uuid, text) from public;

create or replace function record_audit_event(
  p_organization_id uuid,
  p_event_type text,
  p_resource_type text,
  p_resource_id uuid,
  p_correlation_id uuid,
  p_metadata jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into audit_events (organization_id, actor_id, correlation_id, event_type, resource_type, resource_id, metadata)
  values (p_organization_id, auth.uid(), p_correlation_id, p_event_type, p_resource_type, p_resource_id, p_metadata);
end;
$$;

revoke all on function record_audit_event(uuid, text, text, uuid, uuid, jsonb) from public;

-- ----------------------------------------------------------------------------
-- 10.2 Clinical domains
-- ----------------------------------------------------------------------------

create or replace function create_clinical_domain(
  p_organization_id uuid, p_code text, p_name text, p_description text default null
) returns clinical_domains
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row clinical_domains%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  perform assert_permission(p_organization_id, 'clinical_domains.manage');

  insert into clinical_domains (organization_id, code, name, description, created_by, updated_by)
  values (p_organization_id, p_code, p_name, p_description, v_actor, v_actor)
  returning * into v_row;

  perform record_audit_event(p_organization_id, 'clinical_domain.created', 'clinical_domain', v_row.id, gen_random_uuid(),
    jsonb_build_object('code', p_code));

  return v_row;
end;
$$;

revoke all on function create_clinical_domain(uuid, text, text, text) from public;

create or replace function update_clinical_domain(
  p_id uuid, p_name text default null, p_description text default null, p_is_active boolean default null
) returns clinical_domains
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row clinical_domains%rowtype;
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select organization_id into v_org from clinical_domains where id = p_id;
  if v_org is null then
    raise exception 'clinical domain not found: %', p_id;
  end if;
  perform assert_permission(v_org, 'clinical_domains.manage');

  update clinical_domains set
    name = coalesce(p_name, name),
    description = coalesce(p_description, description),
    is_active = coalesce(p_is_active, is_active),
    updated_at = now(), updated_by = v_actor
  where id = p_id
  returning * into v_row;

  perform record_audit_event(v_org, 'clinical_domain.updated', 'clinical_domain', p_id, gen_random_uuid(), '{}'::jsonb);

  return v_row;
end;
$$;

revoke all on function update_clinical_domain(uuid, text, text, boolean) from public;

-- ----------------------------------------------------------------------------
-- 10.3 Guideline authorities
-- ----------------------------------------------------------------------------

create or replace function create_guideline_authority(
  p_organization_id uuid, p_name text, p_short_name text default null,
  p_authority_type text default null, p_country_or_region text default null,
  p_official_website text default null, p_is_verified boolean default false,
  p_verification_notes text default null
) returns guideline_authorities
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row guideline_authorities%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  perform assert_permission(p_organization_id, 'guideline_authorities.manage');

  insert into guideline_authorities (
    organization_id, name, short_name, authority_type, country_or_region,
    official_website, is_verified, verification_notes, created_by, updated_by
  ) values (
    p_organization_id, p_name, p_short_name, p_authority_type, p_country_or_region,
    p_official_website, coalesce(p_is_verified, false), p_verification_notes, v_actor, v_actor
  )
  returning * into v_row;

  perform record_audit_event(p_organization_id, 'guideline_authority.created', 'guideline_authority', v_row.id, gen_random_uuid(),
    jsonb_build_object('name', p_name, 'is_verified', coalesce(p_is_verified, false)));

  return v_row;
end;
$$;

revoke all on function create_guideline_authority(uuid, text, text, text, text, text, boolean, text) from public;

create or replace function update_guideline_authority(
  p_id uuid, p_name text default null, p_short_name text default null,
  p_authority_type text default null, p_country_or_region text default null,
  p_official_website text default null, p_is_verified boolean default null,
  p_verification_notes text default null
) returns guideline_authorities
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row guideline_authorities%rowtype;
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select organization_id into v_org from guideline_authorities where id = p_id;
  if v_org is null then
    raise exception 'guideline authority not found: %', p_id;
  end if;
  perform assert_permission(v_org, 'guideline_authorities.manage');

  update guideline_authorities set
    name = coalesce(p_name, name),
    short_name = coalesce(p_short_name, short_name),
    authority_type = coalesce(p_authority_type, authority_type),
    country_or_region = coalesce(p_country_or_region, country_or_region),
    official_website = coalesce(p_official_website, official_website),
    is_verified = coalesce(p_is_verified, is_verified),
    verification_notes = coalesce(p_verification_notes, verification_notes),
    updated_at = now(), updated_by = v_actor
  where id = p_id
  returning * into v_row;

  perform record_audit_event(v_org, 'guideline_authority.updated', 'guideline_authority', p_id, gen_random_uuid(), '{}'::jsonb);

  return v_row;
end;
$$;

revoke all on function update_guideline_authority(uuid, text, text, text, text, text, boolean, text) from public;

-- ----------------------------------------------------------------------------
-- 10.4 Guidelines
-- ----------------------------------------------------------------------------

create or replace function create_guideline(
  p_organization_id uuid, p_clinical_domain_id uuid, p_authority_id uuid,
  p_internal_code text, p_canonical_title text, p_short_title text default null,
  p_jurisdiction text default null, p_default_language text default 'en', p_description text default null
) returns guidelines
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row guidelines%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  perform assert_permission(p_organization_id, 'guidelines.create');

  insert into guidelines (
    organization_id, clinical_domain_id, authority_id, internal_code, canonical_title,
    short_title, jurisdiction, default_language, description, created_by, updated_by
  ) values (
    p_organization_id, p_clinical_domain_id, p_authority_id, p_internal_code, p_canonical_title,
    p_short_title, p_jurisdiction, coalesce(p_default_language, 'en'), p_description, v_actor, v_actor
  )
  returning * into v_row;

  perform record_audit_event(p_organization_id, 'guideline.created', 'guideline', v_row.id, gen_random_uuid(),
    jsonb_build_object('internal_code', p_internal_code));

  return v_row;
end;
$$;

revoke all on function create_guideline(uuid, uuid, uuid, text, text, text, text, text, text) from public;

create or replace function update_guideline_draft(
  p_id uuid, p_canonical_title text default null, p_short_title text default null,
  p_jurisdiction text default null, p_description text default null
) returns guidelines
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row guidelines%rowtype;
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select organization_id into v_org from guidelines where id = p_id;
  if v_org is null then
    raise exception 'guideline not found: %', p_id;
  end if;
  perform assert_permission(v_org, 'guidelines.update_draft');

  update guidelines set
    canonical_title = coalesce(p_canonical_title, canonical_title),
    short_title = coalesce(p_short_title, short_title),
    jurisdiction = coalesce(p_jurisdiction, jurisdiction),
    description = coalesce(p_description, description),
    updated_at = now(), updated_by = v_actor
  where id = p_id
  returning * into v_row;

  perform record_audit_event(v_org, 'guideline.updated', 'guideline', p_id, gen_random_uuid(), '{}'::jsonb);

  return v_row;
end;
$$;

revoke all on function update_guideline_draft(uuid, text, text, text, text) from public;

-- ----------------------------------------------------------------------------
-- 10.5 Guideline versions
-- ----------------------------------------------------------------------------

create or replace function create_guideline_version(
  p_guideline_id uuid, p_version_label text, p_edition text default null,
  p_publication_date date default null, p_effective_date date default null,
  p_review_due_date date default null, p_expiry_date date default null,
  p_language text default 'en', p_source_url text default null, p_external_identifier text default null,
  p_evidence_scope text default null, p_target_population text default null,
  p_excluded_population text default null, p_methodology_summary text default null, p_notes text default null
) returns guideline_versions
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row guideline_versions%rowtype;
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select organization_id into v_org from guidelines where id = p_guideline_id;
  if v_org is null then
    raise exception 'guideline not found: %', p_guideline_id;
  end if;
  perform assert_permission(v_org, 'guidelines.create');

  insert into guideline_versions (
    organization_id, guideline_id, version_label, edition, publication_date, effective_date,
    review_due_date, expiry_date, language, source_url, external_identifier,
    evidence_scope, target_population, excluded_population, methodology_summary, notes,
    lifecycle_status, created_by, updated_by
  ) values (
    v_org, p_guideline_id, p_version_label, p_edition, p_publication_date, p_effective_date,
    p_review_due_date, p_expiry_date, coalesce(p_language, 'en'), p_source_url, p_external_identifier,
    p_evidence_scope, p_target_population, p_excluded_population, p_methodology_summary, p_notes,
    'draft', v_actor, v_actor
  )
  returning * into v_row;

  perform record_audit_event(v_org, 'guideline_version.created', 'guideline_version', v_row.id, gen_random_uuid(),
    jsonb_build_object('version_label', p_version_label, 'guideline_id', p_guideline_id));

  return v_row;
end;
$$;

revoke all on function create_guideline_version(uuid, text, text, date, date, date, date, text, text, text, text, text, text, text, text) from public;

create or replace function update_guideline_version_draft(
  p_id uuid, p_edition text default null, p_publication_date date default null,
  p_effective_date date default null, p_review_due_date date default null, p_expiry_date date default null,
  p_source_url text default null, p_external_identifier text default null,
  p_evidence_scope text default null, p_target_population text default null,
  p_excluded_population text default null, p_methodology_summary text default null, p_notes text default null
) returns guideline_versions
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_row guideline_versions%rowtype;
  v_org uuid;
  v_status text;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select organization_id, lifecycle_status into v_org, v_status from guideline_versions where id = p_id;
  if v_org is null then
    raise exception 'guideline version not found: %', p_id;
  end if;
  perform assert_permission(v_org, 'guidelines.update_draft');

  if v_status <> 'draft' then
    raise exception 'only draft versions can be edited (current status: %)', v_status;
  end if;

  update guideline_versions set
    edition = coalesce(p_edition, edition),
    publication_date = coalesce(p_publication_date, publication_date),
    effective_date = coalesce(p_effective_date, effective_date),
    review_due_date = coalesce(p_review_due_date, review_due_date),
    expiry_date = coalesce(p_expiry_date, expiry_date),
    source_url = coalesce(p_source_url, source_url),
    external_identifier = coalesce(p_external_identifier, external_identifier),
    evidence_scope = coalesce(p_evidence_scope, evidence_scope),
    target_population = coalesce(p_target_population, target_population),
    excluded_population = coalesce(p_excluded_population, excluded_population),
    methodology_summary = coalesce(p_methodology_summary, methodology_summary),
    notes = coalesce(p_notes, notes),
    updated_at = now(), updated_by = v_actor
  where id = p_id
  returning * into v_row;

  perform record_audit_event(v_org, 'guideline_version.updated', 'guideline_version', p_id, gen_random_uuid(), '{}'::jsonb);

  return v_row;
end;
$$;

revoke all on function update_guideline_version_draft(uuid, text, date, date, date, date, text, text, text, text, text, text, text) from public;

-- ----------------------------------------------------------------------------
-- 10.6 Clinical review
-- ----------------------------------------------------------------------------

-- Defense in depth: enforced again inside submit_guideline_review(), but a
-- trigger closes the gap for ANY insert path, matching the audit_events
-- trigger philosophy (0002) of not relying solely on the function layer.
create or replace function prevent_self_review()
returns trigger
language plpgsql
as $$
declare
  v_creator uuid;
begin
  select created_by into v_creator from guideline_versions where id = new.guideline_version_id;
  if v_creator is not null and v_creator = new.reviewer_id then
    raise exception 'a guideline version cannot be reviewed by its own creator' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_self_review on guideline_reviews;
create trigger trg_prevent_self_review
  before insert on guideline_reviews
  for each row execute function prevent_self_review();

create or replace function submit_guideline_review(
  p_guideline_version_id uuid,
  p_review_status text,
  p_clinical_comments text default null,
  p_safety_concerns text default null,
  p_requested_changes text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns guideline_reviews
language plpgsql security definer set search_path = public as $$
declare
  v_version guideline_versions%rowtype;
  v_actor uuid := auth.uid();
  v_review guideline_reviews%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_review_status not in ('pending', 'changes_requested', 'recommended_for_approval', 'rejected') then
    raise exception 'invalid review status: %', p_review_status;
  end if;

  select * into v_version from guideline_versions where id = p_guideline_version_id;
  if not found then
    raise exception 'guideline version not found: %', p_guideline_version_id;
  end if;

  perform assert_permission(v_version.organization_id, 'guidelines.review');

  if v_version.lifecycle_status <> 'ready_for_review' then
    raise exception 'reviews can only be submitted while a version is ready_for_review (current status: %)', v_version.lifecycle_status;
  end if;

  if v_version.created_by = v_actor then
    raise exception 'a guideline version cannot be reviewed by its own creator' using errcode = '42501';
  end if;

  insert into guideline_reviews (
    organization_id, guideline_version_id, reviewer_id, review_status,
    clinical_comments, safety_concerns, requested_changes, reviewed_at
  ) values (
    v_version.organization_id, p_guideline_version_id, v_actor, p_review_status,
    p_clinical_comments, p_safety_concerns, p_requested_changes, now()
  )
  returning * into v_review;

  perform record_audit_event(v_version.organization_id, 'guideline_review.submitted', 'guideline_version', p_guideline_version_id, p_correlation_id,
    jsonb_build_object('review_status', p_review_status, 'guideline_id', v_version.guideline_id));

  return v_review;
end;
$$;

revoke all on function submit_guideline_review(uuid, text, text, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.7 Lifecycle transition engine (Sprint 1 mission §9)
-- ----------------------------------------------------------------------------
-- Single canonical, transaction-safe entry point for every clinical-status
-- change. Allowed transitions (Sprint 1 mission §8):
--
--   draft            -> ready_for_review
--   ready_for_review -> draft            (requires reason)
--   ready_for_review -> approved         (requires a recommending review; blocks self-approval)
--   approved         -> draft            (explicit revocation; requires reason)
--   approved         -> active           (supersedes the prior active version, if any, transactionally)
--   active           -> superseded       (manual; clears current_active_version_id)
--   active           -> withdrawn        (requires reason; clears current_active_version_id)
--   superseded       -> withdrawn        (requires reason)
--
-- Every other (from, to) pair raises "illegal lifecycle transition" — this
-- includes draft->active, ready_for_review->active, withdrawn->active,
-- superseded->active, and any jump that skips review/approval.

create or replace function transition_guideline_version(
  p_version_id uuid,
  p_target_status text,
  p_reason text default null,
  p_correlation_id uuid default gen_random_uuid()
) returns guideline_versions
language plpgsql security definer set search_path = public as $$
declare
  v_version guideline_versions%rowtype;
  v_guideline guidelines%rowtype;
  v_actor uuid := auth.uid();
  v_from_status text;
  v_prior_active_id uuid;
  v_has_recommendation boolean;
begin
  if v_actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_target_status not in ('draft', 'ready_for_review', 'approved', 'active', 'superseded', 'withdrawn') then
    raise exception 'invalid target status: %', p_target_status;
  end if;

  -- Lock the version row before validating (Sprint 1 mission §9 step 4).
  select * into v_version from guideline_versions where id = p_version_id for update;
  if not found then
    raise exception 'guideline version not found: %', p_version_id;
  end if;

  v_from_status := v_version.lifecycle_status;

  select * into v_guideline from guidelines where id = v_version.guideline_id for update;

  -- ---- Validate the requested transition -----------------------------
  if v_from_status = 'draft' and p_target_status = 'ready_for_review' then
    perform assert_permission(v_version.organization_id, 'guidelines.submit_for_review');

  elsif v_from_status = 'ready_for_review' and p_target_status = 'draft' then
    if not (
      has_permission_in_organization(v_version.organization_id, 'guidelines.review')
      or has_permission_in_organization(v_version.organization_id, 'guidelines.submit_for_review')
    ) then
      raise exception 'permission denied: guidelines.review or guidelines.submit_for_review required' using errcode = '42501';
    end if;
    if p_reason is null or btrim(p_reason) = '' then
      raise exception 'a reason is required to return a version to draft';
    end if;

  elsif v_from_status = 'ready_for_review' and p_target_status = 'approved' then
    perform assert_permission(v_version.organization_id, 'guidelines.approve');
    if v_version.created_by = v_actor then
      raise exception 'self-approval is not permitted: the version author cannot approve their own version' using errcode = '42501';
    end if;
    select exists (
      select 1 from guideline_reviews
      where guideline_version_id = p_version_id
        and review_status = 'recommended_for_approval'
    ) into v_has_recommendation;
    if not v_has_recommendation then
      raise exception 'approval requires at least one review recommending approval';
    end if;

  elsif v_from_status = 'approved' and p_target_status = 'draft' then
    perform assert_permission(v_version.organization_id, 'guidelines.approve');
    if p_reason is null or btrim(p_reason) = '' then
      raise exception 'a reason is required to revoke an approval';
    end if;

  elsif v_from_status = 'approved' and p_target_status = 'active' then
    perform assert_permission(v_version.organization_id, 'guidelines.activate');

  elsif v_from_status = 'active' and p_target_status = 'superseded' then
    perform assert_permission(v_version.organization_id, 'guidelines.supersede');

  elsif v_from_status = 'active' and p_target_status = 'withdrawn' then
    perform assert_permission(v_version.organization_id, 'guidelines.withdraw');
    if p_reason is null or btrim(p_reason) = '' then
      raise exception 'a withdrawal reason is required';
    end if;

  elsif v_from_status = 'superseded' and p_target_status = 'withdrawn' then
    perform assert_permission(v_version.organization_id, 'guidelines.withdraw');
    if p_reason is null or btrim(p_reason) = '' then
      raise exception 'a withdrawal reason is required';
    end if;

  else
    raise exception 'illegal lifecycle transition: % -> %', v_from_status, p_target_status;
  end if;

  -- ---- Apply the transition -------------------------------------------
  if p_target_status = 'approved' then
    update guideline_versions
      set lifecycle_status = 'approved', approved_at = now(), approved_by = v_actor,
          updated_at = now(), updated_by = v_actor
      where id = p_version_id
      returning * into v_version;

  elsif p_target_status = 'active' then
    v_prior_active_id := v_guideline.current_active_version_id;

    if v_prior_active_id is not null and v_prior_active_id <> p_version_id then
      update guideline_versions
        set lifecycle_status = 'superseded', superseded_at = now(), superseded_by = v_actor,
            updated_at = now(), updated_by = v_actor
        where id = v_prior_active_id;

      insert into guideline_lifecycle_events (
        organization_id, guideline_version_id, from_status, to_status, reason, actor_id, correlation_id, metadata
      ) values (
        v_version.organization_id, v_prior_active_id, 'active', 'superseded',
        'superseded by activation of version ' || v_version.version_label, v_actor, p_correlation_id,
        jsonb_build_object('superseded_by_version_id', p_version_id)
      );

      perform record_audit_event(v_version.organization_id, 'guideline_version.superseded', 'guideline_version', v_prior_active_id, p_correlation_id,
        jsonb_build_object('superseded_by_version_id', p_version_id, 'guideline_id', v_version.guideline_id));
    end if;

    update guideline_versions
      set lifecycle_status = 'active', activated_at = now(), activated_by = v_actor,
          supersedes_version_id = coalesce(supersedes_version_id, v_prior_active_id),
          updated_at = now(), updated_by = v_actor
      where id = p_version_id
      returning * into v_version;

    update guidelines set current_active_version_id = p_version_id, updated_at = now(), updated_by = v_actor
      where id = v_version.guideline_id;

  elsif p_target_status = 'superseded' then
    update guideline_versions
      set lifecycle_status = 'superseded', superseded_at = now(), superseded_by = v_actor,
          updated_at = now(), updated_by = v_actor
      where id = p_version_id
      returning * into v_version;

    if v_guideline.current_active_version_id = p_version_id then
      update guidelines set current_active_version_id = null, updated_at = now(), updated_by = v_actor
        where id = v_version.guideline_id;
    end if;

  elsif p_target_status = 'withdrawn' then
    update guideline_versions
      set lifecycle_status = 'withdrawn', withdrawn_at = now(), withdrawn_by = v_actor,
          withdrawal_reason = p_reason, updated_at = now(), updated_by = v_actor
      where id = p_version_id
      returning * into v_version;

    if v_guideline.current_active_version_id = p_version_id then
      update guidelines set current_active_version_id = null, updated_at = now(), updated_by = v_actor
        where id = v_version.guideline_id;
    end if;

  else
    -- draft <-> ready_for_review, and approved -> draft (revocation, which
    -- also clears the now-invalid approval markers).
    update guideline_versions
      set lifecycle_status = p_target_status,
          approved_at = case when p_target_status = 'draft' then null else approved_at end,
          approved_by = case when p_target_status = 'draft' then null else approved_by end,
          updated_at = now(), updated_by = v_actor
      where id = p_version_id
      returning * into v_version;
  end if;

  insert into guideline_lifecycle_events (
    organization_id, guideline_version_id, from_status, to_status, reason, actor_id, correlation_id, metadata
  ) values (
    v_version.organization_id, p_version_id, v_from_status, p_target_status, p_reason, v_actor, p_correlation_id, '{}'::jsonb
  );

  perform record_audit_event(
    v_version.organization_id,
    'guideline_version.' || case p_target_status
      when 'ready_for_review' then 'submitted_for_review'
      when 'approved' then 'approved'
      when 'active' then 'activated'
      when 'superseded' then 'superseded'
      when 'withdrawn' then 'withdrawn'
      when 'draft' then 'returned_to_draft'
      else p_target_status
    end,
    'guideline_version', p_version_id, p_correlation_id,
    jsonb_build_object('from_status', v_from_status, 'to_status', p_target_status, 'guideline_id', v_version.guideline_id)
  );

  return v_version;
end;
$$;

revoke all on function transition_guideline_version(uuid, text, text, uuid) from public;

-- ----------------------------------------------------------------------------
-- 10.8 Consolidated EXECUTE grants (guarded — see the note at the top of
-- section 10). `assert_permission` and `record_audit_event` are
-- deliberately NOT granted here: they are internal helpers only ever
-- called from inside another SECURITY DEFINER function (where they run
-- with the function owner's privileges regardless of what the original
-- caller has been granted), never invoked directly by a client.
-- ----------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function
      create_clinical_domain(uuid, text, text, text),
      update_clinical_domain(uuid, text, text, boolean),
      create_guideline_authority(uuid, text, text, text, text, text, boolean, text),
      update_guideline_authority(uuid, text, text, text, text, text, boolean, text),
      create_guideline(uuid, uuid, uuid, text, text, text, text, text, text),
      update_guideline_draft(uuid, text, text, text, text),
      create_guideline_version(uuid, text, text, date, date, date, date, text, text, text, text, text, text, text, text),
      update_guideline_version_draft(uuid, text, date, date, date, date, text, text, text, text, text, text, text),
      submit_guideline_review(uuid, text, text, text, text, uuid),
      transition_guideline_version(uuid, text, text, uuid)
      to authenticated;
  end if;
end
$$;

-- ============================================================================
-- 11. APPEND-ONLY ENFORCEMENT (guideline_reviews, guideline_lifecycle_events)
-- ============================================================================
-- Same pattern as 0002's audit_events hardening: REVOKE alone protects every
-- normal application role but not the table owner / service_role, so a
-- trigger backstop closes that gap too. Reuses the SAME documented override
-- GUC (`noor.allow_audit_maintenance`) rather than inventing a second
-- maintenance procedure — see docs/database/schema.md.

revoke update, delete on guideline_reviews from public;
revoke update, delete on guideline_lifecycle_events from public;

create or replace function prevent_guideline_registry_history_mutation()
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

drop trigger if exists trg_guideline_reviews_no_update on guideline_reviews;
create trigger trg_guideline_reviews_no_update
  before update on guideline_reviews
  for each row execute function prevent_guideline_registry_history_mutation();

drop trigger if exists trg_guideline_reviews_no_delete on guideline_reviews;
create trigger trg_guideline_reviews_no_delete
  before delete on guideline_reviews
  for each row execute function prevent_guideline_registry_history_mutation();

drop trigger if exists trg_guideline_lifecycle_events_no_update on guideline_lifecycle_events;
create trigger trg_guideline_lifecycle_events_no_update
  before update on guideline_lifecycle_events
  for each row execute function prevent_guideline_registry_history_mutation();

drop trigger if exists trg_guideline_lifecycle_events_no_delete on guideline_lifecycle_events;
create trigger trg_guideline_lifecycle_events_no_delete
  before delete on guideline_lifecycle_events
  for each row execute function prevent_guideline_registry_history_mutation();

-- ============================================================================
-- 12. DEVELOPMENT SEED (explicitly pending human clinical confirmation)
-- ============================================================================
-- No default clinical domain is inserted by this migration. Seeding a
-- specific domain (e.g. Adult Hypertension) into synthetic Development test
-- organizations, if desired, belongs in supabase/seed.sql / hosted-test
-- scripts — never in a migration applied to every environment including a
-- future Production project — and remains explicitly pending clinical
-- confirmation (see PROJECT_STATE.md gap G-03).

-- ============================================================================
-- End of migration 0005
-- ============================================================================
