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
* **Secure document intake (Sprint 1.1): every write mediated the same
  way, plus server-side file verification the browser cannot forge.**
  Migration `0006_secure_guideline_document_intake.sql` adds 5 tables,
  all following the same SECURITY DEFINER-only write model. No arbitrary
  Storage bucket or path is ever client-selectable — paths are generated
  server-side from server-verified identifiers, with the only
  client-influenced segment (the filename) sanitized to strip any
  directory-traversal character. File facts the app must not trust from
  the browser — size, PDF signature, SHA-256 — are computed by the
  Next.js server after it independently re-downloads the object from
  Storage using the same RLS-scoped session that uploaded it (no
  service-role key anywhere in this flow); see ADR 0008. Verified: 19/19
  real assertions against plain Postgres 16
  (`supabase/tests/rls/005_document_intake.sql`) + **16/16 real hosted
  assertions including an actual Supabase Storage upload/download round
  trip** (a synthetic `%PDF-`-signed fixture file genuinely uploaded,
  re-downloaded, and hashed — not simulated). See
  `docs/security/document-intake-authorization.md` and
  `docs/verification/sprint-1.1-document-intake-verification.md`.
* **Durable processing orchestration (Sprint 1.2A): a stricter trust
  boundary than any prior migration.** Migration
  `0007_durable_processing_orchestration.sql` adds six functions
  (claim/start/heartbeat/complete/fail/recover-expired) that are **never
  granted to `authenticated` at all** — no signed-in user's session,
  regardless of permissions their role holds, can call them; only the
  Worker's `service_role` credential can. Job ownership within that shared
  credential is enforced by a hashed lease token
  (`lease_token_hash = sha256(lease_token)`), never a plaintext
  comparison, verified by `assert_lease_owner()` before every state
  change. A Worker that loses its lease (crashed, or reclaimed by
  `recover_expired_document_processing_jobs()`) structurally cannot
  subsequently complete or heartbeat that job — the hash comparison fails
  and the function raises. Proven correct under real concurrency, not
  just sequential-session inference:
  `supabase/tests/concurrency/verify_concurrent_claim.sh` raced two
  independent OS processes against 80 shared jobs — zero double-claims,
  zero lost jobs. Processor exceptions are caught and reported with a
  generic, safe message — never the raw exception text, which could
  contain internals. See
  `docs/security/worker-orchestration-authorization.md` and
  `docs/domain/document-processing-orchestration.md`.
* **Deterministic PDF extraction (Sprint 1.2B): the same hardened trust
  boundary, applied from the start.** Migration
  `0008_deterministic_pdf_extraction.sql` adds three more Worker-only
  functions, never granted to `authenticated`/`anon` from their very first
  version — the exact fix migration 0007 needed a real hosted-only bug to
  discover (see above) is now a permanent regression test
  (`supabase/tests/rls/007_security_hardening_review.sql`) and was applied
  proactively here rather than found the hard way twice. Source-document
  integrity is revalidated independently in two places (Worker-side
  streaming checksum/size/signature check, and again by the database
  function before it will create an extraction run) before any extraction
  ever begins — a checksum mismatch produces zero artifact. Two real
  concurrency bugs were found and fixed by actually racing two independent
  OS processes at the same deterministic extraction identity
  (`supabase/tests/concurrency/verify_concurrent_extraction_identity.sh`,
  5 consecutive runs, all 4 possible race outcomes observed): a raw
  `unique_violation` on simultaneous success, and a raw "not running"
  error when a job's run was superseded mid-flight — both now resolved
  gracefully, never a raw database error surfaced to the Worker. See
  `docs/security/pdf-extraction-security.md`.
* **Extraction review and technical quality gate (Sprint 1-D1): a
  separate permission namespace enforces the review/execution boundary
  from outside the schema too.** `guideline_extraction_reviews.*` /
  `guideline_extraction_findings.*` / `guideline_extraction_source.*` are
  deliberately not part of migration 0008's `guideline_extractions.*`
  namespace. Clinicians hold none of them, verified with both a
  simulated role-switch and a real hosted GoTrue JWT. Self-review is
  blocked at the database level (a reviewer cannot start a review of a
  document they personally uploaded or registered). Signed source-PDF
  access is minted server-side, per-request, short-lived (5 minutes),
  and never persisted or logged — the session's own client is used, no
  service-role key anywhere in that path. Submitted review decisions are
  immutable (one legal exception: an accepted decision may later be
  administratively invalidated); findings' core content is immutable
  from creation and can never be deleted. `009_extraction_review.sql`'s
  own explicit `grant select`/`grant execute` block was written at the
  top of the file from the start, applying Sprint 1.2B's real CI-only
  grant-timing lesson proactively rather than rediscovering it. See
  `docs/security/extraction-review-authorization.md`.
