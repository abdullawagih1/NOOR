-- ============================================================================
-- Noor V1 RLS + Lifecycle Test Suite — Guideline Registry (migration 0005)
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 003_guideline_registry.sql
-- Assumes 001_tenant_isolation.sql already ran in this database (creates the
-- `authenticated` role and seed org/user fixtures) — CI always runs all
-- three files in order against a freshly migrated + seeded database.
--
-- Fixture IDs (domain/authority/guideline/version) are threaded between
-- statements via a session-scoped temp table + two tiny SQL functions,
-- NOT psql's `:'var'` \gset substitution — psql does not interpolate
-- `:'var'` inside dollar-quoted (`$$ ... $$`) plpgsql bodies, which is where
-- nearly every assertion in this file lives, so `\gset`-style substitution
-- silently sends the literal text `:'var'` to the server inside a DO block
-- (a real syntax error, confirmed while writing this file — the temp-table
-- approach works identically inside and outside DO blocks).
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- SETUP: grants mirroring migration 0005's guarded `authenticated` block
-- (which no-ops in this plain-Postgres CI database at migration-apply time,
-- since `authenticated` does not exist until this test suite creates it),
-- plus two extra seed users this suite needs (reviewer, quality) that
-- supabase/seed.sql does not create, plus the fixture-passing helpers.
-- ----------------------------------------------------------------------------

grant select on clinical_domains, guideline_authorities, guidelines,
  guideline_versions, guideline_reviews, guideline_lifecycle_events
  to authenticated;
revoke insert, update, delete on clinical_domains, guideline_authorities,
  guidelines, guideline_versions, guideline_reviews, guideline_lifecycle_events
  from authenticated;

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

insert into auth.users (id, email) values
  ('66666666-6666-6666-6666-666666666666', 'reviewer.alpha@example.test'),
  ('77777777-7777-7777-7777-777777777777', 'quality.alpha@example.test')
on conflict (id) do nothing;

insert into profiles (id, display_name) values
  ('66666666-6666-6666-6666-666666666666', 'Reviewer Alpha'),
  ('77777777-7777-7777-7777-777777777777', 'Quality Alpha')
on conflict (id) do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '66666666-6666-6666-6666-666666666666', id, 'active'
from roles where key = 'clinical_reviewer'
on conflict do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '77777777-7777-7777-7777-777777777777', id, 'active'
from roles where key = 'quality_manager'
on conflict do nothing;

-- SECURITY DEFINER so the fixture-passing helpers work regardless of which
-- role is active via `set local role authenticated` in the surrounding
-- transaction (a temp table's privileges belong to its creating session's
-- role, not automatically to every other role in the same session).
create temporary table test_fixtures (key text primary key, value uuid not null);

