# Changelog

## [Unreleased] — Sprint 1.2A: Durable Processing Orchestration

### Added

* `supabase/migrations/0007_durable_processing_orchestration.sql` — 6 new
  Worker-only functions (`claim_next_document_processing_job`,
  `start_document_processing_job`, `heartbeat_document_processing_job`,
  `complete_document_processing_job`, `fail_document_processing_job`,
  `recover_expired_document_processing_jobs`), never granted to
  `authenticated` (a stricter trust boundary than any prior migration —
  only `service_role` can call them). Atomic claim via
  `FOR UPDATE SKIP LOCKED`; hashed lease-token ownership; exponential
  backoff retry (30s/60s/120s/.../900s cap, `max_attempts=3`, one
  canonical `compute_retry_delay_seconds()` shared by both the
  failure-reporting and crash-recovery code paths); lease-expiry crash
  recovery; `cancel_processing_job` widened to allow `retry_scheduled` as
  a cancellable source status alongside `queued`.
* `docs/architecture/adr/0009-durable-processing-orchestration.md` — the
  database-as-source-of-truth decision, Mode A (polling) over introducing
  a queue this sprint, the hashed-lease design, the `authenticated`-vs-
  `service_role` trust boundary, and the `out_`-prefix output-column
  convention adopted to structurally eliminate the `RETURNS TABLE`
  shadowing bug class hit twice in migration 0006.
* `supabase/tests/rls/006_processing_orchestration.sql` — 27 real
  assertions: atomic claim, sequential-claim distinctness, wrong-worker/
  wrong-token denial for heartbeat/start/complete, idempotent replay of
  completion and failure reporting, retry-exhaustion → dead-letter,
  lease-expiry recovery (with stale-worker lockout), safe concurrent
  recovery, cancellation (queued/retry_scheduled allowed,
  dead_lettered/others rejected, idempotent repeat, unauthorized denied),
  forbidden-transition rejection, and unchanged RLS read restriction.
* `supabase/tests/concurrency/verify_concurrent_claim.sh` +
  `setup_concurrent_claim_fixture.sql` — a genuine dual-OS-process
  concurrency proof: two independent `psql` connections (separate
  Postgres backends) race to drain a shared pool of queued jobs; verifies
  zero overlap, zero lost jobs, and total claimed equals the actual
  claimable count (robust to leftover state from earlier test suites in
  the same database).
* `apps/worker/app/{orchestration_client,worker_loop,processing}.py` — a
  typed httpx PostgREST RPC client for the six new functions; a claim →
  start → heartbeat-loop → complete/fail polling loop with graceful
  shutdown (`WorkerLoop`); a controlled no-op processor
  (`noop_processor`) that proves the lifecycle without parsing any real
  document content. Wired into `app/main.py` via a FastAPI `lifespan`
  handler, gated by `WORKER_PROCESSING_MODE` (`disabled` by default —
  every existing deployment/test run unaffected until set to `noop`
  explicitly).
* `apps/worker/tests/{test_orchestration_client,test_worker_loop}.py` —
  18 new assertions: PostgREST request/response shape and safe error
  handling (`httpx.MockTransport`, no real network) and the full claim/
  start/heartbeat/complete/fail cycle including processor-exception
  containment, heartbeat-failure tolerance, and graceful shutdown
  (a fake in-memory `OrchestrationClient` — no real Supabase project;
  test-only failure-injection processors defined only in the test file).
* `apps/web/lib/documents/streamVerification.ts` — genuine incremental
  streaming file verification (size/PDF-signature/SHA-256 via
  `ReadableStream`, early-abort on oversized files), replacing the
  Sprint 1.1 full-buffer `.download().arrayBuffer()` approach found
  during this sprint's mandatory review. 5 new unit tests, including an
  explicit proof of early abort under a chunk-pull-count assertion.
* `apps/web/lib/documents/{queries,ui}.ts` extended:
  `listDocumentProcessingAttempts`, widened `ProcessingJobStatus`/new
  `ProcessingAttemptStatus` types, `AttemptStatusBadge`,
  `isJobCancellable`. Guideline detail page gained a Job Status Card
  (attempt count, next-retry/dead-letter timestamps, safe error text,
  result summary) and permission-gated Attempt History — no lease
  tokens, secrets, stack traces, or signed URLs anywhere in the UI; no
  fabricated progress percentages.
* `docs/domain/{document-processing-orchestration,document-processing-lifecycle}.md`,
  `docs/database/document-processing-orchestration-schema.md`,
  `docs/security/worker-orchestration-authorization.md`,
  `docs/operations/{worker-processing-runbook,job-recovery-and-dead-letter}.md`,
  `docs/verification/sprint-1.2a-processing-orchestration-verification.md`.

