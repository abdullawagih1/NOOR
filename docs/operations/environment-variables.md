# Environment Variables

Canonical reference for every environment variable Noor uses, across
`apps/web`, `apps/worker`, and CI. No secret values appear in this file —
only names, classification, and where each is validated.

## Naming convention decision

Noor keeps Supabase's **legacy key naming** (`SUPABASE_ANON_KEY` /
`SUPABASE_SERVICE_ROLE_KEY`, exposed to the browser as
`NEXT_PUBLIC_SUPABASE_ANON_KEY`) rather than migrating to the newer
`PUBLISHABLE_KEY` / `SECRET_KEY` system. Reasoning:

* Every working code path (`lib/supabase/{client,server,middleware,
  service-role}.ts`) already uses the legacy names — a rename would touch
  working, already-verified code for zero functional gain.
* The installed SDKs (`@supabase/ssr` 0.12.3, `@supabase/supabase-js`
  2.110.8) fully support the legacy system; it is not deprecated.
* Local Supabase CLI verification (Sprint 0/0.5) confirmed both systems
  coexist on the same project — switching later, if ever needed, doesn't
  require re-provisioning anything.

Revisit this decision only if Supabase formally deprecates the legacy
JWT-based keys, and treat it as a real migration (update code, tests,
`.env.example` files, and this document atomically — see §7 below).

## Variable inventory

| Variable | Application | Public/Secret | Required now | Validated in |
|---|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Web | Public | Yes | `lib/env/public.ts` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Web | Public | Yes | `lib/env/public.ts` |
| `NEXT_PUBLIC_APP_URL` | Web | Public | No (defaults to `http://localhost:3000`) | `lib/env/public.ts` |
| `SUPABASE_URL` | Web (server), Worker | Secret-adjacent (no public equivalent needed) | No — falls back to `NEXT_PUBLIC_SUPABASE_URL` on Web | `lib/env/serverSchema.ts` |
| `SUPABASE_SERVICE_ROLE_KEY` | Web (server), Worker | **Secret** | Yes on Web | `lib/env/serverSchema.ts` |
| `WORKER_BASE_URL` | Web (server) | Public-adjacent (a URL) | No — no call site exists yet (Sprint 1) | `lib/env/serverSchema.ts` |
| `WORKER_INTERNAL_TOKEN` | Web (server), Worker | **Secret** | **Yes on Worker** (crashes worker startup if missing/weak); optional on Web until it calls the Worker | `apps/worker/app/settings.py`; `lib/env/serverSchema.ts` (Web side, optional) |
| `AI_GATEWAY_PROVIDER` / `AI_GATEWAY_API_KEY` | Worker (future) | Secret (key) | No — AI Gateway is inactive | `apps/worker/app/settings.py` (optional) |
| `WORKER_ENV`, `LOG_LEVEL`, `HOST`, `PORT` | Worker | Public | No — safe defaults | `apps/worker/app/settings.py` |
| `WEB_APP_URL`, `ALLOWED_ORIGINS` | Worker | Public | No — defaults to `localhost:3000`; `ALLOWED_ORIGINS` feeds the Worker's CORS middleware | `apps/worker/app/settings.py` |
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD` | CI (future) | Secret | No — not wired into any workflow yet | N/A |
| `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `VERCEL_AUTOMATION_BYPASS_SECRET` | CI (future) | Secret | No — not wired into any workflow yet | N/A |
| `NODE_ENV` | Web | N/A | Framework-provided, not part of this template | — |

## Public vs. secret rule

Only these may ever start with `NEXT_PUBLIC_`: the public app URL, the
Supabase project URL, and the Supabase anon key. Everything else —
service-role key, worker internal token, AI Gateway key, database
password, any CI/deploy token — must never carry that prefix. Verified this
session: `grep -RnE "NEXT_PUBLIC_(SUPABASE_SERVICE_ROLE_KEY|SUPABASE_SECRET_KEY|WORKER_INTERNAL_TOKEN|AI_GATEWAY_API_KEY)"`
across the repo returns nothing.

## Runtime validation architecture

```
apps/web/lib/env/
  public.ts        Browser-safe schema. getPublicEnv() — a function, not a
                    pre-parsed constant, so the throw happens at request/
                    render time, preserving "static routes build without
                    any Supabase config configured" (verified this session).
  serverSchema.ts   The actual server-only zod schema + parse function.
                    Deliberately does NOT import "server-only" so it stays
                    unit-testable outside Next's bundler (that package
                    throws unconditionally in a plain Node/tsx process).
  server.ts         Thin wrapper: `import "server-only"` + re-export of
                    serverSchema.ts. Application code imports THIS file,
                    never serverSchema.ts directly.

apps/worker/app/
  settings.py       pydantic-settings Settings model. WORKER_INTERNAL_TOKEN
                    has no default — a missing or <32-char value crashes
                    the process at import time (verified this session: a
                    real `ValidationError` traceback, not a hypothetical).
```

**Verified boundary enforcement** (this session, not assumed): a throwaway
`"use client"` component was made to import `lib/env/server.ts`, and
`next build` failed with a real webpack error —
*"You're importing a component that needs 'server-only'... not supported
in the pages/ directory"* — then the test file was removed and the build
was re-confirmed clean. The guard is enforced by Next's actual bundler, not
just a code comment.

