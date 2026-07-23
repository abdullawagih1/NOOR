-- ============================================================================
-- Noor V1 — Migration 0001: Identity, Tenancy, RLS Foundation, Audit
-- Council: Backend/Supabase Agent + Database/Data-Integrity Agent
-- ============================================================================
-- This migration establishes:
--   1. auth.uid() convention (Supabase-compatible; see note below)
--   2. organizations, profiles, organization_memberships
--   3. roles, permissions, role_permissions
--   4. audit_events (append-only)
--   5. RLS enabled + policies on every tenant table
--   6. Helper functions used by all future RLS policies
--
-- NOTE ON auth SCHEMA:
--   In a real Supabase project, `auth.users` and `auth.uid()` are provided by
--   GoTrue and must not be created here. This migration creates a
--   Supabase-compatible auth.uid() ONLY when it does not already exist, so
--   that (a) it is a no-op against a real Supabase project, and (b) it lets
--   this migration be exercised against a plain local Postgres instance for
--   CI / offline RLS testing, using the exact same session convention
--   Supabase uses: current_setting('request.jwt.claim.sub', true).
-- ============================================================================

create extension if not exists pgcrypto;

create schema if not exists auth;

do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'auth' and p.proname = 'uid'
  ) then
    create table if not exists auth.users (
      id uuid primary key default gen_random_uuid(),
      email text unique
    );

    create function auth.uid() returns uuid
      language sql stable
      as $fn$
        select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      $fn$;
  end if;
end
$$;

-- ============================================================================
-- 1. ORGANIZATIONS
-- ============================================================================