* **G-12 closed this session:** a guideline-version creator who also holds
  `guidelines.approve` still cannot approve their own version — the one
  self-approval scenario the Sprint 1 guideline-registry test suite could
  not exercise (no seeded role combined both permissions). A dedicated
  regression test (`supabase/tests/rls/004_g12_self_approval_regression.sql`)
  closes this, verified against plain Postgres 16 and hosted Development
  with a real JWT: request denied, lifecycle status unchanged, no
  falsely-claiming lifecycle or audit event.
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
* **`storage.objects` RLS for `guideline-originals`/`guideline-processed`
  is now permission-scoped, not merely organization-scoped** (Sprint
  1-D2, migration `0010_permission_scoped_storage_access.sql`) — closes
  the residual risk documented in Sprint 1-D1. See
  `docs/security/ocr-and-storage-authorization.md`.
* **OCR is self-hosted (Tesseract), never a cloud API** — no guideline
  page content leaves Noor's own infrastructure for OCR, no third-party
  API key or DPA to protect. OCR only ever processes pages a human
  reviewer explicitly flagged, never a whole document automatically
  (ADR 0012). The three Worker-only OCR functions are explicitly
  revoked from `PUBLIC`/`anon`/`authenticated`, the same trust boundary
  as every other Worker-only function in this codebase.
* **Deterministic page-aware chunking (Sprint 1-D3): a deliberately
  separate permission namespace, one layer deeper than OCR.**
  `guideline_chunking.*` is distinct from both `guideline_extractions.*`
  and `guideline_ocr.*`; clinicians hold none of it. The four Worker-only
  chunking functions authenticate purely via lease ownership, never via
  organization permissions — a real design bug of exactly this kind
  (a Worker-only function accidentally calling a permission-gated one,
  which would always fail against `service_role`'s `auth.uid()`-less
  JWT) was caught and fixed before any test ran, and is now a documented
  permanent lesson (`docs/database/deterministic-chunking-schema.md`,
  `docs/security/chunking-authorization.md`). Self-review is blocked at
  the database level, matching extraction/OCR review. Chunks and their
  source spans are fully immutable once created — no maintenance
  override exists for direct deletion of either table (unlike finding
  tables), a documented gap to revisit only if a real operational need
  arises.
* **Retrieval evaluation foundation (Sprint 1-E1): another deliberately
  separate permission namespace, one layer deeper than chunking.**
  `retrieval_evaluation.*` is distinct from every guideline-pipeline
  namespace; clinicians hold none of it — this is a purely internal
  Quality-workspace feature, never exposed as a clinician-facing search
  endpoint. The four Worker-only retrieval functions
  (`get_retrieval_evaluation_job_context`/`get_retrieval_candidates`/
  `finalize_retrieval_evaluation_run`/`fail_retrieval_evaluation_run`)
  authenticate purely via lease ownership, never via organization
  permissions, explicitly revoked from `authenticated`/`anon`. A dataset's
  own creator is blocked at the database level from marking it reviewed
  for freezing (two-person separation) — enforced in SQL, not just a UI
  convention, so it holds even against a direct RPC call. Two real,
  hosted-only bugs were found and fixed this sprint: a dataset-scoped job
  could never be claimed by the Worker (migration 0007's original
  eligibility check assumed every job resolves to one document), and two
  functions computing checksums via `digest()` were missing `extensions`
  in their `search_path` (pgcrypto lives in a different schema on hosted
  Supabase than on local plain Postgres) — both are now documented
  permanent lessons (`docs/database/retrieval-evaluation-schema.md`,
  `docs/security/retrieval-evaluation-authorization.md`).
* **Embedding and pgvector foundation (Sprint 1-E2): raw vectors never
  reach the browser, and there is no client-supplied-vector code path at
  all.** `document_chunk_embeddings.vector_value`/
  `retrieval_evaluation_query_embeddings.vector_value` are never selected
  by any web-application query — only checksums, norms, dimensions, and
  status. Every vector persisted through `record_document_chunk_embedding`/
  `record_query_embedding` (both Worker-only, lease-authenticated, never
  via organization permissions, explicitly revoked from
  `authenticated`/`anon`) originates from the Worker's own
  `EmbeddingProvider.embed()` call — there is no code path from an
  `authenticated` JWT to either function, and no client can submit a
  vector, dimension, similarity expression, distance metric, index
  parameter, provider model name, or provider credential. The provider
  itself is fully self-hosted (`intfloat/multilingual-e5-base` via
  `sentence-transformers`), so there is no provider API key or bearer
  token to leak by construction — a real, deliberate difference from a
  future external-API provider, which would need the same
  Worker-only/environment-managed/never-logged discipline already
  applied to `SUPABASE_SERVICE_ROLE_KEY`/`WORKER_INTERNAL_TOKEN`. A
  cross-tenant vector search is structurally impossible, not merely
  discouraged: `get_vector_search_candidates` scopes its join by both
  `dataset_id` and the claiming job's own `organization_id` together.
  Two real, local-only bugs were found and fixed this sprint (a missing
  CHECK-constraint branch for the new job type, a `real`/`numeric`
  return-type mismatch) — see
  `docs/database/embedding-and-vector-schema.md`,
  `docs/security/embedding-and-vector-authorization.md`.

