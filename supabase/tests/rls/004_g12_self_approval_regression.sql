-- ============================================================================
-- Noor V1 Regression Test — G-12: self-approval by a creator who ALSO holds
-- guidelines.approve must still be blocked.
-- Run as: psql -d noor_test -v ON_ERROR_STOP=1 -f 004_g12_self_approval_regression.sql
-- Depends on 001/002/003 already having run in this database (authenticated
-- role, seed fixtures, and reviewer.alpha 66666666... in particular) — same
-- ordering dependency 002 already has on 001, and 003 on 001/002.
--
-- Sprint 1's own test suite (003) could only prove the two paths that its
-- seeded roles naturally exercise: a non-creator approver succeeds, and a
-- creator who LACKS guidelines.approve is denied by the permission check
-- before the self-approval check is ever reached. Neither proves the
-- self-approval check itself fires when the permission check would
-- otherwise pass — this file closes exactly that gap with a synthetic role
-- holding both guidelines.create and guidelines.approve on the same user.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- SETUP: a test-only role combining guidelines.create + submit_for_review +
-- approve, so one user can reach ready_for_review and then illegally attempt
-- to approve their own work. Committed — this and everything it creates
-- below persists for the duration of the CI job's ephemeral database (same
-- precedent as 003's "Other Guideline"/"Other Domain" residue).
-- ----------------------------------------------------------------------------

insert into roles (key, description) values
  ('g12_test_creator_approver', 'TEST-ONLY: regression fixture for G-12, combines guidelines.create + guidelines.approve on one user')
on conflict (key) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from (values
  ('g12_test_creator_approver', 'clinical_domains.manage'),
  ('g12_test_creator_approver', 'guideline_authorities.manage'),
  ('g12_test_creator_approver', 'guidelines.create'),
  ('g12_test_creator_approver', 'guidelines.submit_for_review'),
  ('g12_test_creator_approver', 'guidelines.approve')
) as mapping(role_key, permission_key)
join roles r on r.key = mapping.role_key
join permissions p on p.key = mapping.permission_key
on conflict (role_id, permission_id) do nothing;

insert into auth.users (id, email) values
  ('99999999-9999-9999-9999-999999999999', 'g12.creator-approver@example.test')
on conflict (id) do nothing;

insert into profiles (id, display_name) values
  ('99999999-9999-9999-9999-999999999999', 'G12 Creator Approver')
on conflict (id) do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '99999999-9999-9999-9999-999999999999', id, 'active'
from roles where key = 'g12_test_creator_approver'
on conflict do nothing;

grant execute on function
  create_clinical_domain(uuid, text, text, text),
  create_guideline_authority(uuid, text, text, text, text, text, boolean, text),
  create_guideline(uuid, uuid, uuid, text, text, text, text, text, text),
  create_guideline_version(uuid, text, text, date, date, date, date, text, text, text, text, text, text, text, text),
  submit_guideline_review(uuid, text, text, text, text, uuid),
  transition_guideline_version(uuid, text, text, uuid)
  to authenticated;

create temporary table g12_fixtures (key text primary key, value uuid not null);