create or replace function test_fixture_set(p_key text, p_value uuid) returns uuid
language sql security definer as $$
  insert into test_fixtures (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value
  returning value;
$$;

create or replace function fx(p_key text) returns uuid
language sql stable security definer as $$
  select value from test_fixtures where key = p_key;
$$;

-- Fixture identity conventions used throughout:
--   admin.alpha      (11111111...) organization_admin, org Alpha — creates content
--   clinician.alpha  (22222222...) clinician, org Alpha           — read_active only
--   admin.beta       (33333333...) organization_admin, org Beta   — cross-tenant probe
--   reviewer.alpha   (66666666...) clinical_reviewer, org Alpha
--   quality.alpha    (77777777...) quality_manager, org Alpha     — approve/activate/withdraw

-- ----------------------------------------------------------------------------
-- FIXTURE: domain, authority, guideline, and an initial draft version,
-- created by admin.alpha. Persisted (committed) — later tests build on it.
-- ----------------------------------------------------------------------------

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('domain_id', id) from create_clinical_domain(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'hypertension', 'Adult Hypertension', 'Pending clinical confirmation'
  );
  select test_fixture_set('authority_id', id) from create_guideline_authority(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Test Guideline Authority', 'TGA', 'society', 'Global', null, true, 'seeded for RLS testing'
  );
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('guideline_id', id) from create_guideline(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'),
    'HTN-001', 'Adult Hypertension Management', 'Hypertension', 'Global', 'en', 'Seeded for RLS testing'
  );
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('version_id', id) from create_guideline_version(
    fx('guideline_id'), 'v1.0', 'First edition', '2024-01-01', '2024-02-01', null, null,
    'en', null, null, null, null, null, null, null
  );
commit;

do $$
begin
  raise notice 'FIXTURE READY: domain, authority, guideline, and draft version v1.0 created by admin.alpha';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 1: Duplicate internal_code within the same organization is rejected
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform create_guideline(
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', fx('domain_id'), fx('authority_id'),
        'HTN-001', 'Duplicate Code Attempt'
      );
    exception when unique_violation then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 1 FAILED: duplicate internal_code was accepted';
    end if;
    raise notice 'TEST 1 PASSED: duplicate internal_code rejected';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 2: Duplicate version_label within the same guideline is rejected
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform create_guideline_version(fx('guideline_id'), 'v1.0');
    exception when unique_violation then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 2 FAILED: duplicate version_label was accepted';
    end if;
    raise notice 'TEST 2 PASSED: duplicate version_label rejected';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 3: Invalid date ordering is rejected (effective_date before publication_date)
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform create_guideline_version(
        fx('guideline_id'), 'v-bad-dates', null, '2024-06-01'::date, '2024-01-01'::date
      );
    exception when check_violation then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 3 FAILED: effective_date before publication_date was accepted';
    end if;
    raise notice 'TEST 3 PASSED: invalid date ordering rejected';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 4: Cross-tenant creation is denied — admin.beta cannot create a
-- guideline referencing org Alpha's domain/authority (permission check
-- fails first; the composite FK would reject it either way).
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
  set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform create_guideline(
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', fx('domain_id'), fx('authority_id'),
        'HTN-CROSS', 'Cross-tenant attempt'
      );
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 4 FAILED: admin.beta created a guideline referencing org Alpha''s domain';
    end if;
    raise notice 'TEST 4 PASSED: cross-tenant guideline creation denied';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 5: Clinician (guidelines.read_active only) cannot see the draft
-- version; admin.alpha (guidelines.read_all via organization_admin) can.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from guideline_versions where id = fx('version_id');
    if v_count <> 0 then
      raise exception 'TEST 5 FAILED: clinician could see a draft guideline version';
    end if;
    raise notice 'TEST 5 PASSED: clinician cannot see a draft version';
  end
  $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from guideline_versions where id = fx('version_id');
    if v_count <> 1 then
      raise exception 'TEST 5b FAILED: admin.alpha (read_all) could not see the draft version';
    end if;
    raise notice 'TEST 5b PASSED: guidelines.read_all sees draft versions';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 6: Illegal transition draft -> active is rejected, and leaves no
-- partial write (status is still draft afterward).
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform transition_guideline_version(fx('version_id'), 'active');
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 6 FAILED: draft -> active was allowed';
    end if;
    raise notice 'TEST 6 PASSED: draft -> active rejected';
  end
  $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_status text;
  begin
    select lifecycle_status into v_status from guideline_versions where id = fx('version_id');
    if v_status <> 'draft' then
      raise exception 'TEST 6b FAILED: version status changed despite the rejected transition (now %)', v_status;
    end if;
    raise notice 'TEST 6b PASSED: rejected transition left no partial write';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 7: Submit for review (draft -> ready_for_review). Committed — later
-- tests depend on this state.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_status text;
  begin
    perform transition_guideline_version(fx('version_id'), 'ready_for_review');
    select lifecycle_status into v_status from guideline_versions where id = fx('version_id');
    if v_status <> 'ready_for_review' then
      raise exception 'TEST 7 FAILED: expected ready_for_review, got %', v_status;
    end if;
    raise notice 'TEST 7 PASSED: draft -> ready_for_review succeeded';
  end
  $$;
commit;