### Fixed

* **Sprint 1.1's mandatory-review finding**: `completeGuidelineUploadAction`
  fully buffered the uploaded file into memory before computing its
  facts. Refactored to real streaming — same trust model, same 50 MB
  limit, provably early-aborts on oversized input.
* A real bug found by actually running the new orchestration test file,
  not by reading it: the first draft's fixture pool was sized for fewer
  fresh claims than the test sequence actually needed, and separately
  asserted the shared Docker test database's claim queue would become
  globally empty — both wrong once run against cumulative state left by
  prior test suites. Fixed by sizing the fixture pool correctly and
  scoping assertions to the file's own fixture ids/distinctness rather
  than a global count.

### Verified this session (not assumed)

* Database: a fresh `postgres:16` Docker container had all 7 migrations +
  seed + the full RLS suite (001–006) run against it — 100% green,
  including the pre-existing 001–005 suites unmodified on top of
  migration 0007's schema changes. A genuine two-process concurrency
  race (80 jobs) — zero double-claims, zero lost jobs.
* Web: lint/typecheck/build clean; new `documents-orchestration-ui.test.ts`
  assertions added to the suite.
* Worker: `python -m compileall` clean; 27/27 pytest assertions (9
  pre-existing `/jobs`-contract + 18 new orchestration assertions).
* Other workspaces unaffected: `clinical-schemas` (6/6), `ui` (typecheck)
  re-verified clean.
* Hosted "Noor Development" and Vercel Preview — see
  `docs/verification/sprint-1.2a-processing-orchestration-verification.md`
  for the full record.

## [Unreleased] — Sprint 1.1: Secure Guideline Source Document Intake

### Added

* `supabase/migrations/0006_secure_guideline_document_intake.sql` — 5 new
  tables (`guideline_source_documents`, `document_upload_sessions`,
  `document_processing_jobs`, `document_processing_attempts`,
  `document_intake_events`), 8 permissions, 5 SECURITY DEFINER functions.
  Server-generated tenant-scoped Storage paths, signed direct upload
  authorization, post-upload object verification (existence, size, PDF
  signature, SHA-256 — computed server-side, never trusted from the
  browser), duplicate detection (same-version rejected, same-org
  other-version allowed and recorded, cross-org non-leaking), idempotent
  upload-session/completion/job-creation, released-version source
  immutability, and a manual quarantine override that cascades to cancel
  any active processing job.
* `docs/architecture/adr/0008-secure-document-intake-and-processing-boundary.md`
  — three separate state machines (clinical publication, upload session,
  processing job), and why file-identity facts are computed by the
  Next.js server (which cannot avoid it — Postgres cannot read Storage
  object bytes) rather than by SQL.
* `supabase/tests/rls/005_document_intake.sql` — 19 real assertions:
  eligibility, one-primary-per-version, cross-tenant denial, idempotent
  session/completion/job creation, duplicate detection (both allowed and
  rejected paths), RLS read restriction (clinicians see nothing),
  suspended/removed denial, verified-document immutability, quarantine
  cascade, retry-after-rejection, cancel-session, unauthorized
  job-cancellation denial, append-only intake events, audit trail.
* `supabase/tests/rls/004_g12_self_approval_regression.sql` — closes G-12
  (see "Fixed" below).
* `apps/web/lib/documents/{config,schemas,errors,queries,actions,ui}.ts` —
  canonical upload-size constant (kept in sync with the SQL-side guard via
  a dedicated test), Zod validation, safe error mapping, RLS-trusting
  reads, and the real upload orchestration: create session (RPC + signed
  Storage authorization) → direct browser-to-Storage PUT → complete
  (server re-downloads the object, computes size/signature/checksum,
  calls the RPC that atomically records the decision and queues a job).
  No service-role key or arbitrary Storage path/bucket ever reaches the
  browser.
* Minimal UI: an interactive upload panel
  (`apps/web/app/knowledge/guidelines/[guidelineId]/UploadPanel.tsx`,
  "use client") and a Source Documents section on the guideline detail
  page showing status, size, checksum fingerprint, and processing-job
  status, with permission-aware quarantine/cancel-job actions.
* `apps/web/tests/{documents-schemas,documents-errors,documents-config}.test.ts`
  — 22 new assertions. `tests/permissions.test.ts` extended with an
  8-permission document-intake role-mapping check.
* `docs/domain/{guideline-source-documents,document-intake-lifecycle}.md`,
  `docs/database/secure-document-intake-schema.md`,
  `docs/security/document-intake-authorization.md`,
  `docs/operations/guideline-document-upload.md`,
  `docs/verification/sprint-1.1-document-intake-verification.md`.

### Fixed

