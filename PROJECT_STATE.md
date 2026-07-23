# PROJECT_STATE.md

**Last updated:** Environment Variables Audit & Security Hardening session
(Claude Code, this environment)
**Updated by:** Noor Delivery Council (Claude Code, running locally against
the actual repository)

---

## -1. This session: Environment Variables Audit, Standardization, and Security Hardening

A full repository audit (`grep -R "process\.env"`, `os.getenv`,
`SUPABASE_|NEXT_PUBLIC_|WORKER_|AI_GATEWAY_`) found every variable
reference across `apps/web`, `apps/worker`, CI, and docs, and surfaced one
real, previously-unknown security gap: **the Worker's `POST /jobs`
endpoint had zero authentication** — `WORKER_INTERNAL_TOKEN` had been
declared in `.env.example` since Sprint 0 but never actually implemented
anywhere. Fixed and verified this session (see `SECURITY.md`,
`docs/operations/worker-deployment.md`). Also implemented: centralized
validated env access on both sides (`apps/web/lib/env/*`,
`apps/worker/app/settings.py`), a real (not assumed) `server-only`
bundler-enforcement test, a real (not assumed) canary-secret browser-bundle
leak test, and 13 new tests (9 Web env, 4 Worker auth) — all green. Full
inventory, classification, and rotation/incident guidance:
`docs/operations/environment-variables.md`. This did not touch the
hosted-Supabase or Vercel-Deployment-Protection blockers below — those are
unchanged from the prior session.

---

## 0. Current phase

**Sprint 0.5 — Hosted Infrastructure & Design System Activation.**
Sprint 0 (platform foundation) was completed and remediated in a prior
session — see §1 for that history. Status: **in progress, not complete** —
hosted Supabase is blocked pending credentials (see §5, gap G-01), and
Vercel Preview HTTP verification is blocked by Vercel's own Deployment
Protection (§5, gap G-08). Everything achievable without those two items,
including this session's environment-variable hardening, is done and
verified.

---

## 1. History: Sprint 0 and its remediation (prior session, condensed)

A previous sandbox delivery had never actually been a git repository, had a
pass-through auth middleware, an unseeded permissions table, and RLS
verified only against plain PostgreSQL. A remediation session reproduced
every finding, then: initialized real git, built real Supabase SSR auth
(clients, session refresh, login/logout, permission-gated routes),
authored migrations 0002 (permission seeding + auth-hardening triggers) and
0003 (storage foundation), and verified all of it against **both** plain
Postgres and a real local Supabase CLI stack — including a genuine
GoTrue-user → JWT → PostgREST round trip proving RLS enforcement over
actual HTTP. Full detail of that session is preserved in git history
(commits `559aa5d`..`fdfb16b`) and is not repeated here.

---

## 2. Repository statistics (generated, not asserted)

Command: `git ls-files | wc -l` after this session's additions:

* **~115** tracked files (up from 73 at end of Sprint 0 — see `git log
  --stat` for the exact diff per commit)
* **3** SQL migrations, **2** RLS test files (11 assertions), unchanged
  from Sprint 0
* **3** apps/packages became **4**: `apps/web`, `apps/worker`,
  `packages/clinical-schemas`, **`packages/ui`** (new — the design system)
* **32** design-system components (22 generic + 10 clinical), all in
  `packages/ui/components/`

## 3. Git / GitHub status (real, this session)

* Branch: `main`. Remote `https://github.com/abdullawagih1/NOOR.git` —
  **pushed for real this session** (confirmed empty beforehand via
  `git ls-remote`; a stored git credential for github.com was already
  present in Windows Credential Manager, used with the user's explicit
  go-ahead).
* Commits pushed this session (in order): `559aa5d`, `fdfb16b` (prior
  session, pushed now for the first time), `e13d468` (design system +
  password reset), `b1c21e5` (Next.js 15 upgrade), `e635adb` (design-system
  docs). Run `git log --oneline` for the current, authoritative list —
  this document does not repeat commit hashes for anything after this
  point to avoid the exact mistake Sprint 0's remediation was created to
  fix.
* **CI has actually run and passed on GitHub Actions twice** (not just
  YAML-validated): runs `29998063629` (commit `e13d4682`) and
  `30000512766` (commit `e635adbc`, includes the Next.js 15 upgrade),
  5/5 jobs each: Web, Clinical schemas, Worker, Supabase (migrations+RLS),
  Secret scan. See `docs/operations/github-ci.md`.