-- ---------------------------------------------------------------------------
-- TEST 8: A user lacking guidelines.review at all cannot submit a review
-- (admin.alpha, the version's own creator, also lacks the permission —
-- this proves the permission gate; TEST 9/12 exercise the reviewer/approver
-- path with reviewer.alpha and quality.alpha, who are not the creator).
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform submit_guideline_review(fx('version_id'), 'recommended_for_approval');
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 8 FAILED: admin.alpha (lacking guidelines.review) submitted a review';
    end if;
    raise notice 'TEST 8 PASSED: non-reviewer cannot submit a review';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 9: reviewer.alpha submits a recommending review. Committed.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  do $$
  declare v_review_status text;
  begin
    select review_status into v_review_status
      from submit_guideline_review(fx('version_id'), 'recommended_for_approval', 'Looks correct', null, null);
    if v_review_status <> 'recommended_for_approval' then
      raise exception 'TEST 9 FAILED: unexpected review_status %', v_review_status;
    end if;
    raise notice 'TEST 9 PASSED: reviewer.alpha recorded a recommending review';
  end
  $$;
commit;

-- ---------------------------------------------------------------------------
-- TEST 10: Self-approval is blocked — admin.alpha (creator) cannot approve
-- their own version. admin.alpha also lacks guidelines.approve, so this
-- proves the permission gate; the explicit self-approval check inside
-- transition_guideline_version (blocking even a creator who DOES hold
-- guidelines.approve) is verified by code review of migration 0005 — no
-- seeded role in this fixture set both authors content and holds
-- guidelines.approve, so it cannot be exercised end-to-end here without
-- adding a third role combination.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform transition_guideline_version(fx('version_id'), 'approved');
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 10 FAILED: admin.alpha (lacking guidelines.approve) approved a version';
    end if;
    raise notice 'TEST 10 PASSED: non-approver cannot approve';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 11: Approval without any recommending review fails — proven on a
-- second, freshly created version with no review yet.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  select test_fixture_set('version2_id', id) from create_guideline_version(fx('guideline_id'), 'v1.1');
  select transition_guideline_version(fx('version2_id'), 'ready_for_review');
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform transition_guideline_version(fx('version2_id'), 'approved');
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 11 FAILED: approval succeeded without any recommending review';
    end if;
    raise notice 'TEST 11 PASSED: approval requires a recommending review';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 12: quality.alpha (non-creator, guidelines.approve) approves v1.0,
-- then activates it. Committed — subsequent supersession test depends on it.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_status text;
  begin
    perform transition_guideline_version(fx('version_id'), 'approved');
    select lifecycle_status into v_status from guideline_versions where id = fx('version_id');
    if v_status <> 'approved' then
      raise exception 'TEST 12 FAILED: expected approved, got %', v_status;
    end if;
    raise notice 'TEST 12 PASSED: ready_for_review -> approved succeeded for a non-creator approver';
  end
  $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_status text;
  declare v_active_id uuid;
  begin
    perform transition_guideline_version(fx('version_id'), 'active');
    select lifecycle_status into v_status from guideline_versions where id = fx('version_id');
    select current_active_version_id into v_active_id from guidelines where id = fx('guideline_id');
    if v_status <> 'active' or v_active_id <> fx('version_id') then
      raise exception 'TEST 12b FAILED: activation did not take effect (status=%, active_id=%)', v_status, v_active_id;
    end if;
    raise notice 'TEST 12b PASSED: approved -> active succeeded and guidelines.current_active_version_id updated';
  end
  $$;
commit;

-- ---------------------------------------------------------------------------
-- TEST 13: Clinician can now see the active version (guidelines.read_active).
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from guideline_versions where id = fx('version_id');
    if v_count <> 1 then
      raise exception 'TEST 13 FAILED: clinician could not see the active version';
    end if;
    raise notice 'TEST 13 PASSED: clinician sees the active version';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 14: Released-version immutability — a raw client UPDATE against the
