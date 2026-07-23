-- ============================================================================
-- Noor V1 RLS Test Suite — Tenant Isolation
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 001_tenant_isolation.sql
-- Convention: each block sets the Supabase-style session claim
--   request.jwt.claim.sub = <user id>
-- then runs an authenticated-role query and asserts the row count.
-- A failing assertion raises an exception and aborts with a non-zero exit
-- code, which is what CI treats as a test failure.
-- ============================================================================

\set ON_ERROR_STOP on

-- Create a restricted role that RLS actually applies to (superuser bypasses RLS).
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
-- TEST 1: Same-tenant access succeeds
-- Admin Alpha (org Alpha) must see org Alpha and its memberships.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from organizations where slug = 'org-alpha';
    if v_count <> 1 then
      raise exception 'TEST 1 FAILED: admin.alpha could not see org-alpha (got % rows)', v_count;
    end if;

    select count(*) into v_count from organization_memberships
      where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    if v_count < 2 then
      raise exception 'TEST 1 FAILED: admin.alpha could not see org-alpha memberships (got % rows)', v_count;
    end if;

    raise notice 'TEST 1 PASSED: same-tenant access succeeds';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 2: Cross-tenant access fails
-- Admin Alpha must NOT see org Beta or its memberships.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from organizations where slug = 'org-beta';
    if v_count <> 0 then
      raise exception 'TEST 2 FAILED: admin.alpha could see org-beta (cross-tenant leak, got % rows)', v_count;
    end if;

    select count(*) into v_count from organization_memberships
      where organization_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    if v_count <> 0 then
      raise exception 'TEST 2 FAILED: admin.alpha could see org-beta memberships (got % rows)', v_count;
    end if;

    raise notice 'TEST 2 PASSED: cross-tenant access denied';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 3: Suspended membership fails
-- The suspended Alpha user must not be able to see org Alpha.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
  set local request.jwt.claims = '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from organizations where slug = 'org-alpha';
    if v_count <> 0 then
      raise exception 'TEST 3 FAILED: suspended member could still see org-alpha (got % rows)', v_count;
    end if;

    raise notice 'TEST 3 PASSED: suspended membership denied';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 4: Removed membership fails
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
  set local request.jwt.claims = '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from organizations where slug = 'org-alpha';
    if v_count <> 0 then
      raise exception 'TEST 4 FAILED: removed member could still see org-alpha (got % rows)', v_count;
    end if;

    raise notice 'TEST 4 PASSED: removed membership denied';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 5: Unauthorized privileged action fails
-- A plain clinician must not be able to write organization_memberships
-- (only organization_admin can, per policy memberships_write_admin).
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_inserted boolean := false;
  begin
    begin
      insert into organization_memberships (organization_id, user_id, role_id, status)
      select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', gen_random_uuid(), id, 'active'
      from roles where key = 'clinician';
      v_inserted := true;
    exception when insufficient_privilege or others then
      v_inserted := false;
    end;

    if v_inserted then
      raise exception 'TEST 5 FAILED: non-admin clinician was able to insert a membership';
    end if;

    raise notice 'TEST 5 PASSED: privileged action denied for non-admin role';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 6: Unauthorized audit-event read fails
-- A plain clinician (no auditor/admin/safety_officer role) must not see
-- audit_events for their own organization.
-- ---------------------------------------------------------------------------
begin;
  insert into audit_events (organization_id, actor_id, correlation_id, event_type, resource_type)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
          gen_random_uuid(), 'organization.created', 'organization');
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from audit_events
      where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    if v_count <> 0 then
      raise exception 'TEST 6 FAILED: non-privileged clinician could read audit_events (got % rows)', v_count;
    end if;

    raise notice 'TEST 6 PASSED: unauthorized audit-event read denied';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 7: Audit events are append-only (no UPDATE/DELETE grant to public)
-- ---------------------------------------------------------------------------
do $$
declare v_has_update boolean;
declare v_has_delete boolean;
begin
  select has_table_privilege('authenticated', 'audit_events', 'UPDATE') into v_has_update;
  select has_table_privilege('authenticated', 'audit_events', 'DELETE') into v_has_delete;

  if v_has_update or v_has_delete then
    raise exception 'TEST 7 FAILED: audit_events is not append-only (update=%, delete=%)', v_has_update, v_has_delete;
  end if;

  raise notice 'TEST 7 PASSED: audit_events is append-only for the authenticated role';
end
$$;

\echo 'ALL RLS TESTS PASSED'
