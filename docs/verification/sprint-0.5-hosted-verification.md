# Sprint 0.5 — Hosted Verification Record

Every command and result below was actually run against the real hosted
"Noor Development" Supabase project and the real Vercel Preview deployment
this session — nothing here is inferred or assumed. No secret values
appear in this document; safe metadata (project ref, region, counts,
policy names) is recorded where useful.

## Project identity

* Name: **Noor Development**
* Ref: `quohfsaqeqzbbvmrhmbr`
* Region: `eu-west-3`
* Postgres: `17.6.1.147` (engine 17)
* Status at verification time: `ACTIVE_HEALTHY`
* Environment: Development (confirmed — not Production)

## Migrations

```
$ supabase migration list --linked   (before)
→ 0001, 0002, 0003 all pending (local set, remote empty)

$ supabase db push --linked --yes
→ Applying migration 0001_identity_and_rls.sql...
→ Applying migration 0002_sprint0_auth_hardening.sql...
→ Applying migration 0003_storage_foundation.sql...
→ Finished supabase db push.

$ supabase migration list --linked   (after)
→ 0001, 0002, 0003 all local==remote
```

A **new migration was written and applied this session**:
`0004_revoke_anon_table_grants.sql` — see "Finding: unnecessary anon
grants" below for why.

## Hosted database structure verification

| Object | Expected | Hosted Result | Status |
|---|---|---|---|
| 10 public tables (organizations, organization_settings, profiles, roles, permissions, role_permissions, organization_memberships, access_reviews, audit_events, feature_flags) | All present | All present | ✅ |
| RLS enabled on all 10 | `rowsecurity = true` everywhere | `true` on all 10 | ✅ |
| Triggers: `trg_audit_events_no_update`, `trg_audit_events_no_delete`, `trg_prevent_membership_org_reassignment` | 3 triggers | 3 triggers present, correct tables/timing | ✅ |
| `permissions` seeded | 7 rows | 7 | ✅ |
| `role_permissions` mapped | 14 rows | 14 | ✅ |
| `roles` seeded | 9 roles | 9 (auditor, clinical_pharmacist, clinical_reviewer, clinician, knowledge_manager, organization_admin, platform_support, quality_manager, safety_officer) | ✅ |
| Storage buckets | 5, all private | 5 present, all `public: false` | ✅ |
| Storage policies on `storage.objects` | 2 (SELECT, INSERT, org-scoped) | `noor_buckets_select_own_org`, `noor_buckets_insert_own_org` | ✅ |
| Security-definer functions pin `search_path` | 3 functions | `current_active_organization_ids`, `has_role_in_organization`, `has_permission_in_organization` all `search_path=public` | ✅ |

## Finding: unnecessary `anon` grants (discovered, fixed, verified)

Hosted verification found `anon` held **full CRUD** (SELECT, INSERT,
UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER) on every public table, plus
a project-wide default-privilege entry that would apply the same to any
future table. Root cause: this hosted project inherited Supabase's legacy
`auto_expose_new_tables` default at creation time (the always-revoked
behavior is scheduled to become the permanent default, per Supabase's own
deprecation note — this project predates that).

**Impact assessment:** RLS already made this practically inert — every
policy requires `auth.uid()` to resolve to an active membership, which is
never true for `anon`. Verified directly: `anon` SELECT on `organizations`
returned `200 []` (empty, not real data) even before the fix. This was a
defense-in-depth gap, not a live data exposure.

**Fix:** `supabase/migrations/0004_revoke_anon_table_grants.sql` — revokes
all `anon` privileges on every current table and closes the default-ACL
entry for future ones (guarded: no-op against the plain-Postgres CI
container, which has no `anon` role at all — verified by re-applying all 4
migrations there and re-running both RLS test files, 11/11 still pass).

**Verified after fix:**
```
$ (SQL) select count(*) from information_schema.table_privileges where grantee='anon' and table_schema='public';
→ 0

$ curl .../rest/v1/organizations -H "apikey: <anon>" -H "Authorization: Bearer <anon>"
→ 401 {"code":"42501","message":"permission denied for table organizations"}
```
(Previously: `200 []`. Now genuinely permission-denied at the grant layer too — matching the defense-in-depth posture the local Supabase stack already had in prior sessions.)

## Synthetic hosted test data

2 organizations, 8 users, created via the GoTrue admin API + direct SQL
(profiles/memberships), all under the `noor-hosted-test+*@example.test`
address pattern:

```
admin_alpha        organization_admin  Org Alpha   active
clinician_alpha     clinician           Org Alpha   active
reviewer_alpha       clinical_reviewer   Org Alpha   active
quality_alpha        quality_manager     Org Alpha   active
admin_beta          organization_admin  Org Beta    active
suspended_alpha      clinician           Org Alpha   suspended
removed_alpha        clinician           Org Alpha   removed
no_membership        (none)              (none)      —
```

