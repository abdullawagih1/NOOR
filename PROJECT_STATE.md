# PROJECT_STATE.md

**Last updated:** Sprint 1.2B — Deterministic PDF Page and Text
Extraction session (Claude Code, this environment)
**Updated by:** Noor Delivery Council (Claude Code)

---

## -7. This session: Sprint 1.2B — Deterministic PDF Page and Text Extraction

Implemented workstream `S1-C2`: the Worker's controlled no-op processor
(Sprint 1.2A) is replaced with a real, deterministic PDF extraction
pipeline — source integrity revalidated twice independently, page-level
text extraction and normalization, page/artifact checksums, technical
quality metrics, conservative suspected-scanned detection, a canonical
JSON artifact uploaded privately and independently re-verified, and
atomic finalization with idempotent identity-based reuse. Migration
`0008_deterministic_pdf_extraction.sql`.

**Mandatory first review completed**: re-verified the Sprint 1.2A
hosted-only security fix (schema `CREATE` privileges, narrow
`search_path`, `authenticated`/`anon` EXECUTE grants) and turned it into
a **permanent regression suite**
(`supabase/tests/rls/007_security_hardening_review.sql`) rather than
leaving it as a one-off verification script — the exact class of bug
found in Sprint 1.2A can now never silently regress unnoticed.

**Extractor decision (ADR 0010):** `pypdf` (BSD-3-Clause), selected over
the mission's own suggested default, `PyMuPDF` — which moved to AGPL-3.0
licensing at v1.24.1, a real, unresolved legal exposure for a commercial
clinical SaaS platform (the AGPL network-use clause). This is exactly the
kind of blind-default risk the mission's own instruction ("do not select
it blindly") anticipated; the ADR documents the full comparison against
`pdfminer.six`/`pdfplumber` too.

**Two real concurrency bugs found and fixed by actually racing two
independent processes at the same extraction identity, not by reading the
SQL:**

1. `finalize_document_extraction_run()` raised a raw `unique_violation`
   when two genuinely simultaneous extraction attempts at the same
   identity both tried to mark themselves `succeeded` — the row-level
   lock inside `create_document_extraction_run()` only locks an
   *existing* row, so two callers can legitimately both create fresh
   `running` rows the first time they race in. Fixed with an exception
   handler that gracefully adopts the winning run instead of surfacing a
   raw constraint-violation error to the Worker.
2. A second, related race surfaced immediately after fixing the first:
   the claim → create → insert-pages → finalize sequence is several
   separate auto-committed statements, not one spanning transaction — a
   job's own `document_extraction_runs` row can be superseded by a
   *different* job's attempt at the same identity after the first job
   already committed its `create` call but before it reached `finalize`.
   That raised a raw "not running" error too. Fixed by explicitly
   detecting the supersession case: adopt an already-succeeded winner if
   one exists, otherwise raise a clear, named, retryable error — exactly
   what a real Worker's error-classification layer expects, never a raw,
   unclassified exception. Both fixes re-verified together: 5 consecutive
   runs of the new dual-OS-process concurrency script
   (`supabase/tests/concurrency/verify_concurrent_extraction_identity.sh`),
   all 4 possible race outcomes observed naturally, zero unexpected
   errors across all five. See
   `docs/database/deterministic-pdf-extraction-schema.md`.

**Verification, real not assumed:** local — a fresh `postgres:16` Docker
container had all 8 migrations + seed + the full RLS suite (001–008) run
against it, 100% green (117/117 cumulative assertions), including the
pre-existing 001–007 suites unmodified on top of migration 0008's schema;
two genuine dual-OS-process concurrency proofs (the unchanged Sprint 1.2A
claim-race script, and the new extraction-identity-race script); Worker —
91/91 pytest assertions (59 pre-existing + 32 new covering fixture
behavior against 11 synthetic PDFs, determinism, source-integrity
revalidation, and end-to-end processor orchestration),
`python -m compileall` clean; Web — lint/typecheck/build/test all clean,
the new extraction UI route compiles in the production build.

