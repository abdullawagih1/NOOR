# Guideline Registry — Authorization Model

Source: `supabase/migrations/0005_guideline_registry_and_lifecycle.sql`,
`apps/web/lib/auth/permissions.ts`, `apps/web/lib/guidelines/actions.ts`.

## Defense in depth (ADR 0003)

Four independent layers, none of which alone is trusted as sufficient:

1. **Permission-aware UI** — `apps/web/lib/guidelines/actions.ts` calls
   `requirePermission(...)` before attempting any mutation; the Admin/
   Reviewer detail pages only render an action's button/form when the
   signed-in user's `permissionKeys` include the relevant permission.
2. **Route-level session gate** — `/knowledge/*` (registry + detail),
   `/reviewer/guidelines`, `/clinician/knowledge` are all
   `force-dynamic` and resolve identity/membership before rendering
   anything (`requireActiveMembership`/`requirePermission`).
3. **Database RLS** — every table's SELECT policies are scoped by
   organization membership and, for `guideline_versions`, further scoped by
   `guidelines.read_all` vs. default (`active`-only).
4. **Database function-level checks** — every write-path function
   independently re-derives `auth.uid()` and calls
   `has_permission_in_organization`, so even a caller who somehow reached
   the RPC without going through the app's own permission gate is still
   blocked server-side.

## Tenant isolation

Every table carries `organization_id`; every SELECT policy filters through
`current_active_organization_ids()`; every write function resolves
`organization_id` either from an explicit, permission-checked parameter
(creates) or from the existing row itself (updates — never a client
parameter). Composite foreign keys make cross-tenant references
structurally impossible for domain/authority/guideline/version
relationships (see `docs/database/guideline-registry-schema.md`). Verified:
`supabase/tests/rls/003_guideline_registry.sql` TEST 4 (cross-tenant
create denied), TEST 21/21b/21c (suspended/removed/anonymous denied read).

## Clinician visibility is a database guarantee, not a UI filter

`guideline_versions_select_active_for_members` is the only SELECT policy a
caller without `guidelines.read_all` ever matches, and it requires
`lifecycle_status = 'active'`. A clinician cannot read a draft, a
pending-review, an approved-but-not-yet-active, a superseded, or a
withdrawn version by any query — not because the Clinician UI doesn't
render them, but because Postgres never returns those rows to that
session. Verified: TEST 5 (clinician cannot see a draft version) /
TEST 5b (privileged role can) / TEST 13 (clinician sees the version once
active).

## Review/approval separation and self-action prevention

* **Self-review is blocked by a trigger** (`prevent_self_review`), not
  only by role assignment — a version's own `created_by` can never appear
  as `guideline_reviews.reviewer_id`, regardless of what permissions that
  user holds.
* **Self-approval is blocked inside `transition_guideline_version`** —
  `ready_for_review → approved` explicitly checks `auth.uid() <>
  guideline_versions.created_by` before proceeding, independent of the
  reviewer-vs-approver role split.
* **Approval requires a prior recommending review** — `ready_for_review →
  approved` checks `exists (select 1 from guideline_reviews where
  guideline_version_id = ... and review_status = 'recommended_for_approval')`
  before allowing the transition.

Verified: TEST 8 (non-reviewer cannot submit a review), TEST 9 (a
legitimate, non-creator reviewer can), TEST 10 (non-approver cannot
approve), TEST 11 (approval without any recommending review fails), TEST
12/12b (a non-creator approver succeeds through review → approve →
activate).

## Version immutability

`active`, `superseded`, and `withdrawn` versions cannot be mutated by any
client write path — there is no RLS UPDATE policy on `guideline_versions`
for `authenticated` at all, for **any** lifecycle state, and
`update_guideline_version_draft()` itself refuses to run unless the
target row's `lifecycle_status = 'draft'`. Content correction after
activation always means creating a new version through the normal
draft → review → approval → activation pipeline, never editing released
content. Verified: TEST 14 (raw UPDATE against an active version rejected).

## Audit behavior

Every mutating function writes an `audit_events` row (organization-scoped,
`actor_id = auth.uid()`, `correlation_id`, safe metadata only — no raw
clinical content, no secrets). Lifecycle transitions additionally write a
`guideline_lifecycle_events` row carrying `from_status`/`to_status`/
`reason`. Both `guideline_reviews` and `guideline_lifecycle_events` are
append-only for every runtime role (REVOKE + trigger, mirroring the
`audit_events` pattern from migration 0002) — not just for the
`authenticated` role, but for the table owner and `service_role` too, with
the same documented, narrow `noor.allow_audit_maintenance` override.
Verified: TEST 19 (lifecycle-event UPDATE blocked without the override),
TEST 20 (audit events actually recorded for a real transition sequence —
6 rows for one version's created → submitted → reviewed → approved →
activated → withdrawn history).

## Remaining risks / known scope limits

* Self-approval-by-a-creator-who-also-holds-`guidelines.approve` is blocked
  by explicit code (not just role separation), but this exact combination
  isn't exercised end-to-end by the seeded RLS test fixtures (no seeded
  user both authors content and holds `guidelines.approve`) — verified by
  code review of the transition function, not by a live test case. Noted
  in `docs/verification/sprint-1-guideline-registry-verification.md`.
* No document/file-level authorization exists yet (no upload, no storage
  object tied to a guideline version) — that arrives with the
  document-processing task (ADR 0007) and will need its own authorization
  review at that time.