All deleted after verification — see "Cleanup" below.

## Hosted Authentication (real GoTrue calls)

| Test | Result |
|---|---|
| Valid email/password login succeeds | ✅ PASS |
| Invalid password fails safely (400) | ✅ PASS |
| Anonymous user has no tenant access (401, post-fix) | ✅ PASS |
| Session issued correctly (access_token + refresh_token) | ✅ PASS |
| Session refresh works (refresh_token grant) | ✅ PASS |
| Logout succeeds (204) | ✅ PASS |
| Public signup: recorded actual API status, not assumed | ℹ️ INFO — Noor's own invite-only policy is enforced by omitting a signup UI in the app, not by disabling Supabase's signup API at the project level; see `KNOWN_LIMITATIONS.md` |
| Password-reset request: investigated a real status difference | See "Finding: email rate limiting" below |

### Finding: email rate limiting affects raw `/recover` status codes

This Development project has no custom SMTP configured. A first
back-to-back test showed existing-user `/recover` returning `400`/`429`
while a non-existent address returned `200` — investigated rather than
assumed:

```
$ curl .../auth/v1/recover  (existing, fresh address)  → 429 over_email_send_rate_limit
$ curl .../auth/v1/recover  (fresh non-existent address) → 200 {}
```

Root cause: GoTrue's default per-project email-send quota (no custom SMTP)
is consumed only when an email actually gets queued for a real account;
non-existent addresses never trigger a send and never consume it. This is
a genuine, real characteristic of an SMTP-less Development project — not
an application defect. Critically, **Noor's own `requestPasswordReset()`
server action never branches on this response** (`apps/web/lib/auth/actions.ts`):
it always redirects to the same generic `?sent=1` page regardless of what
the Supabase API returns. The product surface remains non-enumerating;
only a caller hitting GoTrue directly with the public anon key could
observe the difference. Recorded as a known limitation, with a
recommendation to configure custom SMTP before Controlled Beta.

## Hosted RLS (real JWTs, not superuser queries)