* **G-12 closed**: a guideline-version creator who also holds
  `guidelines.approve` still cannot approve their own version — the one
  gap the prior Sprint 1 report left open (blocked by real code, but never
  exercised end-to-end since no seeded role combined both). A dedicated
  regression test (a synthetic role holding `guidelines.create` +
  `guidelines.approve` on one user) passes against plain Postgres 16
  **and** hosted Development with a real GoTrue JWT.
* A real, two-part bug found by actually running migration 0006, not by
  reading it: `create_guideline_upload_session()` and
  `complete_guideline_upload()` both use `RETURNS TABLE`, whose output
  column names (`status`, `source_document_id`) silently shadowed real
  table columns referenced later in the same function bodies, producing
  `column reference "..." is ambiguous` only when actually executed.
  Fixed by table-qualifying both references.

### Backlog reconciliation

* `MASTER_BACKLOG.md`'s Sprint 1 section restructured from the original
  flat `S1-NN` guess into coherent workstreams (`S1-A` Guideline Registry
  — done, `S1-B` Secure Document Intake — now also done, `S1-C`/`S1-D`/
  `S1-E` — future) — the prior report undercounted what the S1-A vertical
  slice had actually delivered (application layer, UI, hosted
  verification), not just the schema migration.

### Verified this session (not assumed)

* Web: lint/typecheck/build clean; 63/63 test assertions.
* Database: 60/60 real assertions (cumulative across all 5 RLS/regression
  suites) against a real, freshly created `postgres:16` Docker container.
* Hosted "Noor Development": migration 0006 applied
  (`supabase db push --linked`, confirmed `local==remote`); **16/16 real
  assertions including actual Supabase Storage upload/download I/O** — a
  synthetic `%PDF-`-signed fixture file was really uploaded via an
  RLS-authorized (non-service-role) request, really re-downloaded, really
  hashed; plus the hosted G-12 run. All synthetic data (2 orgs, 6 users,
  the temporary G-12 test role, both uploaded Storage objects) deleted and
  confirmed via a zero-count query.
* Vercel Preview redeployed with the new code (`target: preview`,
  `status: Ready`), stable alias re-pointed, Deployment Protection
  re-confirmed enabled and correctly enforced (unchanged from Sprint 1).
* Other workspaces unaffected: `clinical-schemas` (6/6), `ui` (typecheck),
  `worker` (9/9 + compileall) all re-verified clean.

## [Unreleased] — Sprint 1: Guideline Registry Schema and Lifecycle

### Added

* `supabase/migrations/0005_guideline_registry_and_lifecycle.sql` — the
  controlled clinical guideline registry: 6 tables (`clinical_domains`,
  `guideline_authorities`, `guidelines`, `guideline_versions`,
  `guideline_reviews`, `guideline_lifecycle_events`), 12 permissions, 10
  SECURITY DEFINER functions mediating every write (create/update/review/
  transition, each atomically paired with an `audit_events` row), a single
  canonical `transition_guideline_version()` lifecycle engine enforcing
  draft → ready_for_review → approved → active → superseded → withdrawn,
  a partial unique index guaranteeing one active version per guideline,
  composite foreign keys enforcing tenant/guideline integrity declaratively,
  and append-only enforcement on review/lifecycle-history tables mirroring
  the `audit_events` pattern from migration 0002.
* `docs/architecture/adr/0007-separate-clinical-and-processing-lifecycles.md`
  — the clinical publication lifecycle (this migration) and the future
  document-processing lifecycle (upload/OCR/parsing/chunking) are two
  separate state machines, never merged.
* `supabase/tests/rls/003_guideline_registry.sql` — 26 real assertions
  covering uniqueness constraints, date-ordering, cross-tenant denial,
  clinician visibility (active-only), every legal/illegal lifecycle
  transition, self-review/self-approval blocking, transactional
  supersession, released-version immutability, append-only history, and
  audit-event creation.
* `apps/web/lib/guidelines/{schemas,actions,queries,errors,ui}.ts` — Zod
  validation authoritative at the server boundary, Server Actions wrapping
  every RPC with `requirePermission` + correlation IDs + safe error
  mapping (raw Postgres error text never reaches the client), RLS-trusting
  read queries.
* Minimal UI: `/knowledge/guidelines` (Admin Registry: list/filter, new
  guideline with inline domain/authority quick-add, detail page with
  permission-aware lifecycle action buttons and inline review/status
  history), `/reviewer/guidelines` (Reviewer Queue), `/clinician/knowledge`
  (read-only, structurally can only ever show `active` versions).
* `apps/web/tests/{guidelines-schemas,guidelines-errors}.test.ts` — 21 new
  assertions (Zod validation edge cases; Postgres-error → safe-message
  mapping).
