# Security

## Reporting

This is a pre-release internal project (Sprint 0). Report concerns directly
to the project owner rather than a public issue until a disclosure process
exists.

## Controls implemented in Sprint 0

* Row-Level Security enabled on every table in `supabase/migrations/0001_*`
  and `0002_*`, verified by 11 passing assertions across
  `supabase/tests/rls/001_tenant_isolation.sql` and
  `002_auth_hardening.sql` — covering same-tenant access, cross-tenant
  denial, suspended-membership denial, removed-membership denial, non-admin
  privileged-write denial, non-privileged audit-read denial, audit-log
  append-only enforcement, permission-mapping correctness, and cross-tenant
  membership-reassignment denial. Verified against **both** plain Postgres
  16 and a real local Supabase stack (real `authenticated` role, real
  GoTrue `auth.uid()`) — see `PROJECT_STATE.md` for exact commands/output.
* Real authentication: Supabase SSR clients
  (`apps/web/lib/supabase/{client,server,middleware}.ts`), session refresh
  in `middleware.ts`, and server-side permission checks
  (`apps/web/lib/auth/context.ts`) gate `/admin`, `/clinician`, `/reviewer`,
  `/quality`. Middleware redirects unauthenticated requests; it is not the
  sole authorization boundary — every workspace layout independently calls
  `requirePermission()`, which re-derives identity, active membership, and
  permissions from the database (RLS-scoped), never from client-supplied
  IDs or editable user metadata.
* `audit_events` has `UPDATE`/`DELETE` revoked from `public` **and** blocked
  by a trigger for every runtime role, including `service_role` and the
  table owner — with a documented, narrow override reachable only from a
  direct privileged database session (see `docs/database/schema.md`). This
  is append-only for every role the application uses; it is not absolute
  immutability against a database superuser, and the docs say so explicitly.
* `organization_memberships.organization_id` is immutable after insert
  (trigger), closing a gap where an admin's UPDATE could otherwise reassign
  a membership row to a different organization.
* Storage buckets (0003) are private by default with organization-scoped
  RLS on `storage.objects`; no anonymous reads, no service-role key in the
  browser (`lib/supabase/service-role.ts` is server-only, documented as
  never importable from a client component, and has no call sites yet in
  Sprint 0).
* Login redirect handling (`lib/auth/redirect.ts`) rejects absolute URLs and
  protocol-relative (`//host`) strings for the `next` parameter — no open
  redirect via the login flow.
* `.env.example` files exist at root and per-app; `.gitignore` excludes all
  `.env*` variants except `.env.example`, plus build artifacts, caches, and
  Supabase CLI local state (`.branches/`, `.temp/`).

## Known gaps (Sprint 1+)

* No automated eslint/import-boundary rule yet prevents a future "use
  client" component from importing `lib/supabase/service-role.ts` —
  currently convention-only. Tracked in `KNOWN_LIMITATIONS.md`.
* No secret scanning configured in CI yet.
* **`next@14.2.35` carries several disclosed high-severity advisories**
  (`npm audit`, this session) whose only available fix is `next@16` — a
  breaking major-version upgrade affecting App Router APIs this session's
  auth work depends on. Not applied unilaterally; flagged for an explicit
  Sprint 1 decision rather than a forced upgrade during a hardening pass.
* No dependency vulnerability scanning configured in CI yet.
* No prompt-injection, malicious-PDF, or data-exfiltration test suite exists
  yet — there is no ingestion or generation pipeline to test against.
* MFA, session/device management, and SSO are Supabase Auth features not yet
  configured because no hosted Supabase project exists yet — only a local
  CLI stack has been verified against.
* Password-based login only; no magic-link or SSO flow wired to a UI yet
  (the `/auth/callback` code-exchange route exists and is real, but nothing
  currently sends a user through it besides a future password-reset link).

## Reporting a vulnerability found in this repository

Open a pull request or contact the maintainer directly; do not include real
credentials, tokens, or patient-like data in any issue or PR.