create or replace function g12_fixture_set(p_key text, p_value uuid) returns uuid
language sql security definer as $$
  insert into g12_fixtures (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value
  returning value;
$$;

create or replace function g12fx(p_key text) returns uuid
language sql stable security definer as $$
  select value from g12_fixtures where key = p_key;
$$;

-- ----------------------------------------------------------------------------
-- FIXTURE: creator-approver builds a domain, authority, guideline, and
-- version, then submits it for review — all as the same user.
-- ----------------------------------------------------------------------------

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
  set local request.jwt.claims = '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';

  select g12_fixture_set('domain_id', id) from create_clinical_domain(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'g12-domain', 'G12 Regression Domain', null
  );
  select g12_fixture_set('authority_id', id) from create_guideline_authority(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'G12 Regression Authority', null, null, null, null, true, null
  );
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
  set local request.jwt.claims = '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';

  select g12_fixture_set('guideline_id', id) from create_guideline(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', g12fx('domain_id'), g12fx('authority_id'),
    'G12-001', 'G12 Regression Guideline'
  );
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
  set local request.jwt.claims = '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';

  select g12_fixture_set('version_id', id) from create_guideline_version(g12fx('guideline_id'), 'v1.0');
  select transition_guideline_version(g12fx('version_id'), 'ready_for_review');
commit;

-- reviewer.alpha (from 003, org Alpha) submits a recommending review — a
-- real, legitimate review exists, so the ONLY thing standing between this
-- version and 'approved' is the self-approval check itself.
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

  select submit_guideline_review(g12fx('version_id'), 'recommended_for_approval', 'G12 regression fixture review');
commit;

do $$
begin
  raise notice 'G12 FIXTURE READY: creator-approver''s version is ready_for_review with a recommending review on file';
end
$$;

-- ---------------------------------------------------------------------------
-- G12 TEST: the creator, who legitimately holds guidelines.approve and has
-- a recommending review on file, still cannot approve their own version.
-- ---------------------------------------------------------------------------
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
  set local request.jwt.claims = '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';

  do $$
  declare v_failed boolean := false;
  declare v_error_message text;
  begin
    begin
      perform transition_guideline_version(g12fx('version_id'), 'approved');
    exception when others then
      v_failed := true;
      get stacked diagnostics v_error_message = message_text;
    end;

    if not v_failed then
      raise exception 'G12 FAILED: a creator holding guidelines.approve was able to approve their own version';
    end if;
    if v_error_message not ilike '%self-approval%' then
      raise exception 'G12 FAILED: the rejection was not the self-approval check (got: %)', v_error_message;
    end if;
    raise notice 'G12 PASSED: self-approval request denied (%)', v_error_message;
  end
  $$;
rollback;

-- ---------------------------------------------------------------------------
-- G12 TEST (evidence, outside the rolled-back transaction): lifecycle
-- status is unchanged, no approval lifecycle event exists, and no audit
-- event falsely claims an approval.
-- ---------------------------------------------------------------------------
do $$
declare v_status text;
declare v_lifecycle_event_count int;
declare v_audit_event_count int;
begin
  select lifecycle_status into v_status from guideline_versions where id = g12fx('version_id');
  if v_status <> 'ready_for_review' then
    raise exception 'G12b FAILED: lifecycle_status changed despite the denied approval (now %)', v_status;
  end if;
  raise notice 'G12b PASSED: lifecycle_status unchanged (%)', v_status;

  select count(*) into v_lifecycle_event_count from guideline_lifecycle_events
    where guideline_version_id = g12fx('version_id') and to_status = 'approved';
  if v_lifecycle_event_count <> 0 then
    raise exception 'G12c FAILED: a guideline_lifecycle_events row claims this version was approved (% rows)', v_lifecycle_event_count;
  end if;
  raise notice 'G12c PASSED: no approval lifecycle event was created';

  select count(*) into v_audit_event_count from audit_events
    where resource_type = 'guideline_version' and resource_id = g12fx('version_id')
      and event_type = 'guideline_version.approved';
  if v_audit_event_count <> 0 then
    raise exception 'G12d FAILED: an audit_events row falsely claims this version was approved (% rows)', v_audit_event_count;
  end if;
  raise notice 'G12d PASSED: no audit event falsely claims approval';
end
$$;

-- ----------------------------------------------------------------------------
-- CLEANUP: remove the test-only role (cascades role_permissions and, via
-- organization_memberships' FK to roles, would block deletion if left
-- referenced — delete the membership first). Fixture domain/guideline/etc.
-- rows are left in place for this ephemeral CI database, matching 003's own
-- precedent for its cross-guideline-test residue.
-- ----------------------------------------------------------------------------

delete from organization_memberships
  where user_id = '99999999-9999-9999-9999-999999999999'
    and role_id in (select id from roles where key = 'g12_test_creator_approver');
delete from role_permissions where role_id in (select id from roles where key = 'g12_test_creator_approver');
delete from roles where key = 'g12_test_creator_approver';

drop function g12fx(text);
drop function g12_fixture_set(text, uuid);

\echo 'ALL G-12 REGRESSION TESTS PASSED'
