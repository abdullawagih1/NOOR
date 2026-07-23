# Hosted Supabase Setup

Status as of Sprint 0.5: **BLOCKED — CREDENTIALS REQUIRED**. Local
verification against a real Supabase CLI stack is done and passing (see
`PROJECT_STATE.md`) — this document is the exact, reproducible path from
there to a hosted Development project.

## Why this is blocked

`supabase login` opens an interactive browser OAuth flow. There is no
`SUPABASE_ACCESS_TOKEN` in this environment, and no browser to complete the
flow with. One of these unblocks it:

1. Run `supabase login` yourself in a terminal with a browser, then tell
   whoever's driving this to continue from step 2 below.
2. Generate a personal access token at
   `https://supabase.com/dashboard/account/tokens` and provide it as
   `SUPABASE_ACCESS_TOKEN` for the session doing this work.

## Steps once authenticated

```bash
# 1. Create (or identify) the Development project
supabase projects create "Noor Development" --org-id <YOUR_ORG_ID> --region <closest-region> --db-password <GENERATED_STRONG_PASSWORD>
# Note the returned project ref (e.g. abcdefghijklmnop) — this is not a secret,
# it's a public identifier, safe to record in docs.

# 2. Link this repo to it
supabase link --project-ref <PROJECT_REF>

# 3. Review the diff before pushing — never push blind
supabase db diff

# 4. Push migrations (0001, 0002, 0003 — applies in order, idempotent guards
#    already in place for anything that would conflict with GoTrue-managed
#    schema)
supabase db push

# 5. Re-run the exact same RLS test files used for local verification,
#    now against the hosted project's connection string:
psql "$(supabase db url --project-ref <PROJECT_REF>)" -v ON_ERROR_STOP=1 -f supabase/tests/rls/001_tenant_isolation.sql
psql "$(supabase db url --project-ref <PROJECT_REF>)" -v ON_ERROR_STOP=1 -f supabase/tests/rls/002_auth_hardening.sql
```

## What "done" looks like

* All 3 migrations applied with no manual intervention.
* Both RLS test files pass unmodified (11/11 assertions) — same numbers as
  local verification.
* `select * from storage.buckets;` shows all 5 buckets, all `public = false`.
* Record here (not with real secret values, just confirmation):
  * Project ref: _______
  * Region: _______
  * Database version: _______
  * Auth email provider configured: yes/no
  * Redirect URLs allow-listed (`<APP_URL>/auth/callback`): yes/no

## Environment variables to set (Vercel Preview/Production, never committed)

```
NEXT_PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key from project settings>
SUPABASE_SERVICE_ROLE_KEY=<service role key — server-only, Vercel "Sensitive" env var>
NEXT_PUBLIC_APP_URL=<the deployment's own URL>
```

Set Development/Preview/Production values separately in Vercel — never
reuse a Production service-role key in Preview.

## Redirect URL configuration (Supabase Auth settings)

Add every deployment origin's `/auth/callback` to Supabase's allowed
redirect URLs (Authentication → URL Configuration):

```
http://localhost:3000/auth/callback          (local dev)
https://<preview-url>.vercel.app/auth/callback
https://<production-domain>/auth/callback
```

Without this, `resetPasswordForEmail`'s `redirectTo` will be silently
rejected by Supabase (the email link will redirect to the site URL instead
of the callback route).
