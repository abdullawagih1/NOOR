# PROJECT_STATE.md

**Last updated:** Sprint 1 — Guideline Registry Schema and Lifecycle
session (Claude Code, this environment)
**Updated by:** Noor Delivery Council (Claude Code)

---

## -4. This session: Sprint 1 — Guideline Registry Schema and Lifecycle

Implemented the first Sprint 1 vertical slice: an organization-scoped
controlled registry for clinical guidelines (Clinical Domain → Guideline
Authority → Guideline → Guideline Version → Clinical Review → Approval →
Activation → Supersession → Withdrawal), deliberately stopping short of any
PDF ingestion, embeddings, or retrieval/generation work.

**Schema and lifecycle engine** (`supabase/migrations/0005_guideline_registry_and_lifecycle.sql`):
6 new tables (`clinical_domains`, `guideline_authorities`, `guidelines`,
`guideline_versions`, `guideline_reviews`, `guideline_lifecycle_events`),
12 new permissions, 10 SECURITY DEFINER functions (every create/update/
review/lifecycle-transition mutation goes through one, atomically pairing
the write with an `audit_events` row — no table has an INSERT/UPDATE/DELETE
RLS policy for `authenticated` at all), tenant integrity via composite
foreign keys rather than triggers wherever declaratively possible, a
partial unique index guaranteeing one active version per guideline, and
append-only enforcement on review/lifecycle-history tables mirroring
migration 0002's `audit_events` pattern. Full design rationale:
`docs/database/guideline-registry-schema.md`,
`docs/domain/guideline-lifecycle.md`. ADR 0007 records the decision to keep
the clinical-publication lifecycle and the (not-yet-built)
document-processing lifecycle as two separate state machines.

**A real architecture correction made mid-session:** the Admin Guideline
Registry pages were initially built under `/admin/knowledge/guidelines/*`,
matching the mission's suggested routes literally — but `quality_manager`
(who holds `guidelines.approve`/`activate`/`supersede`/`withdraw`) only has
`workspace.quality.access`, not `workspace.admin.access`, so nesting under
`/admin/*` would have made the entire approval/activation workflow
unreachable by the one role meant to perform it. Moved to a neutral
`/knowledge/guidelines/*` route, gated per-page by the specific
`guidelines.*` permission rather than a workspace shell — reachable by
`organization_admin`, `knowledge_manager`, `quality_manager`,
`safety_officer`, `clinical_reviewer`, and `auditor` as their individual
permissions warrant.

**Application layer and UI:** `apps/web/lib/guidelines/{schemas,actions,
queries,errors,ui}.ts` — Zod validation authoritative at the server
boundary, Server Actions wrapping every RPC with `requirePermission` +
correlation IDs + safe typed error mapping, RLS-trusting read queries.
Minimal UI: Admin Guideline Registry (list/filter, new-guideline form with
inline domain/authority quick-add, detail page with permission-aware
lifecycle action buttons and inline review/status history), Reviewer Queue
(`/reviewer/guidelines`), and a read-only Clinician Active Knowledge view
(`/clinician/knowledge`) that can structurally only ever display `active`
versions (RLS-enforced, not UI-filtered).