* `docs/domain/{guideline-registry,guideline-lifecycle}.md`,
  `docs/database/guideline-registry-schema.md`,
  `docs/security/guideline-registry-authorization.md`,
  `docs/verification/sprint-1-guideline-registry-verification.md`.

### Changed

* `apps/web/tests/permissions.test.ts` — was hardcoded to check permission
  seeding against migration 0002 only; now scans every
  `supabase/migrations/*.sql` file, since permissions now legitimately span
  0002 and 0005 (and will span future migrations too).
* Admin/Reviewer/Quality/Clinician workspace stub pages
  (`apps/web/app/{admin,reviewer,quality,clinician}/page.tsx`) updated to
  link into the now-real guideline registry, and `WorkspaceHeader`'s nav
  gained two permission-gated items ("Guideline Registry",
  "Clinical Knowledge").

### Fixed

* A real, non-hypothetical bug found by actually running the new RLS test
  file against a fresh Postgres 16 Docker container (not just reading the
  SQL): psql's `:'var'` fixture-substitution silently does not interpolate
  inside dollar-quoted `DO $$ ... $$` PL/pgSQL blocks — which is where
  nearly every assertion lives — producing a bare syntax error on first
  run. Fixed by threading fixture IDs through a session-scoped temp table
  plus two `SECURITY DEFINER` SQL helper functions instead, which work
  identically inside and outside `DO` blocks.

### Architecture decision made mid-session

* The Admin Guideline Registry pages were initially built under
  `/admin/knowledge/guidelines/*`, matching the mission's literal suggested
  routes — but `quality_manager` (who holds `guidelines.approve`/
  `activate`/`supersede`/`withdraw`) only has `workspace.quality.access`,
  not `workspace.admin.access`, so nesting under `/admin/*` would have made
  the entire approval/activation workflow unreachable by the one role meant
  to perform it. Moved to a neutral `/knowledge/guidelines/*` route
  (its own minimal layout resolving only the session, not a specific
  workspace), with each page gating itself by the specific `guidelines.*`
  permission it needs.

### Verified this session (not assumed)

* Web: lint/typecheck/build clean; 34/34 test assertions.
* Database: 41/41 real assertions (11 Sprint-0 RLS + 4 auth-hardening + 26
  new guideline-registry) against a real, freshly created `postgres:16`
  Docker container matching CI's `database` job exactly.
* Hosted "Noor Development": migration 0005 applied
  (`supabase db push --linked`, confirmed `local==remote`); schema
  confirmed via Management API queries (RLS enabled on all 6 tables, 12
  permissions, 24 role mappings, all functions, the one-active-version
  index); **18/18 real GoTrue-JWT assertions** exercising the registry
  entirely over HTTP with 4 synthetic users; all synthetic test data (2
  orgs, 4 users) deleted and confirmed via a zero-count query.
* Vercel Preview redeployed with the new code (`target: preview`,
  `status: Ready`), stable alias re-pointed, Deployment Protection
  re-confirmed enabled and correctly enforced (unprotected smoke test
  correctly detects and reports the protection wall, unchanged from
  Sprint 0.5).
* Other workspaces unaffected: `clinical-schemas` (6/6), `ui` (typecheck),
  `worker` (9/9) all re-verified clean.

## [Unreleased] — Sprint 0.5 final closure

### Closed

* **Sprint 0.5 status: Complete and Hosted-Verified.** The one remaining
  dashboard-only action — Vercel "Protection Bypass for Automation" — was
  configured by the user directly in the Vercel dashboard (no CLI/API path
  exists for this step; confirmed in the prior session). The user then ran
  the unmodified `scripts/smoke-test-web.mjs` against the protected Preview
  with the bypass token set locally: **10/10 checks passed**, including all
  6 body-content checks (`/login`, `/forgot-password`, `/403`,
  `/access-denied`, `/`, `/design-system`) confirming real Noor content was
  served — not the Vercel SSO interstitial. The bypass token was never
  handled by this session; it was generated, used, and removed from the
  user's own shell afterward, never printed, persisted, or committed.
* `docs/verification/sprint-0.5-hosted-verification.md` updated with the
  full protected-run evidence and an explanation of why the `isVercelSso`
  structural check (added in the prior session specifically to fix a
  false-positive bug) makes a `PASS` here trustworthy rather than a
  status-code coincidence.
* `PROJECT_STATE.md`, `SPRINT_CURRENT.md`, `MASTER_BACKLOG.md` (S1-11),
  `KNOWN_LIMITATIONS.md` updated to reflect closure.
* This is an HTTP-level, body-content-aware smoke test — **not** browser-
  driven E2E. Playwright form-submission testing (login, password reset)
  remains a documented pre-Controlled-Beta requirement
  (`KNOWN_LIMITATIONS.md` item 8), not a Sprint 1 blocker.