**Verified secret non-leakage** (this session): built `apps/web` with
canary values (`CANARY-SERVICE-ROLE-SECRET-...`, `CANARY-WORKER-TOKEN-...`)
for every server secret, then grepped the entire `.next/static` output —
none appeared. Note: `lib/supabase/client.ts` (the browser Supabase client)
has no call sites in this codebase yet — every current auth flow uses
Server Actions exclusively — so `NEXT_PUBLIC_SUPABASE_ANON_KEY` doesn't
currently appear in the client bundle either, simply because nothing
client-side reads it yet. That will change the day a Client Component
calls `createClient()` from `lib/supabase/client.ts`, and is expected —
only the *secret* values must never appear there.

## Local setup

```bash
cp apps/web/.env.example apps/web/.env.local
cp apps/worker/.env.example apps/worker/.env
```

Fill in `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` from
`supabase status` (after `supabase start`) or a hosted project. Generate
`WORKER_INTERNAL_TOKEN` with `openssl rand -hex 32` and use the **same**
value in both `apps/web/.env.local` and `apps/worker/.env` once the Web app
actually calls the Worker (Sprint 1).

Both files are git-ignored (`.gitignore`: `.env`, `.env.*`, `!.env.example`)
— confirmed this session via `git check-ignore -v`.

## Vercel setup (Preview)

Set in Vercel Project Settings → Environment Variables, scoped to
**Preview**, pointing at a **Development** Supabase project (never
Production):

* `NEXT_PUBLIC_APP_URL` — the Preview deployment's own URL
* `NEXT_PUBLIC_SUPABASE_URL`
* `NEXT_PUBLIC_SUPABASE_ANON_KEY`
* `SUPABASE_SERVICE_ROLE_KEY` — mark **Sensitive** in Vercel
* `WORKER_BASE_URL` / `WORKER_INTERNAL_TOKEN` — only once the Worker is
  actually hosted and the Web app has a real call site

Changing any of these triggers a redeploy on the next push, or use
`vercel redeploy` to pick them up immediately without a code change.

## Worker hosting setup

Whatever platform hosts `apps/worker` needs the same `.env.example`
variables as real values, with `WORKER_INTERNAL_TOKEN` matching what's
configured in the Web app's `WORKER_INTERNAL_TOKEN`. See
`docs/operations/worker-deployment.md`.

## GitHub Actions secrets (future — not currently required)

None of these are wired into `.github/workflows/pr.yml` today — every
current CI job (`web`, `clinical-schemas`, `worker`, `database`,
`secret-scan`) runs without any hosted credential, by design (mission
requirement: keep ordinary PR checks runnable without hosted secrets).
They'll be needed only when a future workflow deploys or runs hosted
smoke tests:

```
SUPABASE_ACCESS_TOKEN
SUPABASE_PROJECT_REF
SUPABASE_DB_PASSWORD
VERCEL_TOKEN
VERCEL_ORG_ID
VERCEL_PROJECT_ID
VERCEL_AUTOMATION_BYPASS_SECRET
```

Add them as GitHub Actions **secrets** (Settings → Secrets and variables →
Actions), never as plain **variables**, and never reference them in a
workflow step that also touches client-bundled code.

## Rotation guidance

* **Supabase service-role key / anon key:** rotate from the Supabase
  dashboard (Project Settings → API). Update Vercel env vars immediately
  after — the old key keeps working until rotated there too, so there's no
  forced-downtime window if done promptly.
* **`WORKER_INTERNAL_TOKEN`:** generate a new value (`openssl rand -hex
  32`), update it in both the Web app's and the Worker's hosting
  environment in the same change window (a mismatch means every
  Web→Worker call gets a 403 until both sides agree).
* **AI Gateway key:** rotate per-provider; not yet active, so no live
  rotation procedure exists yet.

## Incident response: a secret leaked

1. Rotate the leaked credential immediately at its source (Supabase
   dashboard, provider console) — this invalidates it regardless of where
   it leaked to.
2. Update every environment that held it (local `.env.local`/`.env`,
   Vercel, Worker hosting) with the new value.
3. If it leaked into git history (not just a live log/terminal), treat the
   repository history as compromised for that credential — rotation
   (step 1) already neutralizes it; history rewriting is a separate,
   optional cleanup and does not substitute for rotation.
4. Check Supabase/provider audit logs for any access during the exposure
   window.
5. Document the incident (what leaked, when rotated, blast-radius
   assessment) — do not skip this even if rotation was fast.

## Variables not required yet

`AI_GATEWAY_PROVIDER`, `AI_GATEWAY_API_KEY`, `WORKER_BASE_URL` (Web side),
`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` (Worker side — declared in
`apps/worker/.env.example` for when Sprint 1 wires a real Supabase call,
but nothing reads them today), and all seven CI secrets listed above. None
of these being unset should ever break a build or test run — verified this
session (`WORKER_BASE_URL`/`WORKER_INTERNAL_TOKEN` unset does not fail
`getServerEnv()`; AI Gateway fields are optional in the Worker's
`Settings`).
