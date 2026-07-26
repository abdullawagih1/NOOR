# Security

## Reporting

This is a pre-release internal project. Report concerns directly to the
project owner rather than a public issue until a disclosure process
exists.

## Controls implemented

* Row-Level Security enabled on every table in `supabase/migrations/0001_*`
  through `0005_*`, verified by 15 Sprint-0/0.5 assertions across
  `supabase/tests/rls/001_tenant_isolation.sql` and
  `002_auth_hardening.sql` — covering same-tenant access, cross-tenant
  denial, suspended-membership denial, removed-membership denial, non-admin
  privileged-write denial, non-privileged audit-read denial, audit-log
  append-only enforcement, permission-mapping correctness, and cross-tenant
  membership-reassignment denial — **plus 26 Sprint-1 guideline-registry
  assertions** (`003_guideline_registry.sql`) covering cross-tenant
  guideline-creation denial, clinician read restricted to `active` versions
  only, every legal/illegal lifecycle transition, self-review and
  self-approval blocking, transactional supersession, released-version
  immutability, append-only review/lifecycle history, and audit-event
  creation. Verified against plain Postgres 16, a real local Supabase
  stack, **and the real hosted "Noor Development" project** — 26 Sprint
  0.5 Auth/RLS/Authorization/Feature-flag/Audit assertions + 8 Storage
  assertions + **18 Sprint-1 guideline-registry assertions**, all with real
  GoTrue-issued JWTs, all passed. See
  `docs/verification/sprint-0.5-hosted-verification.md` and
  `docs/verification/sprint-1-guideline-registry-verification.md`.
* **Guideline registry: every write is mediated by a SECURITY DEFINER
  function, never a table-level grant.** None of the 6 new tables
  (`clinical_domains`, `guideline_authorities`, `guidelines`,
  `guideline_versions`, `guideline_reviews`, `guideline_lifecycle_events`)
  has an INSERT/UPDATE/DELETE RLS policy for `authenticated`, and
  INSERT/UPDATE/DELETE table grants are explicitly revoked (Supabase's
  platform default privileges would otherwise grant them — the same class
  of finding migration 0004 closed for `anon`). A version's clinical
  publication status can only ever change through
  `transition_guideline_version()`, which independently re-derives
  `auth.uid()` and the caller's organization-scoped permission — self-
  review is blocked by a database trigger regardless of role, self-approval
  is blocked by an explicit check independent of the reviewer/approver role
  split, and released (`active`/`superseded`/`withdrawn`) version content
  is immutable via any client write path. See
  `docs/security/guideline-registry-authorization.md`.
* **Hosted finding, fixed and re-verified same session:** the hosted
  project had inherited a legacy Supabase default granting `anon` full
  CRUD (SELECT/INSERT/UPDATE/DELETE/TRUNCATE) on every public table. RLS
  already blocked practical access (`anon` SELECT returned `200 []`, not
  real rows) — this was a defense-in-depth gap, not a live exposure — but
  `supabase/migrations/0004_revoke_anon_table_grants.sql` closes it at the
  grant layer too. Verified: `anon` SELECT now returns `401 permission
  denied`, and a direct query confirms zero remaining `anon` grants on any
  public table.
* **A genuine, unplanned confirmation of the audit trigger on hosted
  infrastructure:** cleaning up a test audit row during this session's
  verification was *rejected* by `prevent_audit_event_mutation()` on the
  live hosted project — cleanup only succeeded after using the documented
  `noor.allow_audit_maintenance` override in the same transaction, proving
  both the block and its escape hatch work identically to local, not just
  in theory.
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
  browser — `lib/supabase/service-role.ts` and `lib/env/server.ts` both
  import the `server-only` npm package, which turns an accidental "use
  client" import into a **real build failure**, not just a documented
  convention. Verified this session: a throwaway Client Component was made
  to import `lib/env/server.ts`, `next build` failed with an actual
  webpack error, then the test file was removed and the clean build was
  re-confirmed.
* Centralized, validated environment access (`apps/web/lib/env/{public,
  server,serverSchema}.ts`, `apps/worker/app/settings.py`) — no more raw
  `process.env`/`os.getenv` scattered through the codebase. Confirmed
  clean via a full grep audit — no `NEXT_PUBLIC_`-prefixed secret ever
  exists, and a canary-value build (real-looking fake secrets for every
  server variable) confirmed none reach `.next/static`.