## [Unreleased] — Hosted Supabase Development Setup & Sprint 0.5 Closure

### Added

* `supabase/migrations/0004_revoke_anon_table_grants.sql` — fixes a real
  finding from hosted verification: `anon` held full CRUD grants on every
  public table (a legacy Supabase project-creation default). RLS already
  blocked practical access; this closes the grant-layer gap too. Guarded
  to no-op on the plain-Postgres CI container (no `anon` role there).
* `docs/verification/sprint-0.5-hosted-verification.md` — complete,
  command-by-command hosted verification record: 26 Auth/RLS/
  Authorization/Feature-flag/Audit assertions + 8 Storage assertions, all
  executed with real GoTrue-issued JWTs, all passed.
* A stable Vercel Preview alias, `noor-preview-dev.vercel.app`, re-pointed
  to the latest Preview deployment after every deploy — needed because
  Vercel's per-deployment URLs are ephemeral and Supabase's Auth redirect
  allowlist needs a fixed target.
* Supabase Auth site URL + explicit redirect allowlist configured (no
  wildcards) against that stable alias.
* Vercel Preview environment variables (6, Preview-scoped, encrypted)
  pointing at the hosted "Noor Development" project.
* `scripts/smoke-test-web.mjs` rewritten to inspect response **bodies**
  for every check, not just status codes — explicitly detects and reports
  Vercel's SSO interstitial rather than mistaking it for a pass (fixes a
  real false-positive bug from a prior session) and accepts an optional
  `BYPASS_TOKEN` for authenticated Preview testing once configured.

### Fixed

* Hosted "Noor Development" project connected (it already existed,
  created between sessions) and all migrations applied to a genuinely
  green-field remote database (confirmed via `supabase migration list`
  before/after).
* The `anon`-grants finding above.

### Investigated and documented (not a defect)

* A password-reset status-code difference (429 vs 200 for existing vs
  non-existent addresses) turned out to be GoTrue's own default
  email-send rate limit on an SMTP-less Development project — root-caused
  with a clean two-fresh-address test rather than assumed. Noor's own
  `requestPasswordReset()` server action never branches on this response,
  so the product surface remains non-enumerating regardless.

### Verified this session (not assumed)

* All hosted checks above, with real JWTs, against the real project —
  not superuser-only SQL queries.
* A genuine, unplanned proof of the audit append-only trigger: cleaning up
  a test audit row was *rejected* by `prevent_audit_event_mutation()` on
  the hosted project, exactly as designed; cleanup only succeeded via the
  documented `noor.allow_audit_maintenance` override.
* Local re-verification (lint/typecheck/test/build for Web; typecheck/test
  for clinical-schemas and ui; compile/pytest for Worker; full RLS suite
  against plain Postgres, both before and after migration 0004) — all
  green.
* All synthetic hosted test data (2 orgs, 8 users) deleted after
  verification, confirmed via a zero-count query.

### Known, not fixed this session

* Vercel "Protection Bypass for Automation" requires a dashboard action —
  confirmed no CLI command exists and the REST API rejects the plausible
  field names/endpoints (400/404) for enabling it programmatically.
* No custom SMTP on the hosted Development project — acceptable pre-Beta,
  should be configured before real password-reset email volume matters.

## [Unreleased] — Environment Variables Audit, Standardization, and Security Hardening

### Added

* `apps/web/lib/env/{public,server,serverSchema}.ts` — centralized,
  zod-validated environment access. `public.ts`/`server.ts` are lazy
  functions (not pre-parsed constants) so the existing "static routes
  build without any Supabase config" property is preserved (re-verified —
  same route split as before). `server.ts` imports the `server-only` npm
  package; `serverSchema.ts` deliberately doesn't, so it stays unit-testable
  outside Next's bundler (`server-only` throws unconditionally in a plain
  Node/tsx process, discovered this session).
* `apps/worker/app/settings.py` — pydantic-settings `Settings` model.
  `WORKER_INTERNAL_TOKEN` has no default: the process now refuses to start
  at all if it's missing or under 32 characters (a real
  `pydantic.ValidationError` at import time, not a hypothetical — verified
  three ways: missing, too-short, and valid).
* `apps/worker/app/auth.py` — **`POST /jobs` now actually requires
  authentication.** The environment audit found `WORKER_INTERNAL_TOKEN`
  had been declared in every `.env.example` since Sprint 0 but never
  implemented anywhere — the endpoint accepted any request, unauthenticated,
  this whole time. Fixed: `Authorization: Bearer <token>`, constant-time
  comparison, 401 on missing/malformed header, 403 on wrong token, neither
  response leaks the expected value.
