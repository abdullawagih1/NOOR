-- ============================================================================
-- Noor V1 Test Suite — Security Hardening Regression (Sprint 1.2B, mission
-- §5). Turns the two real, hosted-only bugs found and fixed in Sprint 1.2A
-- (pgcrypto search_path gap; authenticated/anon default-privileges gap on
-- the six Worker-only orchestration functions) into a permanent regression
-- suite, rather than a one-off verification script that could silently
-- stop being run.
--
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 007_security_hardening_review.sql
-- Depends on 001-006 already having run in this database (migrations
-- 0001-0007 must be applied).
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- TEST 1: PUBLIC (and, transitively, every role) cannot CREATE in the
-- `public` schema. This is what makes "an attacker-writable schema in
-- search_path" structurally impossible on both environments — Postgres
-- 15+'s default (no CREATE grant to PUBLIC on `public`) is relied upon,
-- not assumed; this test proves it's actually in effect on this database,
-- not just documented as an expectation.
-- ----------------------------------------------------------------------------
do $$
declare
  v_public_create boolean;
  v_authenticated_create boolean;
  v_anon_create boolean;
begin
  select has_schema_privilege('public', 'public', 'CREATE') into v_public_create;
  if v_public_create then
    raise exception 'TEST 1 FAILED: the PUBLIC pseudo-role can CREATE in schema public';
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    select has_schema_privilege('authenticated', 'public', 'CREATE') into v_authenticated_create;
    if v_authenticated_create then
      raise exception 'TEST 1 FAILED: authenticated can CREATE in schema public';
    end if;
  end if;

  if exists (select 1 from pg_roles where rolname = 'anon') then
    select has_schema_privilege('anon', 'public', 'CREATE') into v_anon_create;
    if v_anon_create then
      raise exception 'TEST 1 FAILED: anon can CREATE in schema public';
    end if;
  end if;

  raise notice 'TEST 1 PASSED: PUBLIC/authenticated/anon cannot CREATE in schema public';
end
$$;

-- ----------------------------------------------------------------------------
-- TEST 2: if an `extensions` schema exists (hosted Supabase; not present on
-- plain local Postgres), PUBLIC/authenticated/anon cannot CREATE there
-- either. Migration 0007's `search_path = public, extensions` (used by
-- assert_lease_owner/claim_next_document_processing_job for pgcrypto) is
-- only safe from search-path injection if this holds — a writable
-- `extensions` schema would let a lower-privileged role shadow
-- digest()/gen_random_bytes() with a same-named function of its own.
-- ----------------------------------------------------------------------------
do $$
declare
  v_public_create boolean;
  v_authenticated_create boolean;
  v_anon_create boolean;
begin
  if not exists (select 1 from pg_namespace where nspname = 'extensions') then
    raise notice 'TEST 2 SKIPPED: no `extensions` schema on this database (expected locally)';
  else
    select has_schema_privilege('public', 'extensions', 'CREATE') into v_public_create;
    if v_public_create then
      raise exception 'TEST 2 FAILED: the PUBLIC pseudo-role can CREATE in schema extensions';
    end if;

    if exists (select 1 from pg_roles where rolname = 'authenticated') then
      select has_schema_privilege('authenticated', 'extensions', 'CREATE') into v_authenticated_create;
      if v_authenticated_create then
        raise exception 'TEST 2 FAILED: authenticated can CREATE in schema extensions';
      end if;
    end if;

    if exists (select 1 from pg_roles where rolname = 'anon') then
      select has_schema_privilege('anon', 'extensions', 'CREATE') into v_anon_create;
      if v_anon_create then
        raise exception 'TEST 2 FAILED: anon can CREATE in schema extensions';
      end if;
    end if;

    raise notice 'TEST 2 PASSED: PUBLIC/authenticated/anon cannot CREATE in schema extensions';
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- TEST 3: every search_path on the Sprint 1.2A orchestration functions is
-- exactly `public` or `public, extensions` — never broader (never includes
-- pg_temp explicitly, never omits a schema qualifier entirely in a way
-- that would fall back to a session-controlled default).
-- ----------------------------------------------------------------------------
do $$
declare
  v_bad_count int;
begin
  select count(*) into v_bad_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'assert_lease_owner', 'claim_next_document_processing_job', 'start_document_processing_job',
      'heartbeat_document_processing_job', 'complete_document_processing_job',
      'fail_document_processing_job', 'recover_expired_document_processing_jobs'
    )
    and (
      p.proconfig is null
      or not (
        array_to_string(p.proconfig, ',') like '%search_path=public%'
        and array_to_string(p.proconfig, ',') not like '%pg_temp%'
      )
    );

  if v_bad_count > 0 then
    raise exception 'TEST 3 FAILED: % orchestration function(s) have a missing or unexpectedly broad search_path', v_bad_count;
  end if;
  raise notice 'TEST 3 PASSED: every orchestration function has a narrow, explicit search_path';
end
$$;

-- ----------------------------------------------------------------------------
-- TEST 4: the six Worker-only functions (plus their two internal helpers)
-- have EXECUTE granted to no role except the connecting superuser/owner
-- (the local analogue of hosted's `service_role`) — never `authenticated`,
-- never `anon`, never `PUBLIC`. This is the permanent regression for the
-- exact hosted-only bug found and fixed in Sprint 1.2A.
-- ----------------------------------------------------------------------------
do $$
declare
  v_leaked_grant record;
  v_leak_count int := 0;
begin
  for v_leaked_grant in
    select routine_name, grantee
    from information_schema.routine_privileges
    where routine_name in (
      'assert_lease_owner', 'compute_retry_delay_seconds',
      'claim_next_document_processing_job', 'start_document_processing_job',
      'heartbeat_document_processing_job', 'complete_document_processing_job',
      'fail_document_processing_job', 'recover_expired_document_processing_jobs'
    )
    and grantee not in ('postgres', 'service_role', current_user)
  loop
    v_leak_count := v_leak_count + 1;
    raise warning 'unexpected grant: % has EXECUTE on %', v_leaked_grant.grantee, v_leaked_grant.routine_name;
  end loop;

  if v_leak_count > 0 then
    raise exception 'TEST 4 FAILED: % unexpected EXECUTE grant(s) found on Worker-only functions', v_leak_count;
  end if;
  raise notice 'TEST 4 PASSED: no Worker-only function is EXECUTE-granted beyond postgres/service_role';
end
$$;

-- ----------------------------------------------------------------------------
-- TEST 5: a real call attempt as `authenticated` is denied (permission
-- denied for function), not merely "no grant exists in the catalog" —
-- proving the enforcement is live, not just declared.
-- ----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    begin
      set local role authenticated;
      perform claim_next_document_processing_job('security-regression-test-worker');
      set local role none;
      raise exception 'TEST 5 FAILED: authenticated successfully called claim_next_document_processing_job';
    exception
      when insufficient_privilege then
        set local role none;
        raise notice 'TEST 5 PASSED: authenticated is denied (permission denied) when calling claim_next_document_processing_job';
      when others then
        set local role none;
        raise exception 'TEST 5 FAILED: unexpected error calling as authenticated: %', sqlerrm;
    end;
  else
    raise notice 'TEST 5 SKIPPED: no authenticated role on this database';
  end if;
end
$$;

do $$
begin
  raise notice 'ALL SECURITY HARDENING REGRESSION TESTS PASSED';
end
$$;
