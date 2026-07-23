-- ============================================================================
-- Noor V1 — Synthetic seed data for local/dev/test only.
-- No real patient, clinician, or organization data. Two orgs, four users,
-- covering active/suspended/removed membership states for RLS testing.
-- ============================================================================

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'admin.alpha@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'clinician.alpha@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'admin.beta@example.test'),
  ('44444444-4444-4444-4444-444444444444', 'suspended.alpha@example.test'),
  ('55555555-5555-5555-5555-555555555555', 'removed.alpha@example.test')
on conflict (id) do nothing;

insert into profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'Admin Alpha'),
  ('22222222-2222-2222-2222-222222222222', 'Clinician Alpha'),
  ('33333333-3333-3333-3333-333333333333', 'Admin Beta'),
  ('44444444-4444-4444-4444-444444444444', 'Suspended Alpha'),
  ('55555555-5555-5555-5555-555555555555', 'Removed Alpha')
on conflict (id) do nothing;

insert into organizations (id, name, slug) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Org Alpha', 'org-alpha'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Org Beta', 'org-beta')
on conflict (id) do nothing;

insert into organization_settings (organization_id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
on conflict (organization_id) do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', id, 'active'
from roles where key = 'organization_admin'
on conflict do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', id, 'active'
from roles where key = 'clinician'
on conflict do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '33333333-3333-3333-3333-333333333333', id, 'active'
from roles where key = 'organization_admin'
on conflict do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '44444444-4444-4444-4444-444444444444', id, 'suspended'
from roles where key = 'clinician'
on conflict do nothing;

insert into organization_memberships (organization_id, user_id, role_id, status)
select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555', id, 'removed'
from roles where key = 'clinician'
on conflict do nothing;