* CORS middleware wired into the Worker using the previously
  declared-but-unused `ALLOWED_ORIGINS` setting.
* `apps/worker/.env.example` — didn't exist before this session.
* `apps/web/tests/env.test.ts` (9 assertions) — valid/missing/malformed
  public and server env, optional-vs-required field behavior.
* Worker tests expanded from 5 to 9: missing token, malformed
  `Authorization` header, wrong token, and a check that error responses
  never leak the expected token value.
* `docs/operations/environment-variables.md` (full inventory,
  classification, rotation, incident-response guidance),
  `docs/operations/worker-deployment.md` (new).

### Fixed

* Real, once-thought-benign gap closed: the Worker's only real endpoint
  had no authentication at all. Found via a systematic audit
  (`grep -R "process\.env"` / `os.getenv` across the whole repo), not
  assumed — the audit table is in this session's conversation record.
* `.env.example` files (root, `apps/web`, new `apps/worker`) rewritten to
  an accurate, consistent, documented template — the root file previously
  listed `SUPABASE_ANON_KEY` without the `NEXT_PUBLIC_` prefix actually
  required by the code that reads it.

### Verified this session (not assumed)

* Boundary enforcement is real, not just documented: a throwaway `"use
  client"` component was made to import `lib/env/server.ts`; `next build`
  failed with an actual webpack error; the test file was then removed and
  a clean build reconfirmed.
* No secret leakage into the browser bundle: built `apps/web` with
  canary values for every server secret
  (`CANARY-SERVICE-ROLE-SECRET-...`, `CANARY-WORKER-TOKEN-...`), grepped
  the entire `.next/static` output — none appeared. Noted, not a defect:
  `lib/supabase/client.ts` (browser client) has no call sites yet, so
  `NEXT_PUBLIC_SUPABASE_ANON_KEY` doesn't currently reach the client
  bundle either — simply because nothing client-side reads it yet.
* `git grep` across tracked files for `sb_secret_`, real-looking
  `SUPABASE_SERVICE_ROLE_KEY=`/`WORKER_INTERNAL_TOKEN=`/
  `AI_GATEWAY_API_KEY=`/`SUPABASE_DB_PASSWORD=` values, and dangerous
  `NEXT_PUBLIC_`-prefixed secret names — all clean.
* Full local verification suite (lint/typecheck/test/build for Web;
  compile/pytest for Worker) re-run clean after every change in this
  session, not just once at the end.

## [Unreleased] — Sprint 0.5: Hosted Infrastructure & Design System Activation

### Added

* **`packages/ui`** (new workspace): canonical design tokens (colors,
  typography, spacing, radius, shadows — 16 clinical/system semantic states
  with icon + label + accessible description each), 22 generic primitives,
  10 Noor clinical components, `TokensStyleTag` (single-source CSS-variable
  injector). Tailwind CSS 3.4 added to `apps/web` as the utility layer,
  configured to import these tokens directly (`tailwind.config.ts`).
* `/design-system` showcase route (dev-only — 404s when
  `NODE_ENV=production`, verified via a real build).
* ADR 0005 (design-system composition) and ADR 0006 (Next.js
  security-version strategy).
* Password reset flow: `/forgot-password`, `/update-password`, wired
  through the existing `/auth/callback` route. Public signup stays
  disabled — documented as an intentional invite-only V1 Controlled Beta
  policy.
* `docs/design-system/{NOOR_DESIGN_SYSTEM,ACCESSIBILITY,SEMANTIC_STATES}.md`,
  `docs/operations/{hosted-supabase-setup,vercel-preview-deployment,github-ci}.md`.
* `scripts/smoke-test-web.mjs`: real HTTP smoke test (route protection,
  page availability, dev-only-route enforcement) — run against a local
  `next start` + real local Supabase this session, 10/10 passed.
* `apps/web/tests/{redirect,permissions}.test.ts`: open-redirect coverage
  for `sanitizeNextPath`, and a consistency check that every permission key
  referenced in code is actually seeded by migration 0002.
* CI: push-to-`main` trigger (previously PR-only) and a `gitleaks`
  secret-scan job.

### Changed

* **Next.js 14.2.35 → 15.5.21.** `npm audit` flagged ~19 advisories against
  14.2.35 with no non-breaking fix available; several were genuinely
  reachable through this app's actual Server Action / Middleware usage.
  Spiked the upgrade in an isolated git worktree first, hit and fixed Next
  15's "Async Request APIs" breaking change (`cookies()`/`searchParams` are
  now Promises — 7 files touched), fully re-verified, then applied to
  `main`. See ADR 0006 for the complete advisory list and exposure
  analysis.
