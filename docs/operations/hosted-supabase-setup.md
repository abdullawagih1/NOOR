# Hosted Supabase Setup

Status: **Connected and verified.** The "Noor Development" project is
linked, all migrations are applied, and Auth/RLS/Storage/Audit are all
verified against it with real JWTs — see
`docs/verification/sprint-0.5-hosted-verification.md` for the complete,
command-by-command evidence. This document is now the reproducible
reference for repeating or extending that setup, not a blocked TODO.

## Project

* Name: **Noor Development**
* Ref: `quohfsaqeqzbbvmrhmbr`
* Region: `eu-west-3`
* Postgres: 17 (`17.6.1.147`)
* Environment: Development (confirmed, not Production)

## Reproducing the connection

```bash
# Authenticate (interactive) or export SUPABASE_ACCESS_TOKEN for a
# non-interactive session — never commit or print the token.
supabase login
# or: export SUPABASE_ACCESS_TOKEN=<your personal access token>

supabase link --project-ref quohfsaqeqzbbvmrhmbr

# Review before pushing — never push blind
supabase migration list --linked

supabase db push --linked
```

## Migrations applied (in order)

```
0001_identity_and_rls.sql          identity/tenancy/RLS foundation
0002_sprint0_auth_hardening.sql    permission seeds, org-immutability + audit triggers
0003_storage_foundation.sql        5 private buckets, org-scoped storage RLS
0004_revoke_anon_table_grants.sql  fixes a real finding from hosted verification —
                                    see docs/verification/sprint-0.5-hosted-verification.md
```

`0004` exists because hosted verification found `anon` held full CRUD
grants on every table (a legacy Supabase project-creation default). RLS
already blocked practical access, but the migration closes the
grant-layer gap too — read the verification doc for the full root-cause
account before assuming this is fixed on any *other* hosted project you
connect later; re-run the same check:

```sql
select count(*) from information_schema.table_privileges
where grantee = 'anon' and table_schema = 'public';
-- expect 0 after 0004 is applied
```

## Re-running hosted verification

The exact scripts used this session (Auth, RLS, Audit, Storage, cleanup)
are not committed to the repo — they were scratch Python scripts
constructed per-session to avoid ever hardcoding project-specific
synthetic-data UUIDs into version control. To re-verify:

1. Apply migrations (above).
2. Create 2 synthetic orgs + 8 synthetic users covering: admin/clinician/
   reviewer/quality roles in one org, an admin in a second org (cross-tenant
   check), a suspended member, a removed member, and a no-membership user.
3. Sign in each active user via `POST /auth/v1/token?grant_type=password`
   to get a real JWT.
4. Exercise `/rest/v1/*` with each JWT for the RLS/authorization/audit/
   feature-flag checks listed in `docs/verification/sprint-0.5-hosted-verification.md`.
5. Exercise `/storage/v1/object/*` for the storage checks.
6. Clean up: delete audit test rows first (the append-only trigger blocks
   deletion — use the documented `set local
   noor.allow_audit_maintenance = 'true'` override in the same
   transaction), then delete the synthetic organizations (cascades to
   memberships/settings/flags/access_reviews), then delete the synthetic
   auth users.

## Auth URL configuration (applied this session)

```
Site URL:      https://noor-preview-dev.vercel.app
Redirect URLs:
  http://localhost:3000/auth/callback
  http://localhost:3000/update-password
  https://noor-preview-dev.vercel.app/auth/callback
  https://noor-preview-dev.vercel.app/update-password
```

No wildcards. `noor-preview-dev.vercel.app` is a Vercel alias explicitly
re-pointed to the latest Preview deployment after every deploy (see
`docs/operations/vercel-preview-deployment.md`) — this avoids needing to
update Supabase's allowlist every time Vercel's ephemeral per-deployment
URL changes.

Set/inspect via the Supabase Management API (`PATCH
/v1/projects/{ref}/config/auth` with `site_url` and `uri_allow_list`), or
the dashboard (Authentication → URL Configuration).

## Environment variables (set in Vercel Preview this session)

```
NEXT_PUBLIC_SUPABASE_URL=https://quohfsaqeqzbbvmrhmbr.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key — Vercel "Preview" scope>
SUPABASE_URL=https://quohfsaqeqzbbvmrhmbr.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service role key — Vercel "Preview" scope, Sensitive>
```

Never reuse these Development-project values for a future Production
environment — a separate hosted project should back Production when that
work begins.

## Known limitation: email rate limiting (no custom SMTP)

This Development project has no custom SMTP provider configured, so
GoTrue's default (low) email-send quota applies. Repeated
`/auth/v1/recover` calls against real accounts can 429 once exhausted,
while calls against non-existent addresses never consume the quota (no
email is ever queued for them) — this is a genuine characteristic of an
SMTP-less project, not an application bug; Noor's own UI never branches on
it (see `docs/verification/sprint-0.5-hosted-verification.md`). Configure
custom SMTP (Authentication → Email → SMTP Settings) before Controlled
Beta if password-reset email volume needs to exceed the default quota.