* CI's push trigger and a `gitleaks` secret-scan job were both added this
  session (`.github/workflows/pr.yml`).

## 4. This session's verification evidence

### Local re-verification (before any change, and again after)

All of Sprint 0's local checks were re-run from clean state before
changing anything, and again after the Next.js 15 upgrade:

```
$ npm ci && npm run lint/typecheck/test/build --workspace=apps/web   → all green, both times
$ npm run typecheck/test --workspace=packages/clinical-schemas       → 6/6, both times
$ npm run typecheck --workspace=packages/ui                          → clean (new package)
$ python -m compileall apps/worker && pytest apps/worker              → 5/5, both times
$ (docker) apply 0001-0003 + seed + both RLS test files against
  plain Postgres 16                                                   → 11/11, both times
```

### Design System (packages/ui) — implemented and verified

* Canonical tokens (`packages/ui/tokens/*.ts`): colors (brand + 16
  semantic states, light+dark), typography, spacing, radius, shadows.
  Consumed by Tailwind (`apps/web/tailwind.config.ts`) and by a runtime
  CSS-variable injector (`TokensStyleTag`) — one source, zero duplication.
* 22 generic primitives + 10 Noor clinical components, all typechecked,
  all rendered on `/design-system` with mocked data.
* `/design-system` calls `notFound()` when `NODE_ENV==="production"` —
  verified via a real production build + `next start`: returns 404 there,
  reachable only in `next dev`.
* Every pre-existing route (login, 403, access-denied, 4 workspaces) was
  restyled onto the new components in the same session.
* Real WCAG contrast was computed (not asserted) for every token pairing —
  see `docs/design-system/ACCESSIBILITY.md`. One real, documented exception
  found: `muted-soft` on `canvas` (3.02:1, fails AA-normal) — scoped to
  placeholder-only text with an always-visible label alongside it, not
  silently ignored.
* ADR 0005 records the composition decision (50% Better / 25% NHS / 15%
  Carbon / 10% DESIGN.md warmth) and what was deliberately *not* carried
  from DESIGN.md (Airbnb brand color, terminology, typefaces).

### Auth: password reset — implemented and verified (build-level)

`/forgot-password` → `resetPasswordForEmail` (generic success message,
no account-enumeration oracle) → email link → `/auth/callback` (code
exchange, pre-existing route) → `/update-password` →
`supabase.auth.updateUser`. Public signup remains disabled — documented as
an intentional V1 Controlled Beta policy (invite-only), not an oversight,
on the login page itself and in `KNOWN_LIMITATIONS.md`.

### Real HTTP smoke test (local `next start` + real local Supabase)

```
$ npx supabase start                                    → real GoTrue/PostgREST/Postgres stack
$ npm run build --workspace=apps/web  (real Supabase env vars, not placeholders)
$ NODE_ENV=production npx next start -p 3000
$ node scripts/smoke-test-web.mjs
→ 10/10 PASS: unauthenticated redirects to /login on all 4 workspace routes,
  /login /forgot-password /403 /access-denied /  all 200,
  /design-system 404s in production
```

This is real evidence against a real running server — not a unit test.
`docker rm -f` / `supabase stop` afterward; no stray containers left running.

### Next.js 14.2.35 → 15.5.21 upgrade — spiked, then applied

`npm audit` on 14.2.35: ~19 advisories, several genuinely reachable through
Noor's actual Server Action / Middleware usage (not just theoretical). No
non-breaking fix exists within the 14.x line (14.2.35 is the newest stable
14.x release). Spiked the 15.x upgrade in an isolated `git worktree`
first — hit Next 15's "Async Request APIs" breaking change immediately
(`cookies()` and `searchParams` are now Promises), fixed 7 files, re-ran
lint/typecheck/test/build clean in the spike, then ported the identical fix
to `main` and re-verified there too. `next` no longer appears in
`npm audit` afterward. Full advisory list, exposure analysis, and decision
in `docs/architecture/adr/0006-nextjs-security-version-strategy.md`.

### Vercel — deployment pipeline verified; HTTP verification blocked