* Worker `/jobs` now requires `Authorization: Bearer <WORKER_INTERNAL_TOKEN>`
  (previously **no authentication existed at all** on this endpoint —
  found during this session's environment audit, not previously known).
  Constant-time comparison (`secrets.compare_digest`); missing/malformed
  header → 401, wrong token → 403, neither response leaks the expected
  value (`test_accept_job_error_does_not_reveal_expected_token`). The
  Worker process now refuses to start at all if `WORKER_INTERNAL_TOKEN` is
  missing or under 32 characters — verified via a real
  `pydantic.ValidationError` at import time, not a hypothetical.
* Login redirect handling (`lib/auth/redirect.ts`) rejects absolute URLs and
  protocol-relative (`//host`) strings for the `next` parameter — no open
  redirect via the login flow. Covered by `apps/web/tests/redirect.test.ts`
  (6 assertions).
* Password reset (`/forgot-password`) always returns the same generic
  success message whether or not the email matches an account — no
  account-enumeration oracle.
* `.env.example` files exist at root and per-app; `.gitignore` excludes all
  `.env*` variants except `.env.example`, plus build artifacts, caches, and
  Supabase CLI local state (`.branches/`, `.temp/`).
* **`next@15.5.21`** (upgraded from `14.2.35` this session — ADR 0006):
  resolves every Next-specific advisory `npm audit` had flagged, including
  ones genuinely reachable through this app's Server Action / Middleware
  usage (DoS, SSRF, internal-endpoint disclosure). Spiked in an isolated
  git worktree before applying to confirm the breaking-change fix (Next
  15's async `cookies()`/`searchParams`) was small and safe.
* CI: `gitleaks` secret-scan job added, runs on every push/PR — confirmed
  passing on real GitHub Actions runs (not just locally).
* `/design-system` returns 404 whenever `NODE_ENV=production` — verified
  via a real production build; unreachable on any deployed environment,
  reachable only in local dev, where it renders mocked data only.

## Known gaps (Sprint 1+)

* No dependency vulnerability scanning beyond `npm audit` run manually —
  not wired into CI as a blocking gate yet.
* A new transitive dependency, `sharp` (pulled in by Next 15's image
  pipeline), carries its own disclosed advisory. `apps/web` doesn't use
  `next/image` anywhere, so this is currently inert — re-check before ever
  adopting it.
* No prompt-injection, malicious-PDF, or data-exfiltration test suite exists
  yet — there is no ingestion or generation pipeline to test against.
* MFA, session/device management, and SSO are Supabase Auth features not
  yet configured on the hosted Development project.
* Password-based login only; no magic-link or SSO flow wired to a UI yet
  (the `/auth/callback` code-exchange route exists and is real — password
  reset now uses it).
* No custom SMTP configured on the hosted Development project — GoTrue's
  default (low) email-send rate limit applies. Investigated this session:
  a real status-code difference between existing/non-existent addresses on
  `/auth/v1/recover` was root-caused to this rate limit, not an
  enumeration bug — Noor's own `requestPasswordReset()` never branches on
  the raw API response. See `docs/operations/hosted-supabase-setup.md`.
* **Vercel Deployment Protection ("Vercel Authentication")** is enabled by
  default on this team and gates every route of the deployed Preview
  behind Vercel's own SSO, including `/login`. **Kept enabled throughout —
  by design, never disabled for testing convenience.** "Protection Bypass
  for Automation" (dashboard-only; no CLI command, REST API rejects the
  plausible field names/endpoints with 400/404) was configured by the user
  directly in the dashboard, then used once to run
  `scripts/smoke-test-web.mjs` against the protected Preview and removed
  from the local shell immediately after — never printed, persisted, or
  committed. `scripts/smoke-test-web.mjs` correctly detects and reports the
  protection wall by inspecting response bodies (the `isVercelSso` check) —
  fixing a real false-positive bug from a prior session where `fetch()`
  auto-following the SSO redirect produced misleading "200 OK" passes; that
  same check is what makes the protected 10/10 pass trustworthy rather than
  a status-code coincidence. See
  `docs/verification/sprint-0.5-hosted-verification.md`.

### Handling the Vercel bypass secret (and secrets like it)

The pattern demonstrated when closing this gap is the one to repeat:
generate/rotate the secret only in the Vercel dashboard, export it into the
shell only for the duration of the command that needs it (e.g.
`$env:BYPASS_TOKEN = "..."` in the same session as the `node` invocation),
and unset it from the shell immediately afterward. Never write it to a
`.env` file that could be committed, never paste it into chat, PR, or
commit-message text, and never log it — `scripts/smoke-test-web.mjs` reads
it from `process.env.BYPASS_TOKEN` only, sends it as the
`x-vercel-protection-bypass` header, and never echoes it back in output.

## Reporting a vulnerability found in this repository

Open a pull request or contact the maintainer directly; do not include real
credentials, tokens, or patient-like data in any issue or PR.
