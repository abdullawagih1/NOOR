# Database Schema — Sprint 0

Source: `supabase/migrations/0001_identity_and_rls.sql`,
`0002_sprint0_auth_hardening.sql`, `0003_storage_foundation.sql`. This
document is updated in the same PR as any migration change — see Definition
of Done.

## Tables implemented in Sprint 0

| Table | Purpose | RLS |
|-------|---------|-----|
| `organizations` | Tenant root | Enabled — visible to active members only |
| `organization_settings` | Per-org config (default domain, language) | Enabled — visible to active members, writable by `organization_admin` |
| `profiles` | 1:1 with `auth.users` | Enabled — self + shared-org read, self write |
| `roles` / `permissions` / `role_permissions` | Static RBAC reference data, seeded in 0002 | Enabled — readable by any authenticated user |
| `organization_memberships` | User ↔ org ↔ role, with `status` | Enabled — shared-org read, `organization_admin`-only write; `organization_id` immutable after insert (trigger, 0002) |
| `access_reviews` | Membership review audit trail | Enabled — `organization_admin` / `auditor` only |
| `audit_events` | Append-only audit log | Enabled — `auditor` / `organization_admin` / `safety_officer` read only; UPDATE/DELETE revoked from `public` **and** blocked by trigger for every runtime role (0002) |
| `feature_flags` | Emergency shutdown / gradual rollout | Enabled — member read, `organization_admin` write |
| `storage.buckets` (5 buckets) | `guideline-originals`, `guideline-processed`, `evaluation-assets`, `generated-reports`, `temporary-uploads` | Private; RLS on `storage.objects` restricts to the caller's own `organization_id` path prefix (0003) — only created when the `storage` schema exists (real Supabase, not the CI Postgres container) |

## Permission model (0002)

`role_permissions` was declared in 0001 but never seeded — no route could
actually be authorized against a permission key. 0002 seeds:

`workspace.clinician.access`, `workspace.admin.access`,
`workspace.reviewer.access`, `workspace.quality.access`,
`organization.members.read`, `organization.members.manage`, `audit.read`

and maps each of the 9 roles from 0001 to the subset it should hold (see the
migration for the exact mapping). `has_permission_in_organization(org_id,
permission_key)` mirrors `has_role_in_organization` for use in RLS policies
and application code.

## Deliberately not yet created

Guideline/document/chunk/retrieval/generation tables from the Architecture
Report §9.2–9.5 are **Sprint 1 scope** (see MASTER_BACKLOG.md). Creating them
now without the ingestion and retrieval code that uses them would add
unverified surface area — Sprint 0 favors a small, fully-tested foundation
over a large, unverified schema.

## Key design decisions

* **Tenancy:** every tenant-owned table carries or resolves to
  `organization_id`. No table relies on a client-supplied org ID for
  filtering — see `current_active_organization_ids()`.
* **Membership status:** `active | suspended | removed`. All RLS policies
  check `status = 'active'`, not merely row existence — this is what makes
  RLS tests 3 and 4 (`supabase/tests/rls/001_tenant_isolation.sql`) matter.
* **Audit immutability — honest scope.** `audit_events` has `UPDATE`/`DELETE`
  revoked from `public` (0001) **and** blocked by a `BEFORE UPDATE/DELETE`
  trigger (0002) that fires for every runtime role, including the table
  owner and Supabase's `service_role` — not RLS-dependent, since
  `service_role` bypasses RLS by design. This is append-only for every role
  the application ever uses, but it is **not absolute**: a database
  superuser with a direct, privileged session can still execute
  `set local noor.allow_audit_maintenance = 'true';` before an UPDATE/DELETE
  to intentionally override it. That override is a session-local Postgres
  GUC reachable only via a direct DB session (`psql`, Supabase Studio SQL
  editor) — it cannot be set through PostgREST or any application code path,
  including one holding the service-role key over HTTP. Any use of the
  override should be logged out-of-band (this is a process control, not a
  database one) since the DB itself cannot audit an audit-bypass. See
  `supabase/tests/rls/002_auth_hardening.sql` (tests 3, 3b, 4) for the
  proof that both the block and the override work as described.
* **Membership org-immutability:** a trigger (0002) rejects any UPDATE that
  changes `organization_memberships.organization_id`, closing a gap where
  the `memberships_update_admin` RLS policy alone would have let an admin
  reassign a membership row to a different organization they also administer.
* **`auth.uid()` compatibility shim:** see ADR 0004. Written to be a no-op
  against real Supabase. Verified as a genuine no-op: `supabase start`
  applies 0001 and the shim's `create table auth.users` / `create function
  auth.uid()` block is skipped (real Supabase already defines both).

## Verified

* Plain Postgres 16 (matches the CI `database` job): all three migrations
  apply cleanly, seed loads, both RLS test files pass (11/11 assertions).
* Real local Supabase (`supabase start`, CLI v2.109.1): all three migrations
  apply automatically on start, both RLS test files re-run against the
  **real** `authenticated` role and real GoTrue-backed `auth.uid()` (via
  `request.jwt.claims`, not just the plain-Postgres `request.jwt.claim.sub`
  shim) — 11/11 pass. Storage buckets and their RLS policies were confirmed
  present (`select * from storage.buckets`, `pg_policies` on
  `storage.objects`). A real end-to-end request was also run: a GoTrue user
  was created via the admin API, signed in for a real JWT, and that JWT used
  against the live PostgREST endpoint (`/rest/v1/organizations`) correctly
  returned only the caller's own organization. An anonymous PostgREST
  request to the same endpoint was correctly rejected (401, `permission
  denied for table organizations`).
* Command reference for reproducing local Supabase verification is in
  `README.md` → "Database / RLS tests".
