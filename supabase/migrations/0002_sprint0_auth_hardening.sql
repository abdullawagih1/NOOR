-- ============================================================================
-- Noor V1 — Migration 0002: Sprint 0 Auth Hardening
-- Council: Backend/Supabase Agent + Security Agent
-- ============================================================================
-- Follow-up to 0001_identity_and_rls.sql, found incomplete during Sprint 0
-- remediation:
--   1. permissions / role_permissions were declared but never seeded — no
--      workspace could actually be authorized against a permission key.
--   2. organization_memberships.organization_id could be reassigned by an
--      admin update (no WITH CHECK preventing cross-org reassignment).
--   3. audit_events relied on REVOKE alone; adds a trigger-based backstop
--      that also holds under any future grant misconfiguration, with a
--      documented, explicit maintenance override.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PERMISSIONS
-- ----------------------------------------------------------------------------

insert into permissions (key, description) values
  ('workspace.clinician.access', 'Access the Clinician workspace'),
  ('workspace.admin.access', 'Access the Admin workspace'),
  ('workspace.reviewer.access', 'Access the Clinical Reviewer workspace'),
  ('workspace.quality.access', 'Access the Quality & Safety workspace'),
  ('organization.members.read', 'View organization membership'),
  ('organization.members.manage', 'Invite, suspend, or change membership roles'),
  ('audit.read', 'Read audit events for the organization')
on conflict (key) do nothing;

-- ----------------------------------------------------------------------------
-- 2. ROLE -> PERMISSION MAPPING (Master Prompt §11 suggested baseline)
-- ----------------------------------------------------------------------------

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from (values
  ('clinician', 'workspace.clinician.access'),
  ('clinical_pharmacist', 'workspace.clinician.access'),
  ('clinical_reviewer', 'workspace.reviewer.access'),
  ('knowledge_manager', 'workspace.admin.access'),
  ('quality_manager', 'workspace.quality.access'),
  ('safety_officer', 'workspace.quality.access'),
  ('safety_officer', 'audit.read'),
  ('organization_admin', 'workspace.admin.access'),
  ('organization_admin', 'organization.members.read'),
  ('organization_admin', 'organization.members.manage'),
  ('organization_admin', 'audit.read'),
  ('auditor', 'audit.read'),
  ('auditor', 'organization.members.read'),
  ('platform_support', 'organization.members.read')
) as mapping(role_key, permission_key)
join roles r on r.key = mapping.role_key
join permissions p on p.key = mapping.permission_key
on conflict (role_id, permission_id) do nothing;

-- ----------------------------------------------------------------------------
-- 3. PERMISSION-CHECK HELPER (mirrors has_role_in_organization)
-- ----------------------------------------------------------------------------

create or replace function has_permission_in_organization(p_organization_id uuid, p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from organization_memberships m
    join role_permissions rp on rp.role_id = m.role_id
    join permissions p on p.id = rp.permission_id
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and p.key = p_permission_key
  )
$$;

-- ----------------------------------------------------------------------------
-- 4. PREVENT CROSS-ORGANIZATION MEMBERSHIP REASSIGNMENT
-- ----------------------------------------------------------------------------
-- RLS policy memberships_update_admin lets an organization_admin update rows
-- in their own org, but without this trigger nothing stops that same UPDATE
-- from also changing organization_id to a *different* org the admin belongs
-- to, silently moving a membership across tenants.

create or replace function prevent_membership_org_reassignment()
returns trigger
language plpgsql
as $$
begin
  if new.organization_id <> old.organization_id then
    raise exception 'organization_memberships.organization_id cannot be changed; remove and re-create the membership instead';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_membership_org_reassignment on organization_memberships;
create trigger trg_prevent_membership_org_reassignment
  before update on organization_memberships
  for each row execute function prevent_membership_org_reassignment();

-- ----------------------------------------------------------------------------
-- 5. AUDIT EVENTS: TRIGGER-BASED APPEND-ONLY BACKSTOP
-- ----------------------------------------------------------------------------
-- 0001 already revokes UPDATE/DELETE from `public`. That protects every
-- normal application role but NOT a role that owns the table or otherwise
-- bypasses grants (e.g. Supabase's service_role, which bypasses RLS and,
-- depending on ownership, may bypass simple grants too). This trigger fires
-- for ANY role, including the table owner, so it is real defense in depth —
-- but it must not block legitimate, rare administrative maintenance
-- (e.g. a GDPR-driven redaction). The escape hatch is a session-local GUC
-- that is only reachable via a direct, privileged database session (the SQL
-- editor or psql as a superuser) — never via PostgREST/application code, so
-- API clients (including callers holding the service_role key over HTTP)
-- cannot set it.
--
-- Honest scope: this is NOT "absolute" immutability — a database superuser
-- with a direct session can always set the override and mutate rows. It IS
-- immutability for every runtime role the application ever uses, including
-- accidental or malicious use of the service_role key from application code.

create or replace function prevent_audit_event_mutation()
returns trigger
language plpgsql
as $$
begin
  if coalesce(current_setting('noor.allow_audit_maintenance', true), 'false') = 'true' then
    return coalesce(new, old);
  end if;
  raise exception 'audit_events is append-only. UPDATE/DELETE is blocked for all roles. '
    'A documented, privileged maintenance session may override by executing '
    'set local noor.allow_audit_maintenance = ''true'' before the statement — '
    'see docs/database/schema.md for the sign-off process.';
end;
$$;

drop trigger if exists trg_audit_events_no_update on audit_events;
create trigger trg_audit_events_no_update
  before update on audit_events
  for each row execute function prevent_audit_event_mutation();

drop trigger if exists trg_audit_events_no_delete on audit_events;
create trigger trg_audit_events_no_delete
  before delete on audit_events
  for each row execute function prevent_audit_event_mutation();

-- ============================================================================
-- End of migration 0002
-- ============================================================================