-- active version is rejected by RLS (no UPDATE policy/grant exists at all;
-- the only write path is transition_guideline_version()).
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      update guideline_versions set notes = 'tampered' where id = fx('version_id');
    exception when insufficient_privilege or others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 14 FAILED: an active guideline_version was mutated via raw UPDATE';
    end if;
    raise notice 'TEST 14 PASSED: released version content is immutable via raw client UPDATE';
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- TEST 15: Second version (v1.1) approval + activation supersedes v1.0
-- transactionally, and only one active version exists at a time.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  -- version2 is already ready_for_review (committed by TEST 11's setup
  -- above) — only a recommending review is needed here.
  select submit_guideline_review(fx('version2_id'), 'recommended_for_approval', 'Confirmed update');
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v1_status text;
  declare v2_status text;
  declare v_active_id uuid;
  declare v_active_count int;
  begin
    perform transition_guideline_version(fx('version2_id'), 'approved');
    perform transition_guideline_version(fx('version2_id'), 'active');

    select lifecycle_status into v1_status from guideline_versions where id = fx('version_id');
    select lifecycle_status into v2_status from guideline_versions where id = fx('version2_id');
    select current_active_version_id into v_active_id from guidelines where id = fx('guideline_id');
    select count(*) into v_active_count from guideline_versions where guideline_id = fx('guideline_id') and lifecycle_status = 'active';

    if v1_status <> 'superseded' then
      raise exception 'TEST 15 FAILED: prior active version was not superseded (status=%)', v1_status;
    end if;
    if v2_status <> 'active' or v_active_id <> fx('version2_id') then
      raise exception 'TEST 15 FAILED: new version did not become active (status=%, active_id=%)', v2_status, v_active_id;
    end if;
    if v_active_count <> 1 then
      raise exception 'TEST 15 FAILED: expected exactly one active version, found %', v_active_count;
    end if;
    raise notice 'TEST 15 PASSED: activating v1.1 transactionally superseded v1.0; exactly one active version';
  end
  $$;
commit;

-- ---------------------------------------------------------------------------
-- TEST 16 & 17: Self-supersession and cross-guideline supersession are
-- rejected at the database layer (composite FK / check constraint), proven
-- directly (bypassing the function layer, as a privileged maintenance-style
-- write, to isolate the DB constraint from the function's own logic).
-- ---------------------------------------------------------------------------
do $$
declare v_failed boolean := false;
begin
  begin
    update guideline_versions set supersedes_version_id = id where id = fx('version2_id');
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 16 FAILED: self-supersession was accepted';
  end if;
  raise notice 'TEST 16 PASSED: self-supersession rejected';
end
$$;

do $$
declare v_other_guideline_id uuid;
declare v_other_domain_id uuid;
declare v_other_authority_id uuid;
declare v_failed boolean := false;
begin
  insert into clinical_domains (organization_id, code, name) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'other-domain', 'Other Domain')
    returning id into v_other_domain_id;
  insert into guideline_authorities (organization_id, name) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Other Authority')
    returning id into v_other_authority_id;
  insert into guidelines (organization_id, clinical_domain_id, authority_id, internal_code, canonical_title) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', v_other_domain_id, v_other_authority_id, 'OTHER-001', 'Other Guideline')
    returning id into v_other_guideline_id;

  begin
    -- version_id (v1.0) belongs to a DIFFERENT guideline than
    -- v_other_guideline_id; the composite FK
    -- (guideline_id, supersedes_version_id) -> guideline_versions(guideline_id, id)
    -- must reject a new version of v_other_guideline_id claiming to supersede it.
    insert into guideline_versions (organization_id, guideline_id, version_label, supersedes_version_id)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', v_other_guideline_id, 'cross-1.0', fx('version_id'));
  exception when foreign_key_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 17 FAILED: cross-guideline supersession was accepted';
  end if;
  raise notice 'TEST 17 PASSED: cross-guideline supersession rejected by the composite foreign key';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 18: Withdrawal requires a reason, and succeeds with one; withdrawing