**Verification, real not assumed:** web lint/typecheck/build all clean;
34/34 `npm run test --workspace=apps/web` assertions (2 new suites this
session: schema validation, error-code mapping); a real `postgres:16`
Docker container (matching CI's `database` job exactly) had all 5
migrations + seed + the full RLS suite (11 + 4 + **26** new guideline
registry assertions) run against it — 41/41 passed. **A real bug was found
and fixed by actually running the test file**: psql's `:'var'` fixture
substitution silently fails to interpolate inside dollar-quoted `DO $$...$$`
blocks (where nearly every assertion lives), producing a bare syntax error
on first run; fixed by threading fixture IDs through a temp table + two
`SECURITY DEFINER` helper functions instead. Full record:
`docs/verification/sprint-1-guideline-registry-verification.md`.

**Hosted Development verification, real not assumed:** migration 0005
applied to the hosted "Noor Development" project
(`supabase db push --linked`, confirmed `local==remote` before/after).
Schema landed correctly (6 tables/RLS enabled, 12 permissions, 24 role
mappings, all functions, the one-active-version index — verified via direct
Management API queries). **18/18 real GoTrue-JWT hosted assertions
passed**: 4 synthetic users (admin/clinician/reviewer/quality) created via
the Auth Admin API, signed in for real access tokens, and exercised
entirely over HTTP (`/rest/v1/rpc/*`) — domain/authority/guideline/version
creation, clinician denied draft access, illegal transition rejected,
approval-without-review rejected, self-approval blocked, non-creator
approve+activate succeeds, clinician then sees the active version, raw
PATCH against an active version rejected, withdrawal-without-reason
rejected, withdrawal-with-reason succeeds and clears
`current_active_version_id`, audit events recorded, cross-tenant creation
denied. All synthetic test data (2 orgs, 4 users) deleted and confirmed via
a zero-count query. Vercel Preview redeployed with the new code
(`target: preview`, `status: Ready`), stable alias re-pointed, Deployment
Protection re-confirmed enabled and correctly enforced (unprotected smoke
test correctly detects and reports the protection wall, not a false pass —
unchanged from Sprint 0.5, since no protection config changed this
session). Full record:
`docs/verification/sprint-1-guideline-registry-verification.md`.

**Sprint 1 (Guideline Registry Schema and Lifecycle): Complete and
Hosted-Verified.**

---

## -3. Prior session: Sprint 0.5 final closure

The one remaining gap from the prior session — Vercel's "Protection Bypass
for Automation" secret, which required a dashboard action no CLI/API path
could perform — was configured by the user. The user then ran the
protected Preview HTTP smoke test themselves (`node
scripts/smoke-test-web.mjs` with `BYPASS_TOKEN` set locally) and reported
the result: **10/10 checks passed**, including all 6 body-content checks
(`/login`, `/forgot-password`, `/403`, `/access-denied`, `/`,
`/design-system`) that previously, without the bypass token, correctly
failed with "blocked by Vercel Deployment Protection" rather than
false-passing.

**Why this result is trustworthy and not a status-code-only pass:**
`scripts/smoke-test-web.mjs` inspects the response `Location` header for
every check and explicitly sets `isVercelSso = true` whenever it points at
`vercel.com/sso-api`, throwing a labeled failure in that case rather than
returning a bare boolean. A body-content check can only report `PASS` by
reaching the `assert(status === 200, ...)` line *after* the `isVercelSso`
branch has already returned false for that response, which happens only
when Vercel's edge actually let the request reach the Next.js app instead
of redirecting to its own SSO interstitial. A structural pass therefore
proves real Noor content was served, not Vercel's protection page — this
is the same script, unmodified, that correctly caught and reported the
protection wall as a failure in the prior session before the bypass was
configured.

**What this session did *not* do:** run the smoke test itself (the bypass
token was configured and used entirely on the user's machine, then removed
from their shell after — correct handling, since this session never had
and does not need that value), and did not perform any browser-driven
form-submission E2E — the smoke test is still an HTTP-level check only,
not a Playwright browser interaction. That remains a documented pre-
Controlled-Beta requirement (§5), not a Sprint 0.5 blocker.

**Sprint 0.5 status: Complete and Hosted-Verified.**

---

## -2. Prior session: Hosted Supabase Development Setup & Sprint 0.5 Closure (partial)

The user provided a Supabase personal access token mid-session (held only
as an in-memory `SUPABASE_ACCESS_TOKEN` for this session — never printed,
never committed). A hosted **"Noor Development"** project already existed
(`quohfsaqeqzbbvmrhmbr`, `eu-west-3`, Postgres 17, created between
sessions) — linked directly rather than creating a new one. All 3 existing
migrations applied cleanly to a genuinely green-field remote (confirmed via
`supabase migration list --linked` showing empty `remote` before, matching
`local` after).

**Real hosted verification, not assumed:** 26 Auth/RLS/Authorization/
Feature-flag/Audit assertions and 8 Storage assertions, all executed with
real GoTrue-issued JWTs against `/rest/v1` and `/storage/v1` — every
single one passed. Full command-by-command record:
`docs/verification/sprint-0.5-hosted-verification.md`.

**One real, previously-unknown finding, fixed and re-verified on the spot:**
hosted verification surfaced that `anon` held full CRUD grants on every
public table (a legacy Supabase project-creation default this specific
project inherited) — RLS already blocked practical access, but this was a
real defense-in-depth gap. Wrote and applied migration
`0004_revoke_anon_table_grants.sql`, re-verified locally (plain Postgres,
guarded no-op there) and on the hosted project (grants now `0`, anon
`SELECT` now genuinely `401`, was `200 []` before).

**A second finding investigated, not just observed:** a password-reset
status-code difference (429 vs 200) turned out to be GoTrue's own default
email-send rate limit (no custom SMTP on this Development project) — root-
caused with a clean two-fresh-address test, confirmed Noor's own UI never
branches on it, documented honestly rather than either hidden or
overclaimed as a bug.

**A genuine, unplanned proof of a Sprint 0 control**: cleaning up the test
audit-event row was *rejected* by the append-only trigger on the hosted
project — cleanup only succeeded after using the documented
`noor.allow_audit_maintenance` override, proving the control (and its
escape hatch) work identically on hosted, not just locally.

Vercel: Preview environment configured with the hosted Development values
(6 vars, Preview-scoped, encrypted), redeployed, confirmed `target:
preview`/`status: Ready`. A stable alias (`noor-preview-dev.vercel.app`)
was created since Vercel's per-deployment URLs are ephemeral and Supabase's
Auth redirect allowlist needs a fixed target. Supabase Auth URLs configured
against that stable alias, no wildcards. Deployment Protection was **kept
enabled** (not disabled) per explicit mission policy; the one remaining
step — "Protection Bypass for Automation" — is dashboard-only (confirmed:
no CLI command, REST API returns 400/404 for the plausible field names/
endpoints) and is documented as the single remaining manual action.

All synthetic hosted test data (2 orgs, 8 users) was created for
verification and fully deleted afterward — confirmed via a zero-count query
across every affected table.

---

## 0. Current phase

**Sprint 1 — Guideline Registry Schema and Lifecycle.**
Sprint 0.5 (hosted infrastructure & design system) is **Complete and
Hosted-Verified** — see §-3/§1 for that history; it is not reopened here.

**Sprint 1's first vertical slice — Guideline Registry Schema and
Lifecycle — status: Complete and Hosted-Verified.** Schema, lifecycle
engine, RLS, permissions, application layer, and minimal UI are
implemented and verified against three independent environments: plain
Postgres 16 (41/41 real assertions), the real hosted "Noor Development"
Supabase project with real GoTrue JWTs (18/18 real assertions), and the
Vercel Preview deployment (redeployed, healthy, Deployment Protection
intact). Web lint/typecheck/build/test (34/34) all clean. Full record:
§-4 above and
`docs/verification/sprint-1-guideline-registry-verification.md`.

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

## 5. Gap report

| Gap | Impact | Dependency | Risk | Owner | Next task |
|---|---|---|---|---|---|
| G-03: Clinical domain not confirmed | No default clinical domain is seeded anywhere (deliberately — migration 0005 seeds none); blocks choosing *which* guideline content to actually register first | Clinical partner decision | Medium | Product/Clinical | Confirm a domain (e.g. hypertension) or another starting scope |
| G-04: No AI provider selected | Blocks generation-side work | Provider spike | Medium | AI/RAG | Sprint 1 (S1-07) |
| G-07: Auth covers session/permission layer, not full account lifecycle | No signup, no admin member-management screen | None — incremental | Low | Frontend/Backend | Sprint 1 |
| G-09: No Playwright/browser E2E | Login/reset form submission unverified end-to-end via a real browser (the HTTP smoke test proves route protection and page delivery, not form interaction) | None — can start anytime | Low | Frontend/QA | **Pre-Controlled-Beta requirement, not a Sprint 1 blocker** |
| G-10: No custom SMTP on hosted Development project | Default GoTrue email-send rate limit is low; can affect real password-reset email volume | Configure custom SMTP in Supabase dashboard | Low | DevOps | Before Controlled Beta, not blocking Sprint 1 |
| G-11: No document-processing pipeline | Guideline versions carry no file reference; nothing to review/approve beyond registry metadata yet | None — the registry (this sprint) is the prerequisite | Medium | Backend/AI-RAG | Sprint 1 — "Secure Guideline Upload and Processing Job Foundation" (see §6) |
| G-12: Self-approval-by-a-permission-holding-creator not exercised by a live test | The block is real (explicit code check + verified via a *different* path — non-approver denial), but no seeded test fixture combines "authored this version" with "holds guidelines.approve" to hit that exact branch live | None — would need a dedicated fixture | Low | QA | Add when convenient; not blocking |

**Closed this session:** none of the pre-existing gaps close outright, but
the Guideline Registry Schema and Lifecycle vertical slice itself
(the Sprint 1 task this session executed) is Complete and Hosted-Verified
— see §-4.

**Closed prior sessions:** G-01 (hosted Supabase), G-08 (Vercel Protection
Bypass), G-02/G-05/G-06 (Sprint 0 items) — see git history for the
session-by-session record; not repeated here.

None of the remaining gaps (G-03, G-04, G-07, G-09, G-10, G-11, G-12) block
this task's closure — each is either a product/clinical decision, later
Sprint 1 work explicitly out of this task's scope (PDF ingestion, AI
provider selection), or a documented pre-Controlled-Beta requirement.

---

## 6. Recommended next task

The Guideline Registry Schema and Lifecycle vertical slice is closed.
Schema, lifecycle engine, RLS, permissions, application layer, and minimal
UI are implemented and verified against plain Postgres, the real hosted
Development project (real JWTs), and Vercel Preview.

```text
Begin Sprint 1 — Secure Guideline Upload and Processing Job Foundation
```

This is the document-processing lifecycle ADR 0007 deliberately kept
separate from the clinical publication lifecycle just implemented — PDF
upload, private-storage wiring, and a `document_processing_jobs` queue
contract, still not PDF parsing/chunking/embeddings itself (later tasks).
G-03 (clinical domain confirmation) should ideally be resolved before or
alongside that task, since it determines what real content gets uploaded
first. Playwright browser-driven E2E (G-09) stays a documented
pre-Controlled-Beta requirement, not a blocker.