Vercel CLI was already authenticated on this machine. First `vercel link`
(run from `apps/web`) created a project scoped to *only* that directory —
the build failed trying to fetch `@noor/ui` from the public npm registry,
since it never saw the workspace root. Fixed via the Vercel REST API
(`rootDirectory: "apps/web"`, `framework: "nextjs"` — no CLI subcommand
exists for this), re-linked from the repo root, and the build succeeded
(2.2MB uploaded — the whole repo, correctly this time).

The **first** deployment landed as `target: production` despite `--yes`
(empirically confirmed: a project's first-ever deployment is always
Production, regardless of flags — no working Supabase credentials are
wired to it, so nothing sensitive is actually live). A second deploy with
`--target=preview` correctly returned `target: preview`
(`vercel inspect` confirmed).

**HTTP-level verification against that live Preview URL is blocked**: every
route, including `/login`, redirects to `vercel.com/sso-api` — this team's
default "Vercel Authentication" Deployment Protection, which runs in front
of the Next.js app entirely. A first pass at smoke-testing this URL
produced false-positive "200 OK" results because `fetch()` auto-follows
that redirect to Vercel's *own* SSO page (which also returns 200) — caught
by inspecting the response body, not trusted at face value. See
`docs/operations/vercel-preview-deployment.md` for the full account and the
two remediation options (disable protection, or configure a Protection
Bypass for Automation secret) — both are project-setting decisions for the
owner, not something applied unilaterally here.

### Not run (and why)

| Check | Reason not run |
|---|---|
| RLS suite against a **hosted** Supabase project | No hosted project — blocked on credentials (G-01) |
| Full HTTP smoke test against deployed Vercel Preview | Blocked by Vercel Deployment Protection (G-08) |
| Browser-driven (Playwright) E2E of the login/reset forms | Not installed this session; Next's Server Action wire protocol isn't a stable plain-`fetch` target — documented Sprint 1 gap, not faked |
| Load / penetration tests | No deployed target with real data |

---

## 5. Gap report (Sprint 0.5)

| Gap | Impact | Dependency | Risk | Owner | Next task |
|---|---|---|---|---|---|
| G-01: No hosted Supabase project | Blocks hosted RLS re-verification and a working Vercel deployment | User-provided `SUPABASE_ACCESS_TOKEN` or interactive `supabase login` | Medium | You / DevOps | Provide the token, or run `supabase login` yourself — see `docs/operations/hosted-supabase-setup.md` |
| G-08: Vercel Deployment Protection blocks HTTP verification | Can't confirm real user-facing behavior on the deployed Preview | Project-setting decision (disable, or generate a bypass secret) | Low (security posture is arguably *more* correct as-is) | You | Decide and apply via Vercel dashboard — see `docs/operations/vercel-preview-deployment.md` |
| G-03: Clinical domain not confirmed | Blocks guideline sourcing | Clinical partner decision | Medium | Product/Clinical | Confirm or accept hypertension default |
| G-04: No AI provider selected | Blocks generation-side work | Provider spike | Medium | AI/RAG | Sprint 1 |
| G-07: Auth covers session/permission layer, not full account lifecycle | No signup, no admin member-management screen | None — incremental | Low | Frontend/Backend | Sprint 1 |
| G-09: No Playwright/browser E2E | Login/reset form submission unverified end-to-end via a real browser | None — can start anytime | Low | Frontend/QA | Sprint 1 |

Superseded from Sprint 0: G-02 (git push — done), G-05 (Next.js advisory —
resolved via 15.5.21 upgrade, ADR 0006), G-06 (CI execution evidence — done,
twice).

---

## 6. Recommended next task

Two items remain genuinely blocked on external input, not on more work
this session can do:

1. **Provide Supabase credentials** (personal access token, or run
   `supabase login` yourself) so the hosted Development project can be
   created and the already-passing local RLS suite re-verified against it.
2. **Decide on Vercel Deployment Protection** for this project (disable,
   or generate a Protection Bypass secret) so Preview URLs are actually
   testable.

Once either lands, the very next task is: apply the pending migrations to
the hosted project, re-run `scripts/smoke-test-web.mjs` and the RLS suite
against it, and wire real environment variables into the Vercel project.
**Do not begin Sprint 1** (Guideline Registry) until that hosted
verification closes — Sprint 0.5 is not complete until it does.