| Category | Test | Result |
|---|---|---|
| Organization isolation | User in Org Alpha reads Org Alpha | ✅ |
| | User in Org Alpha CANNOT read Org Beta | ✅ |
| | User in Org Beta CANNOT read Org Alpha | ✅ |
| | Requested `organization_id` filter cannot bypass RLS | ✅ |
| Membership state | Active membership accepted | ✅ |
| | Suspended membership denied | ✅ |
| | Removed membership denied | ✅ |
| | No-membership user denied | ✅ |
| Authorization | Clinician permission works | ✅ |
| | Admin permission works | ✅ |
| | Reviewer permission works | ✅ |
| | Quality permission works | ✅ |
| | Non-admin cannot self-assign a role (INSERT denied) | ✅ |
| Feature flags | Org-scoped (Alpha cannot read Beta's flag) | ✅ |
| | Unauthorized mutation denied (non-admin PATCH no-op) | ✅ |

All via real `POST /auth/v1/token?grant_type=password` → real JWT →
`GET/POST/PATCH /rest/v1/...` with that JWT as `Authorization: Bearer`.

## Hosted Audit

| Test | Result |
|---|---|
| Authorized path can insert an audit event | ✅ |
| Normal authenticated user (org_admin) cannot UPDATE | ✅ |
| Normal authenticated user (org_admin) cannot DELETE | ✅ |
| Non-privileged user cannot read | ✅ |
| Cross-tenant audit read denied | ✅ |
| Privileged role (org_admin) CAN read own org's event; actor/org/correlation/timestamp preserved | ✅ |

**A genuine, unplanned proof of the append-only trigger** happened during
cleanup: deleting the test audit row via the Management API (a
superuser-equivalent connection) was **rejected** by
`prevent_audit_event_mutation()` with its documented error message,
exactly as designed. Cleanup only succeeded after explicitly setting the
documented maintenance override (`set local noor.allow_audit_maintenance
= 'true'`) in the same transaction — proving both the block and the
escape hatch are real on the hosted project, not just locally.

## Hosted Storage

| Test | Result |
|---|---|
| Bucket is private (public URL read fails) | ✅ |
| Anonymous upload fails | ✅ |
| Anonymous read fails | ✅ |
| Authorized upload to own org's path succeeds | ✅ |
| Authorized read of own org's object succeeds, content matches | ✅ |
| Org Alpha cannot upload into Org Beta's path | ✅ |
| Org Alpha cannot read Org Beta's object | ✅ |
| Path-traversal-style object key rejected | ✅ |

All 5 buckets confirmed private; policies confirmed org-scoped via the
`(storage.foldername(name))[1]` first-path-segment check against the
caller's active organization membership.

## Supabase Auth URL configuration

```
site_url: https://noor-preview-dev.vercel.app
uri_allow_list:
  http://localhost:3000/auth/callback
  http://localhost:3000/update-password
  https://noor-preview-dev.vercel.app/auth/callback
  https://noor-preview-dev.vercel.app/update-password
```

No wildcards. `noor-preview-dev.vercel.app` is a stable Vercel alias this
session created and explicitly re-points to the latest Preview deployment
after each redeploy (`vercel alias set <deployment> noor-preview-dev.vercel.app`)
— chosen specifically because Vercel's per-deployment URLs are ephemeral
and would otherwise require updating Supabase's allowlist on every deploy.

## Vercel Preview configuration

* Project already linked from a prior session (`noor`,
  `prj_fyVYZ6Dms0NX6E2s7ATR6C0CYweG`), Root Directory `apps/web`, framework
  `nextjs` — both confirmed still correct.
* Preview environment variables set (values encrypted, never displayed):
  `APP_ENV`, `NEXT_PUBLIC_APP_URL`, `NEXT_PUBLIC_SUPABASE_URL`,
  `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_URL`,
  `SUPABASE_SERVICE_ROLE_KEY` — all scoped to **Preview only**, pointing at
  the **Development** Supabase project.
* Redeployed: `vercel deploy --target=preview` →
  `dpl_GrVMQtiTpxww7ndvVvq94RbxBTxR`, confirmed via `vercel inspect`:
  `target: preview`, `status: Ready`.
* Deployed from a clean local working tree at commit `cb49558` (no
  git-linked build — this project deploys via CLI, not a connected GitHub
  integration, so there's no automatic commit-SHA association; content
  correctness is guaranteed by deploying from a confirmed-clean tree at
  that exact commit).

## Vercel Deployment Protection — preserved, bypass secret blocked

Deployment Protection remains **enabled** (`ssoProtection.deploymentType:
all_except_custom_domains`) — not disabled, per the mission's explicit
instruction. **"Protection Bypass for Automation" could not be configured
this session** — it has no CLI command and the REST API returned `400
should NOT have additional property` for the most likely field name and
`404` for two plausible dedicated endpoints. This is a dashboard-only
action:

> Vercel dashboard → `noor` project → Settings → Deployment Protection →
> "Protection Bypass for Automation" → enable it. Vercel generates
> `VERCEL_AUTOMATION_BYPASS_SECRET`. Pass it to
> `scripts/smoke-test-web.mjs` as `BYPASS_TOKEN` to run the full
> authenticated-content checks.

## Hosted HTTP smoke test (real, body-content-aware)

```
$ BASE_URL=https://noor-preview-dev.vercel.app node scripts/smoke-test-web.mjs
```

Result: the 4 protected-route checks passed (Vercel's own protection
issues a redirect too, which the test correctly recognizes and labels
rather than conflating with Noor's `/login` redirect). The 6 direct-content
checks (`/login`, `/forgot-password`, `/403`, `/access-denied`, `/`,
`/design-system`) correctly **failed with an explicit "blocked by Vercel
Deployment Protection" message** rather than reporting a false pass — this
is the fix for the exact false-positive bug found in the prior session
(where `fetch()` auto-following the SSO redirect produced misleading
"200 OK" passes). The script now inspects the `Location` header for
`vercel.com/sso-api` and refuses to call that a pass.

**Full authenticated hosted-Preview HTTP verification is blocked pending
the one dashboard action above** — everything the API/CLI can reach was
verified.

## Cleanup

```
$ (GoTrue admin API) DELETE 8 synthetic users → all succeeded (admin_alpha
  required the audit-maintenance override first, per above)
$ (SQL) DELETE FROM organizations WHERE id IN (...) → both deleted,
  cascaded to memberships/settings/feature_flags/access_reviews
$ (SQL) final zero-count check across orgs/profiles/memberships/flags/
  audit/auth.users matching the test pattern → all 0
```

Database confirmed in a clean Development state — no leftover synthetic
fixtures, no privileged test accounts, no temporary bypass mechanisms in
code.

## Local re-verification (same session, before and after migration 0004)

```
$ npm ci && npm run lint/typecheck/test/build --workspace=apps/web  → all green
$ npm run typecheck/test --workspace=packages/clinical-schemas       → 6/6
$ npm run typecheck --workspace=packages/ui                          → clean
$ python -m compileall apps/worker && pytest apps/worker              → 9/9
$ (docker) plain Postgres 16: all 4 migrations + seed + both RLS
  test files → 11/11, both before and after adding migration 0004
```