* Every existing route (login, 403, access-denied, all 4 workspace shells)
  restyled onto `packages/ui` components; workspace navigation is now
  derived from the signed-in user's actual permissions, not hardcoded by
  route name.

### Fixed

* This is genuinely the first session the repository was pushed to GitHub
  (`git ls-remote` had confirmed the remote existed but was empty). CI now
  has two real, green GitHub Actions runs to point to, not just local
  YAML validation.
* Vercel project misconfiguration: the first `vercel link`/`deploy` (run
  from `apps/web`) scoped the upload to that directory alone, so the build
  failed trying to fetch the private `@noor/ui` workspace package from the
  public npm registry. Fixed by setting the project's Root Directory to
  `apps/web` via the Vercel API (no CLI subcommand exists for this) and
  re-linking from the repository root.

### Known, not fixed this session (see KNOWN_LIMITATIONS.md, PROJECT_STATE.md)

* No hosted Supabase project — blocked on credentials
  (`SUPABASE_ACCESS_TOKEN` or an interactive `supabase login`, neither
  available in this headless session).
* Vercel's default Deployment Protection ("Vercel Authentication") gates
  every route on the deployed Preview behind Vercel's own SSO — blocks
  automated HTTP verification of the live deployment. A caught, corrected
  false-positive: an early smoke-test pass against the Preview URL reported
  "200 OK" for several routes that were actually Vercel's SSO interstitial
  page, not Noor's app — `fetch()` had auto-followed the redirect. Fixed by
  inspecting response bodies, not just status codes; documented so it
  isn't repeated.
* No Playwright/browser-driven E2E of the login/password-reset forms —
  Next's Server Action wire protocol isn't a stable plain-`fetch` target;
  documented as a Sprint 1 gap rather than faked.

## [Unreleased] — Sprint 0 remediation (Claude Code, prior session)

An independent review of the prior sandbox delivery found the repository
had no `.git`, a stubbed auth middleware, an unseeded permissions table, a
tracked build artifact, and RLS claims verified only against plain
Postgres. This session reproduced every existing claim independently before
changing anything, then closed the real gaps.

### Added

* `git init -b main` — this is now an actual, real Git repository (it was
  not one before this session; see "Git status" in `PROJECT_STATE.md` for
  the current commit).
* Real Supabase SSR integration: `apps/web/lib/supabase/{client,server,
  middleware,service-role}.ts` using `@supabase/ssr` + `@supabase/supabase-js`
  (previously `server.ts` only read env vars — no SSR client, no cookies,
  no session at all).
* Real authentication flow: `/login` (email+password, safe-redirect only),
  `/auth/callback` (code exchange for magic-link/reset flows), a `signOut`
  server action, and `middleware.ts` now actually refreshes the session and
  redirects unauthenticated requests away from `/admin`, `/clinician`,
  `/reviewer`, `/quality` (previously a documented pass-through stub).
* `apps/web/lib/auth/context.ts`: `getAuthenticatedContext` /
  `requireActiveMembership` / `requirePermission` / `requireRole`, resolving
  identity, profile, active organization membership, and permissions from
  the database under RLS — never from client-supplied IDs. Each workspace
  now has a layout that calls `requirePermission(...)` before rendering.
  Controlled `/403` and `/access-denied` pages replace unhandled errors for
  permission-denied and no-active-membership cases.
* Migration `0002_sprint0_auth_hardening.sql`: seeds `permissions` and
  `role_permissions` (declared in 0001, never populated — no route could
  actually be authorized against a permission key before this), adds
  `has_permission_in_organization()`, a trigger preventing
  `organization_memberships.organization_id` reassignment, and a trigger
  making `audit_events` append-only for every runtime role (not just
  `public`) with a documented, narrow maintenance override.
* Migration `0003_storage_foundation.sql`: 5 private buckets
  (`guideline-originals`, `guideline-processed`, `evaluation-assets`,
  `generated-reports`, `temporary-uploads`) with organization-scoped RLS on
  `storage.objects`. Guarded to no-op against the plain-Postgres CI
  container (no `storage` schema there); verified for real against a local
  Supabase stack.