**Hosted Development — verified.** Migration 0008 applied (`local==remote`
confirmed). The corrected 007+008 SQL suite (24 assertions) ran clean
against real hosted Postgres 17. A real end-to-end flow exercised the
**unmodified production Worker code** against real infrastructure: a real
GoTrue user/JWT, a real RLS-authorized Storage upload, the real
`WorkerLoop`/extraction pipeline claiming and processing a real job with
`service_role` credentials — 5/5 pages extracted from a real multi-page
PDF, artifact uploaded to private Storage and independently re-downloaded
and re-hashed (checksum match confirmed), idempotent reprocessing proven
(a second real job at the same identity reused the same extraction run,
no duplicate), the `authenticated` trust boundary denied for both an
org_admin JWT and a clinician JWT, RLS confirmed permissive for org_admin
and zero-row for clinician, and a genuine `source_object_missing` failure
correctly classified (not crashed) when the Worker drained an unrelated
fixture job with no real Storage object. One real, non-product finding
along the way: the Supabase Management API's SQL query endpoint batches
an entire multi-statement submission differently than `psql -f`'s
per-statement autocommit, which made an unrelated `begin/rollback` test
pattern (008's original TEST 15/15b) unsafe under that execution model —
fixed in the committed test file itself (switched to the same bare-`DO`-
block role-switch pattern already proven safe by TEST 16), re-verified
locally with no regression. All synthetic hosted data (2 real GoTrue
users, seed.sql's 5 placeholder users, all DB rows, both Storage objects)
was cleaned up and confirmed zero-residual. Vercel Preview redeployed,
`Ready`, the new extraction page-detail route present in the build,
Deployment Protection intact. Full record:
`docs/verification/sprint-1.2b-pdf-extraction-verification.md`.

**A third real bug, found by CI itself, not locally:** the first push
failed the `database` job — CI always starts a genuinely fresh Postgres
container per run, and `008_pdf_extraction.sql` was missing its own
explicit `grant select on document_extraction_runs,
document_extraction_pages to authenticated` (the `authenticated` role
doesn't exist until the RLS suite's first file creates it, so migration
0008's own guarded grant is a no-op there — exactly the same constraint
migrations 0005/0006 already solved in their own test files, which 008
never copied). A reused local Docker container had been silently masking
this the whole time. Fixed, re-verified against multiple genuinely fresh
`postgres:16` containers, re-pushed — CI confirmed green
(`4514f20`, run `30249901666`).

**Sprint 1.2B (Deterministic PDF Page and Text Extraction): Complete and
Hosted-Verified.**

---

## -6. Prior session: Sprint 1.2A — Durable Processing Orchestration

Implemented workstream `S1-C1`: a reliable execution control plane for
the `document_processing_jobs` rows Sprint 1.1 creates `queued` —
atomic Worker claim, hashed-lease ownership with heartbeat renewal,
exponential-backoff retry, max-attempt dead-lettering, lease-expiry crash
recovery, and queued/retry-scheduled cancellation — proven end-to-end
with a **controlled no-op processor**, deliberately not real PDF
extraction (that's Sprint 1.2B, `S1-C2`). Migration
`0007_durable_processing_orchestration.sql`.

**Mandatory review completed first:** Sprint 1.1's
`completeGuidelineUploadAction` fully buffered the uploaded file into
memory (`.download().arrayBuffer()`) before computing size/PDF-signature/
SHA-256. Refactored to genuine incremental streaming
(`apps/web/lib/documents/streamVerification.ts`) — same trust model, same
50 MB limit, provably early-aborts on an oversized stream.

**Architecture (ADR 0009):** the database remains the durable
orchestration source of truth; a queue message, if one is ever
introduced, would only be a wake-up mechanism, never authoritative. Mode
A (Worker polling loop) was chosen over introducing Supabase Queues this
sprint — correctness doesn't depend on it, proven under real dual-process
concurrency. A hashed lease token (never the plaintext) is the ownership
mechanism; the six new orchestration functions are structurally
uncallable by `authenticated` (see below for why that claim required a
real fix, not just a design intention).

**Two real, hosted-only bugs found and fixed** — neither reproducible
against local plain Postgres, both found only by actually running
verification against real hosted Supabase infrastructure:

1. `gen_random_bytes()`/`digest()` (pgcrypto) resolved fine locally
   (installed directly into `public` by a fresh `postgres:16` container)
   but not on hosted, where Supabase pre-installs pgcrypto in an
   `extensions` schema — the first real hosted claim call failed with
   `function gen_random_bytes(integer) does not exist`. Fixed by adding
   `extensions` to the two affected functions' `search_path` (safe on
   both environments: a nonexistent schema in `search_path` is silently
   skipped).
2. **The migration's core trust-boundary claim — "these six functions are
   never granted to `authenticated`" — was false on hosted** until this
   was found. `revoke all on function ... from public` does not undo
   Supabase's project-level `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE
   ON FUNCTIONS TO anon, authenticated, service_role`, which grants
   EXECUTE directly to those named roles at function creation time. A
   real authenticated-JWT call to `claim_next_document_processing_job`
   returned `200` before the fix — an ordinary signed-in
   `organization_admin` could genuinely claim and manipulate processing
   jobs. Fixed with an explicit, guarded `revoke execute ... from
   authenticated` / `from anon` on every function in this migration;
   re-verified the grant is now limited to `postgres`/`service_role` only,
   and the same call now correctly returns `403`/`404`. See ADR 0009's
   addendum and the verification record for the full account — this is
   now a documented lesson for every future Worker-only function.

**Verification, real not assumed:** local — web lint/typecheck/build
clean, all test assertions passing (9 suites, 2 new this sprint); a real
`postgres:16` Docker container had migrations 0001-0007 + seed + the full
RLS/orchestration suite (7+4+26+4+17+**27** = 85 assertions) run against
it, 100% passed; a genuine dual-OS-process concurrency proof (80 real
jobs, two independent `psql` connections racing) — zero double-claims,
zero lost jobs; Worker — 27/27 pytest assertions, `compileall` clean.
Hosted — migration applied and confirmed (`local==remote`), **30/30 real
assertions** including the security trust-boundary proof, a full
claim/lease/heartbeat/retry/dead-letter/recovery/cancel lifecycle, RLS
read-restriction, and a 20-parallel-request real HTTP concurrency race
(zero duplicate claims) — all with real GoTrue JWTs and real
`service_role` credential usage, synthetic data cleaned up and confirmed
zero-residue. Vercel Preview redeployed, healthy, Deployment Protection
unchanged and correctly enforced. Full record:
`docs/verification/sprint-1.2a-processing-orchestration-verification.md`.

**Sprint 1.2A (Durable Processing Orchestration): Complete and
Hosted-Verified.**

---

## -5. Prior session: Sprint 1.1 — Secure Guideline Source Document Intake

Implemented workstream `S1-B`: a trusted, tenant-safe, auditable path from
an approved guideline version to a verified private source document and a
durable, idempotently-created processing job (`queued` only — no claim or
execution). Migration `0006_secure_guideline_document_intake.sql`.

**Two mandatory corrections completed first, per the mission:**

1. **G-12 closed** — the one gap the prior Sprint 1 report left open
   (self-approval by a creator who *also* holds `guidelines.approve` was
   blocked by code but never exercised by a live test, since no seeded
   role combined both). A dedicated regression test
   (`supabase/tests/rls/004_g12_self_approval_regression.sql`) creates a
   synthetic role holding `guidelines.create` + `guidelines.approve` on
   one user, has that user author and submit a version, gets a genuine
   recommending review from a different user, then attempts self-approval
   — denied, with confirmed-unchanged lifecycle status, no approval
   lifecycle event, and no falsely-claiming audit event. Passed against
   plain Postgres 16 **and** hosted Development with a real GoTrue JWT
   (the synthetic role was cleaned up on hosted afterward).
2. **Backlog reconciled** — the prior report undercounted what the S1-A
   vertical slice actually delivered (application layer, UI, hosted
   verification, not just schema). `MASTER_BACKLOG.md` restructured from
   the original flat `S1-NN` guess into coherent workstreams: `S1-A`
   (Guideline Registry, done), `S1-B` (this sprint's Secure Document
   Intake, now also done), `S1-C`/`S1-D`/`S1-E` (future — processing,
   extraction, retrieval).

**Architecture (ADR 0008):** three state machines kept deliberately
separate — clinical publication (unchanged), upload session (`created →
authorized → completed/expired/rejected/cancelled`), and processing job
(`queued` only this sprint). A second, load-bearing decision: unlike
Sprint 1's guideline registry, this migration cannot keep 100% of its
logic in SQL — Postgres cannot read Storage object bytes. File facts
(size, PDF signature, SHA-256) are computed by the Next.js server, which
independently re-downloads the uploaded object using the same RLS-scoped
session that uploaded it (no service-role key anywhere in this flow), and
passes those computed facts as *inputs* to `complete_guideline_upload()` —
the browser is trusted for nothing beyond "which file did the user pick."

**A real, two-part bug found by actually running the migration**, not by
reading the SQL: both `create_guideline_upload_session()` and
`complete_guideline_upload()` use `RETURNS TABLE`, which creates an
implicit PL/pgSQL variable per output column; two of those names (`status`,
`source_document_id`) collided with real table columns queried later in
the same function body, producing `column reference "..." is ambiguous"`
only when actually executed against Postgres 16 — not at migration-apply
time. Fixed by table-qualifying both references. See
`docs/database/secure-document-intake-schema.md`.

**Verification, real not assumed:** local — web lint/typecheck/build
clean, 63/63 `npm run test --workspace=apps/web` assertions (3 new
suites); a real `postgres:16` Docker container had migrations 0001-0006 +
seed + the full RLS suite (7+4+26+4+**19** = 60 assertions) run against it,
60/60 passed. Hosted — migration applied and confirmed
(`local==remote`), **16/16 real assertions including actual Supabase
Storage upload/download I/O** (a synthetic `%PDF-`-signed fixture file
really uploaded, really re-downloaded, really hashed) plus the hosted G-12
run, all synthetic data and both Storage objects cleaned up and confirmed
deleted. Vercel Preview redeployed, healthy, Deployment Protection
unchanged and correctly enforced. Full record:
`docs/verification/sprint-1.1-document-intake-verification.md`.

**Sprint 1.1 (Secure Guideline Source Document Intake): Complete and
Hosted-Verified.**

---

## -4. Prior session: Sprint 1 — Guideline Registry Schema and Lifecycle

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

**Sprint 1 — workstream S1-C2, Deterministic PDF Page and Text
Extraction, just closed locally (hosted verification in progress).**
Sprint 0.5 (hosted infrastructure & design system) is **Complete and
Hosted-Verified** — see §-3/§1 for that history; it is not reopened here.
See `MASTER_BACKLOG.md` for the reconciled Sprint 1 workstream breakdown
(S1-A/S1-B/S1-C1/S1-C2/S1-D/S1-E) — Sprint 1 is no longer tracked as a
single flat task list.

**S1-A (Guideline Registry Schema and Lifecycle) — Complete and
Hosted-Verified** (prior session): schema, lifecycle engine, RLS,
permissions, application layer, minimal UI — 41/41 Postgres 16 assertions,
18/18 hosted real-JWT assertions.

**S1-B (Secure Guideline Source Document Intake) — Complete and
Hosted-Verified** (prior session): upload sessions, server-verified object
intake (size/PDF-signature/SHA-256), duplicate detection, idempotent
registration and job creation — 60/60 Postgres 16 assertions (cumulative,
all suites), 16/16 hosted assertions including real Supabase Storage
upload/download I/O. **G-12 also closed** that session, on both
environments. Full record:
`docs/verification/sprint-1.1-document-intake-verification.md`.

**S1-C1 (Durable Processing Orchestration) — Complete and
Hosted-Verified** (prior session): atomic Worker claim, hashed-lease
ownership with heartbeat renewal, exponential-backoff retry, dead-letter
on exhaustion, lease-expiry crash recovery, queued/retry-scheduled
cancellation, all proven with a controlled no-op processor — 85/85
Postgres 16 assertions (cumulative, all suites), a genuine dual-OS-process
concurrency proof (80 jobs, zero double-claims), 30/30 hosted assertions
including a 20-parallel-request real HTTP concurrency race. **Two real,
hosted-only bugs found and fixed that session** — a pgcrypto
`search_path` gap and a default-privileges gap that had silently made the
migration's core trust-boundary claim false (see §-6 above for the full
account). Full record:
`docs/verification/sprint-1.2a-processing-orchestration-verification.md`.

**S1-C2 (Deterministic PDF Page and Text Extraction) — locally complete,
hosted verification in progress** (this session): the Worker's controlled
no-op processor is replaced with a real, deterministic `pypdf`-based
extraction pipeline (ADR 0010) — source integrity revalidated twice
independently, page-level text extraction/normalization, page/artifact
checksums, technical metrics, conservative suspected-scanned detection, a
canonical JSON artifact independently re-verified after upload, atomic
finalization with idempotent identity-based reuse. Full 001–008 Postgres
16 suite green; two genuine dual-OS-process concurrency proofs (the
unchanged S1-C1 claim-race script, and a new extraction-identity-race
script — 5 consecutive runs, all 4 possible race outcomes observed, zero
unexpected errors); 91/91 Worker pytest assertions. **Two real
concurrency bugs found and fixed this session** by actually racing two
independent processes at the same extraction identity — see §-7 above for
the full account. Web lint/typecheck/build/test all clean. Full record:
§-7 above and
`docs/verification/sprint-1.2b-pdf-extraction-verification.md`.

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
**Closed this session:** G-13 (no processing-worker claim/retry
implementation — the orchestration control plane is now real: atomic
claim, hashed-lease ownership, heartbeat renewal, exponential-backoff
retry, dead-lettering, crash recovery, and cancellation all exist and are
hosted-verified, proven with a controlled no-op processor). The Durable
Processing Orchestration workstream (S1-C1) itself is Complete and
Hosted-Verified.

**Closed this session:** G-14 — the Worker's controlled no-op processor is
replaced with a real, deterministic PDF page/text extractor (`pypdf`, ADR
0010). Source integrity is revalidated twice independently before any
extraction; a canonical JSON artifact (proven byte-identical across
repeated runs) is uploaded privately and independently re-verified;
finalization is atomic with idempotent identity-based reuse. Two real
concurrency bugs were found and fixed by actually racing two independent
processes at the same extraction identity — see §-7 for the full account.
Verified both locally (001–008 RLS suite, two genuine dual-process
concurrency proofs, 91/91 Worker pytest assertions, full web
build/lint/test) and against the real hosted Development project (real
GoTrue JWT, real Storage upload/download, the actual unmodified Worker
code claiming and extracting a real PDF, idempotent reprocessing, trust
boundary, RLS) — see §-7 and
`docs/verification/sprint-1.2b-pdf-extraction-verification.md`. The
Deterministic PDF Extraction workstream (S1-C2) itself is Complete and
Hosted-Verified.

**Closed prior sessions:** G-01 (hosted Supabase), G-08 (Vercel Protection
Bypass), G-11/G-12 (Sprint 1.1 items), G-02/G-05/G-06 (Sprint 0 items) —
see git history for the session-by-session record; not repeated here.

None of the remaining gaps (G-03, G-04, G-07, G-09, G-10) block starting
Sprint 1-D — each is either a product/clinical decision, later Sprint 1
work explicitly out of scope (AI provider selection), or a documented
pre-Controlled-Beta requirement.

---

## 6. Recommended next task

Workstream S1-C2 (Deterministic PDF Page and Text Extraction) is Complete
and Hosted-Verified: a real, deterministic `pypdf`-based extractor (ADR
0010, selected over the mission's suggested PyMuPDF specifically for its
AGPL-3.0 licensing) plugs into the unchanged S1-C1 claim/lease/retry/
complete lifecycle. Source-integrity double-revalidation, deterministic
normalization, canonical JSON artifacts, atomic idempotent finalization,
minimal Admin/Reviewer UI, and two real concurrency bugs found and fixed
via genuine dual-process racing are all implemented and verified against
plain Postgres 16, the Worker's own pytest suite (91/91), and the real
hosted Development project end-to-end (real GoTrue JWT, real Storage,
the actual unmodified Worker code). See §-7 for the full account and
`docs/verification/sprint-1.2b-pdf-extraction-verification.md` for the
complete verification record.

```text
Begin Sprint 1-D — Extraction Review, OCR Decision, and Deterministic Chunking
```

This is workstream S1-D (`MASTER_BACKLOG.md`): a reviewer queue over
extraction results, a real decision on OCR for suspected-scanned pages,
and deterministic chunking — none of which are implemented in S1-C2 by
design (see `docs/domain/document-extraction-lifecycle.md`). G-03
(clinical domain confirmation) should ideally be resolved before or
alongside real content work. Playwright browser-driven E2E (G-09) stays a
documented pre-Controlled-Beta requirement, not a blocker.