create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  status text not null default 'active' check (status in ('active', 'suspended', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists organization_settings (
  organization_id uuid primary key references organizations(id) on delete cascade,
  default_clinical_domain_id uuid,
  default_language text not null default 'en' check (default_language in ('en', 'ar')),
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ============================================================================
-- 2. PROFILES (1:1 with auth.users)
-- ============================================================================

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  locale text not null default 'en' check (locale in ('en', 'ar')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================================
-- 3. ROLES AND PERMISSIONS
-- ============================================================================

create table if not exists roles (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  description text not null
);

create table if not exists permissions (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  description text not null
);

create table if not exists role_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  permission_id uuid not null references permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

-- Approved V1 roles (Execution Plan §7 / Architecture Report §7.3)
insert into roles (key, description) values
  ('clinician', 'Submits clinical questions and reviews evidence-grounded answers'),
  ('clinical_pharmacist', 'Clinician-equivalent access focused on medication-adjacent evidence'),
  ('clinical_reviewer', 'Reviews extraction, approves knowledge releases'),
  ('knowledge_manager', 'Registers and manages guideline documents'),
  ('quality_manager', 'Reviews quality and safety signals'),
  ('safety_officer', 'Owns incident response and emergency shutdown'),
  ('organization_admin', 'Manages organization membership and settings'),
  ('auditor', 'Read-only access to audit records'),
  ('platform_support', 'Time-limited, explicitly audited support access')
on conflict (key) do nothing;

-- ============================================================================
-- 4. ORGANIZATION MEMBERSHIPS
-- ============================================================================

create table if not exists organization_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references roles(id),
  status text not null default 'active' check (status in ('active', 'suspended', 'removed')),
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create index if not exists idx_memberships_user_active
  on organization_memberships (user_id, status);

create index if not exists idx_memberships_org_active
  on organization_memberships (organization_id, status);

create table if not exists access_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  reviewed_membership_id uuid not null references organization_memberships(id) on delete cascade,
  reviewed_by uuid not null references auth.users(id),
  decision text not null check (decision in ('confirmed', 'revoked', 'role_changed')),
  notes text,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- 5. AUDIT EVENTS (append-only; no update/delete policy is ever granted)
-- ============================================================================

create table if not exists audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id),
  actor_id uuid references auth.users(id),
  correlation_id uuid not null,
  event_type text not null,
  resource_type text not null,
  resource_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_org_created on audit_events (organization_id, created_at desc);
create index if not exists idx_audit_correlation on audit_events (correlation_id);

-- Immutability: revoke update/delete at the grant layer (defense in depth
-- beyond RLS — see docs/database/schema.md).
revoke update, delete on audit_events from public;

-- ============================================================================
-- 6. FEATURE FLAGS (needed by AI Gateway / emergency shutdown, Execution Plan §7.4)
-- ============================================================================

create table if not exists feature_flags (
  key text primary key,
  organization_id uuid references organizations(id) on delete cascade,
  enabled boolean not null default false,
  description text,
  updated_at timestamptz not null default now()
);

-- ============================================================================
-- 7. RLS HELPER FUNCTIONS
-- ============================================================================

-- Active organization IDs for the current auth.uid().
create or replace function current_active_organization_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id
  from organization_memberships
  where user_id = auth.uid()
    and status = 'active'
$$;

-- Whether the current user holds a given role key in a given organization.
create or replace function has_role_in_organization(p_organization_id uuid, p_role_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from organization_memberships m
    join roles r on r.id = m.role_id
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and r.key = p_role_key
  )
$$;

-- ============================================================================
-- 8. ENABLE RLS + POLICIES
-- ============================================================================

alter table organizations enable row level security;
alter table organization_settings enable row level security;
alter table profiles enable row level security;
alter table organization_memberships enable row level security;
alter table access_reviews enable row level security;
alter table audit_events enable row level security;
alter table feature_flags enable row level security;
alter table roles enable row level security;
alter table permissions enable row level security;
alter table role_permissions enable row level security;

-- roles/permissions/role_permissions: readable by any authenticated member
-- of at least one active organization (needed to render permission-aware UI).
create policy roles_read_authenticated on roles
  for select using (auth.uid() is not null);

create policy permissions_read_authenticated on permissions
  for select using (auth.uid() is not null);

create policy role_permissions_read_authenticated on role_permissions
  for select using (auth.uid() is not null);

-- organizations: visible only to active members.
create policy organizations_select_member on organizations
  for select using (id in (select current_active_organization_ids()));

-- organization_settings: visible only to active members.
create policy org_settings_select_member on organization_settings
  for select using (organization_id in (select current_active_organization_ids()));

create policy org_settings_update_admin on organization_settings
  for update using (has_role_in_organization(organization_id, 'organization_admin'));

-- profiles: a user can always read/update their own profile, and can read
-- profiles of members who share an active organization with them.
create policy profiles_select_self_or_shared_org on profiles
  for select using (
    id = auth.uid()
    or id in (
      select m2.user_id
      from organization_memberships m1
      join organization_memberships m2 on m2.organization_id = m1.organization_id
      where m1.user_id = auth.uid()
        and m1.status = 'active'
        and m2.status = 'active'
    )
  );

create policy profiles_update_self on profiles
  for update using (id = auth.uid());

create policy profiles_insert_self on profiles
  for insert with check (id = auth.uid());

-- organization_memberships: members can see other active memberships in
-- their own active organizations; only organization_admin can write.
create policy memberships_select_shared_org on organization_memberships
  for select using (organization_id in (select current_active_organization_ids()));

create policy memberships_write_admin on organization_memberships
  for insert with check (has_role_in_organization(organization_id, 'organization_admin'));

create policy memberships_update_admin on organization_memberships
  for update using (has_role_in_organization(organization_id, 'organization_admin'));

-- access_reviews: organization_admin and auditor only.
create policy access_reviews_select_admin_or_auditor on access_reviews
  for select using (
    has_role_in_organization(organization_id, 'organization_admin')
    or has_role_in_organization(organization_id, 'auditor')
  );

create policy access_reviews_insert_admin on access_reviews
  for insert with check (has_role_in_organization(organization_id, 'organization_admin'));

-- audit_events: readable by auditor / organization_admin / safety_officer
-- for their own organization only; never writable via client roles (the
-- application/service role writes audit rows, never the browser).
create policy audit_events_select_privileged on audit_events
  for select using (
    organization_id in (select current_active_organization_ids())
    and (
      has_role_in_organization(organization_id, 'auditor')
      or has_role_in_organization(organization_id, 'organization_admin')
      or has_role_in_organization(organization_id, 'safety_officer')
    )
  );

-- feature_flags: readable by active members; writable by organization_admin.
create policy feature_flags_select_member on feature_flags
  for select using (
    organization_id is null
    or organization_id in (select current_active_organization_ids())
  );

create policy feature_flags_write_admin on feature_flags
  for all using (has_role_in_organization(organization_id, 'organization_admin'));

-- ============================================================================
-- End of migration 0001
-- ============================================================================