* `supabase/tests/rls/002_auth_hardening.sql`: 6 new assertions for the
  above. Both RLS test files were extended to set `request.jwt.claims`
  (real Supabase's actual `auth.uid()` source) alongside the existing
  `request.jwt.claim.sub` shim, so the same files now verify against both
  plain Postgres and real Supabase without duplication.
* `supabase/config.toml` (via `supabase init`) for local Supabase CLI
  development.

### Fixed

* Removed tracked build artifact `apps/web/tsconfig.tsbuildinfo`; expanded
  `.gitignore` to the full baseline (`coverage/`, `dist/`, `build/`,
  `*.tsbuildinfo`, `.env.*`, `.vscode/`, `.idea/`, Supabase CLI local state).
* Removed `apps/web/package-lock.json` and
  `packages/clinical-schemas/package-lock.json` — this is an npm workspaces
  monorepo (root `package.json`), and `npm ci`/`npm install` run from a
  workspace member directory silently resolves to the **root**
  `package-lock.json` regardless; the nested lockfiles were never actually
  read by npm and were misleading to keep. `.github/workflows/pr.yml`
  updated to `npm ci` once at the root per job and target each workspace
  with `--workspace=`, and `cache-dependency-path` corrected to point at the
  root lockfile that npm actually uses.
* Fixed a real production-build failure: the new permission-gated layouts
  read cookies via the Supabase server client, but Next.js still attempted
  to statically prerender `/admin`, `/clinician`, `/reviewer`, `/quality` at
  build time and failed on the (correct) missing-env-var error before it
  could opt into dynamic rendering. Added `export const dynamic =
  "force-dynamic"` to each workspace layout — the standard fix for
  session-dependent App Router routes.

### Verified this session (see PROJECT_STATE.md for full evidence)

* Worker: `compileall` + 5/5 pytest, from a clean venv.
* Web: `npm ci`, lint, typecheck, and production build all pass from the
  repository root using the corrected workspace-scoped commands; 10 routes
  generated (up from the previously reported 6 — 4 new: `/login`,
  `/auth/callback`, `/403`, `/access-denied`).
* clinical-schemas: typecheck + 6/6 tests, from a clean install.
* RLS: 11/11 assertions pass against plain Postgres 16 (matches CI), **and**
  11/11 pass again against a real local Supabase stack (`supabase start`,
  CLI v2.109.1) with the real `authenticated` role and real GoTrue
  `auth.uid()`. A real end-to-end request (GoTrue user → password sign-in →
  JWT → PostgREST `/rest/v1/organizations`) confirmed RLS-filtered results
  over actual HTTP; an anonymous request to the same endpoint was correctly
  rejected (401).
* Storage buckets and their RLS policies confirmed present in the real
  Supabase stack.

### Known, not fixed this session (see KNOWN_LIMITATIONS.md)

* `next@14.2.35` carries several disclosed advisories whose only fix is
  `next@16` — a breaking major-version upgrade, treated as an architecture
  decision requiring sign-off rather than a silent forced upgrade.
* No hosted Supabase project, no GitHub push, no Vercel deployment, no CI
  execution on GitHub Actions — all require credentials/access this session
  does not have.

## [Unreleased] — Sprint 0 initial delivery (prior sandbox session)

### Added

* Monorepo scaffold: `apps/web`, `apps/worker`, `packages/clinical-schemas`,
  `supabase/`, `clinical/`, `docs/`, `infrastructure/`, `.github/workflows/`.
* Migration `0001_identity_and_rls.sql`: organizations, organization_settings,
  profiles, roles/permissions/role_permissions, organization_memberships,
  access_reviews, audit_events, feature_flags, RLS policies and helper
  functions (`current_active_organization_ids`, `has_role_in_organization`).
* Synthetic seed data (`supabase/seed.sql`) covering active, suspended, and
  removed membership states across two organizations.
* RLS test suite (`supabase/tests/rls/001_tenant_isolation.sql`) — 7 tests,
  all passing: same-tenant access, cross-tenant denial, suspended-membership
  denial, removed-membership denial, non-admin privileged-write denial,
  unauthorized audit-read denial, audit-log append-only enforcement.
* Worker service scaffold (FastAPI): `/health`, `/ready`, `POST /jobs` with
  a typed, validated job contract. 5 tests passing.
* Web app scaffold (Next.js 14 App Router): landing page + 4 role-based
  workspace stubs (`/clinician`, `/admin`, `/reviewer`, `/quality`), server-
  only Supabase config accessor, auth middleware stub. Lint, typecheck, and
  production build all pass.
* `packages/clinical-schemas`: zod schema + safety invariants for the
  structured clinical answer contract. 6 tests passing.
* CI pipeline definition (`.github/workflows/pr.yml`) covering web, worker,
  clinical-schemas, and database/RLS jobs. YAML-validated; not yet executed
  on GitHub Actions (no remote push access in this environment).
* Governance docs: `INTENDED_USE.md` (draft), `RISK_REGISTER.md` (10 initial
  risks), 4 ADRs, database/API/operations documentation.

### Changed

* `next` pinned to `14.2.35` (not the originally scaffolded `14.2.15`) after
  `npm install` flagged a known security advisory in `14.2.15` — see
  SECURITY.md.

### Known limitations

See `KNOWN_LIMITATIONS.md`.