-- the active version clears guidelines.current_active_version_id.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  begin
    begin
      perform transition_guideline_version(fx('version2_id'), 'withdrawn');
    exception when others then
      v_failed := true;
    end;
    if not v_failed then
      raise exception 'TEST 18 FAILED: withdrawal without a reason was accepted';
    end if;
    raise notice 'TEST 18 PASSED: withdrawal reason is mandatory';
  end
  $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

  do $$
  declare v_status text;
  declare v_active_id uuid;
  begin
    perform transition_guideline_version(fx('version2_id'), 'withdrawn', 'Superseding authority guidance retracted for RLS test purposes');
    select lifecycle_status into v_status from guideline_versions where id = fx('version2_id');
    select current_active_version_id into v_active_id from guidelines where id = fx('guideline_id');
    if v_status <> 'withdrawn' then
      raise exception 'TEST 18b FAILED: expected withdrawn, got %', v_status;
    end if;
    if v_active_id is not null then
      raise exception 'TEST 18b FAILED: guidelines.current_active_version_id was not cleared after withdrawal';
    end if;
    raise notice 'TEST 18b PASSED: withdrawal succeeded with a reason and cleared current_active_version_id';
  end
  $$;
commit;

-- ---------------------------------------------------------------------------
-- TEST 19: guideline_lifecycle_events is append-only for every role,
-- including the session's own (superuser, in CI) role, without the
-- documented maintenance override — mirrors 002's audit_events proof.
-- ---------------------------------------------------------------------------
do $$
declare v_event_id uuid;
declare v_mutated boolean := false;
begin
  select id into v_event_id from guideline_lifecycle_events where guideline_version_id = fx('version2_id') limit 1;

  begin
    update guideline_lifecycle_events set reason = 'tampered' where id = v_event_id;
    v_mutated := true;
  exception when others then
    v_mutated := false;
  end;
  if v_mutated then
    raise exception 'TEST 19 FAILED: guideline_lifecycle_events was mutated without the maintenance override';
  end if;
  raise notice 'TEST 19 PASSED: guideline_lifecycle_events UPDATE blocked without the maintenance override';
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 20: Audit events were recorded for the major lifecycle actions above.
-- ---------------------------------------------------------------------------
do $$
declare v_count int;
begin
  select count(*) into v_count from audit_events
    where resource_type = 'guideline_version'
      and resource_id = fx('version2_id')
      and event_type in (
        'guideline_version.created', 'guideline_version.submitted_for_review',
        'guideline_review.submitted', 'guideline_version.approved',
        'guideline_version.activated', 'guideline_version.superseded',
        'guideline_version.withdrawn'
      );
  if v_count < 6 then
    raise exception 'TEST 20 FAILED: expected at least 6 audit_events rows for version2, found %', v_count;
  end if;
  raise notice 'TEST 20 PASSED: audit_events recorded for guideline registry lifecycle actions (% rows)', v_count;
end
$$;

-- ---------------------------------------------------------------------------
-- TEST 21: Suspended and removed memberships, and anonymous sessions, are
-- all denied read access to the guideline registry.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
  set local request.jwt.claims = '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from guidelines where id = fx('guideline_id');
    if v_count <> 0 then
      raise exception 'TEST 21 FAILED: suspended member could see org Alpha''s guideline registry';
    end if;
    raise notice 'TEST 21 PASSED: suspended membership denied guideline registry access';
  end
  $$;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
  set local request.jwt.claims = '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from guidelines where id = fx('guideline_id');
    if v_count <> 0 then
      raise exception 'TEST 21b FAILED: removed member could see org Alpha''s guideline registry';
    end if;
    raise notice 'TEST 21b PASSED: removed membership denied guideline registry access';
  end
  $$;
rollback;

-- Anonymous is modeled as an `authenticated`-role session with no sub claim
-- (auth.uid() resolves to null) — NOT a bare superuser statement, which
-- would bypass RLS entirely and make this test meaningless.
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '';
  set local request.jwt.claims = '';

  do $$
  declare v_count int;
  begin
    select count(*) into v_count from guidelines where id = fx('guideline_id');
    if v_count <> 0 then
      raise exception 'TEST 21c FAILED: an anonymous session could see the guideline registry';
    end if;
    raise notice 'TEST 21c PASSED: anonymous session denied guideline registry access';
  end
  $$;
rollback;

drop function fx(text);
drop function test_fixture_set(text, uuid);

\echo 'ALL GUIDELINE REGISTRY TESTS PASSED'