## Known gaps (Sprint 1+)

* **UX-1's brand asset pipeline was reviewed for the standard image-
  supply-chain risks**: the source logo carries no unnecessary metadata
  worth stripping (a plain photo-editor JPEG, no embedded GPS/author
  fields beyond default JFIF), no private filesystem path or secret is
  embedded in any derived asset, and no screenshot or documentation
  produced this sprint contains real user data (synthetic examples
  only). A real Vercel Preview deployment/browser check — including its
  own bundle/secret scan — has not been performed this session segment;
  see `docs/verification/ux-1-brand-alignment-verification.md`.
* No malware/antivirus scanning of the source PDF beyond signature
  validation (unchanged from Sprint 1.1) applies equally to the Worker's
  `pypdf`-based parsing step — a malicious PDF could theoretically exploit
  a `pypdf`-level vulnerability. The extraction timeout and
  exception-containment around every parse path are the only mitigations
  in place this sprint. See `docs/security/pdf-extraction-security.md`.
* No dependency vulnerability scanning beyond `npm audit` run manually —
  not wired into CI as a blocking gate yet. The same applies to the
  Worker's `pip` dependencies (`pypdf`, `reportlab`, `pillow`, and, as of
  Sprint 1-D2, `pytesseract`/`pypdfium2`) — no automated Python
  dependency audit exists in CI yet.
* **The OCR web application UI (request status, review queue, side-by-side
  review workspace, and the `guideline_ocr.read_source`-gated signed-
  source-access action) has been implemented and verified (typecheck/
  lint/build/unit tests, the underlying RPCs and Storage RLS proven
  against real hosted infrastructure, and a real Vercel Preview
  deployment confirmed `Ready`) but has not had a real browser-rendered
  security review** — no Playwright/browser-driven E2E has been
  performed, and this Vercel team's own SSO Deployment Protection blocks
  any headless check of the live Preview URL. See
  `docs/security/ocr-and-storage-authorization.md`.
* A new transitive dependency, `sharp` (pulled in by Next 15's image
  pipeline), carries its own disclosed advisory. `apps/web` doesn't use
  `next/image` anywhere, so this is currently inert — re-check before ever
  adopting it.
* **Closed, Sprint 1-D2:** `storage.objects` RLS for the two
  guideline-content buckets (`guideline-originals`/`guideline-processed`)
  is no longer organization-scoped alone — migration
  `0010_permission_scoped_storage_access.sql` now requires an explicit
  permission (`guideline_documents.read` / `guideline_extractions.read_artifacts`
  / `guideline_ocr.read_artifacts`) at the Storage RLS layer itself, real
  end-to-end against hosted with real GoTrue JWTs (clinician denied,
  permitted roles allowed — see
  `docs/verification/sprint-1-d2-controlled-ocr-verification.md`). The
  other three buckets (`evaluation-assets`/`generated-reports`/
  `temporary-uploads`) remain organization-scoped only — a deliberate
  scope decision, since none is used by any real flow yet. See
  `docs/security/ocr-and-storage-authorization.md`.
* No malware/antivirus scanning on uploaded PDFs — Sprint 1.1's intake
  flow validates the `%PDF-` file signature (confirms file *type*, not
  safety) and computes SHA-256, but no scanning provider is integrated
  (deliberately out of scope — no provider is available to wire in yet).
  Required before accepting externally-sourced documents at real scale.
  See `docs/security/document-intake-authorization.md`.
* No prompt-injection or data-exfiltration test suite exists yet — there
  is no generation pipeline to test against (PDF upload/registration and
  processing orchestration now exist and are verified;
  parsing/embeddings/retrieval/generation do not).
* `service_role` is shared by every Worker instance — there is no
  per-instance database credential; lease-token hash verification, not
  the database role, is what isolates one Worker instance's job from
  another's (Sprint 1.2A). See
  `docs/security/worker-orchestration-authorization.md`.
* `WORKER_INSTANCE_ID` uniqueness across a Worker fleet is not enforced in
  code — an operator who pins the same explicit value on two concurrently
  running processes could cause them to interfere with each other's
  leases. Auto-generated ids (the default) are randomized per process,
  making this practically unreachable unless explicitly configured.
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
