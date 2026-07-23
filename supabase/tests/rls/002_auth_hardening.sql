-- ============================================================================
-- Noor V1 RLS Test Suite — Sprint 0 Auth Hardening (migration 0002)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 002_auth_hardening.sql
-- Assumes 001_tenant_isolation.sql's `authenticated` role/grants already
-- exist in this session (same suite run, same connection is not required —
-- CI re-applies migrations + seed fresh, then runs both test files).
-- ============================================================================

\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$$;

grant select on organizations, organization_settings, profiles,
  organization_memberships, access_reviews, audit_events, feature_flags,
  roles, permissions, role_permissions to authenticated;
grant insert, update on organization_memberships, access_reviews, feature_flags to authenticated;
grant update on organization_settings, profiles to authenticated;
grant insert on profiles to authenticated;

-- ---------------------------------------------------------------------------
-- TEST 1: has_permission_in_organization reflects the seeded role mapping
-- Admin Alpha (organization_admin in org Alpha) must have
-- organization.members.manage; a plain clinician must not.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_admin_has boolean;
  begin
    select has_permission_in_organization('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'organization.members.manage')
      into v_admin_has;
    if not v_admin_has then
      raise exception 'TEST 1 FAILED: admin.alpha lacks organization.members.manage';
    end if;
    raise notice 'TEST 1 PASSED: seeded role_permissions grant admin the expected permission';
  end
  $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_clinician_has boolean;
  begin
    select has_permission_in_organization('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'organization.members.manage')
      into v_clinician_has;
    if v_clinician_has then
      raise exception 'TEST 1b FAILED: plain clinician unexpectedly has organization.members.manage';
    end if;
    raise notice 'TEST 1b PASSED: non-admin role does not get admin-only permission';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 2: organization_memberships.organization_id cannot be reassigned
-- ---------------------------------------------------------------------------
do $$
declare v_membership_id uuid;
declare v_other_org uuid;
declare v_reassigned boolean := false;
begin
  select id into v_membership_id from organization_memberships
    where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' limit 1;
  select id into v_other_org from organizations where slug = 'org-beta';

  begin
    update organization_memberships set organization_id = v_other_org where id = v_membership_id;
    v_reassigned := true;
  exception when others then
    v_reassigned := false;
  end;

  if v_reassigned then
    raise exception 'TEST 2 FAILED: organization_id was reassigned across tenants';
  end if;

  raise notice 'TEST 2 PASSED: cross-tenant membership reassignment blocked';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 3: audit_events is append-only even for the session's own role
-- (this file runs as whatever role executes psql — typically table owner /
-- superuser in CI — proving the trigger, not just the 0001 REVOKE, is what
-- blocks the mutation).
-- ---------------------------------------------------------------------------
do $$
declare v_event_id uuid;
declare v_mutated boolean := false;
begin
  insert into audit_events (organization_id, actor_id, correlation_id, event_type, resource_type)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
          gen_random_uuid(), 'test.event', 'test')
  returning id into v_event_id;

  begin
    update audit_events set event_type = 'tampered' where id = v_event_id;
    v_mutated := true;
  exception when others then
    v_mutated := false;
  end;

  if v_mutated then
    raise exception 'TEST 3 FAILED: audit_events was mutated without the maintenance override';
  end if;

  raise notice 'TEST 3 PASSED: audit_events UPDATE blocked for the current role, override unset';

  begin
    delete from audit_events where id = v_event_id;
    v_mutated := true;
  exception when others then
    v_mutated := false;
  end;

  if v_mutated then
    raise exception 'TEST 3b FAILED: audit_events was deleted without the maintenance override';
  end if;

  raise notice 'TEST 3b PASSED: audit_events DELETE blocked for the current role, override unset';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 4: the documented maintenance override actually works when set
-- explicitly (proves the escape hatch is real, not just a raise-always trap)
-- ---------------------------------------------------------------------------
begin;
  set local noor.allow_audit_maintenance = 'true';

  do $$
  declare v_event_id uuid;
  begin
    insert into audit_events (organization_id, actor_id, correlation_id, event_type, resource_type)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            gen_random_uuid(), 'test.event.maintenance', 'test')
    returning id into v_event_id;

    update audit_events set event_type = 'maintenance-corrected' where id = v_event_id;
    delete from audit_events where id = v_event_id;

    raise notice 'TEST 4 PASSED: documented maintenance override permits UPDATE/DELETE when explicitly set';
  end
  $$;
rollback;

\echo 'ALL AUTH HARDENING TESTS PASSED'
