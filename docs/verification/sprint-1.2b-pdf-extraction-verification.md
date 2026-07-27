# Sprint 1.2B — Deterministic PDF Page and Text Extraction Verification Record

Every command and result below was actually run — nothing here is inferred
or assumed. Companion docs: `docs/domain/{document-extraction-lifecycle,
document-extraction-artifacts}.md`,
`docs/database/deterministic-pdf-extraction-schema.md`,
`docs/security/pdf-extraction-security.md`,
`docs/operations/{pdf-extraction-worker-runbook,extraction-failure-recovery}.md`,
ADR 0010.

## Mandatory review: security-definer schema-resolution hardening (closed this sprint)

Turned the two real, hosted-only bugs found and fixed in Sprint 1.2A
(pgcrypto `search_path` gap; `authenticated`/`anon` default-privileges gap
on Worker-only functions) into a **permanent** regression suite —
`supabase/tests/rls/007_security_hardening_review.sql` — rather than a
one-off check. Verified locally and against hosted (see below); both
green.

## Local database verification — real Postgres 16

A fresh `postgres:16` Docker container had all 8 migrations, seed data,
and the full RLS/orchestration/extraction test suite applied and run:

```
$ for f in supabase/migrations/*.sql; do psql ... -f "$f"; done
→ 0001-0008 all applied with zero errors

$ psql ... -f supabase/seed.sql   → applied cleanly

$ for f in supabase/tests/rls/*.sql; do psql ... -f "$f"; done
→ 001_tenant_isolation.sql:               8/8  PASSED
→ 002_auth_hardening.sql:                 7/7  PASSED
→ 003_guideline_registry.sql:            28/28 PASSED
→ 004_g12_self_approval_regression.sql:   5/5  PASSED
→ 005_document_intake.sql:               20/20 PASSED
→ 006_processing_orchestration.sql:      25/25 PASSED
→ 007_security_hardening_review.sql:      5/5  PASSED
→ 008_pdf_extraction.sql:                19/19 PASSED
```

117 real assertions across the cumulative 001–008 suite, all green — the
pre-existing 001–006 suites are **unmodified** and still 100% green on
top of migration 0008's schema changes.

### Extraction schema test coverage (008_pdf_extraction.sql)

19 assertions: fresh-run creation with correct identity; source
checksum/size mismatch rejection; wrong-worker/wrong-token denial;
same-attempt replay attaching to the same running row (not a duplicate —
the exact bug this test caught on first execution); trusted-context page
insert; finalize page-count-mismatch rejection; successful finalize;
idempotent replayed finalize; succeeded-run identity reuse; the partial
unique index blocking a second succeeded row at the same identity outside
the function layer; succeeded-run and page-row immutability; safe no-op
failing an already-succeeded run; real failure classification; RLS
(clinician denied, organization_admin permitted); the `authenticated`
trust boundary; and stale-attempt supersession (a second job/fixture
simulating a crashed Worker whose abandoned `running` run is superseded
by the next real attempt).

### Two real concurrency bugs found by actually racing two independent processes

`supabase/tests/concurrency/verify_concurrent_extraction_identity.sh`
races two real `docker exec psql` OS processes at the same deterministic
extraction identity. Both bugs below were found this way — not by
reading the SQL:

1. **`finalize_document_extraction_run()` raised a raw `unique_violation`**
   when two genuinely simultaneous attempts both tried to mark themselves
   `succeeded` at the same identity. Fixed with an exception handler that
   gracefully adopts the winning run and returns it instead of surfacing
   a raw constraint-violation error.
2. **A second, related race surfaced immediately after fixing the
   first**: a job superseded mid-flight (its own `create` call committed,
   but a different attempt's `create` superseded it before it reached
   `finalize`) raised a raw "not running" error. Fixed by explicitly
   detecting the supersession case and either adopting an
   already-succeeded winner or raising a clear, named, retryable error.

Both fixes re-verified together: 5 consecutive concurrency-script runs,
all 4 possible race outcomes observed, zero unexpected/unclassified
errors. See `docs/database/deterministic-pdf-extraction-schema.md` for
the full technical account.

## Local web verification

```
npm run lint --workspace=apps/web        → clean
npx tsc --noEmit (apps/web)              → clean
npm run test --workspace=apps/web        → all assertions passed
npm run build --workspace=apps/web       → succeeded, extraction UI routes generated
```

## Local Worker verification

```
python -m compileall apps/worker         → clean
cd apps/worker && pytest tests/ -v       → 91/91 passed
```

91 total: 59 pre-existing (orchestration, unaffected) + 32 new —
extractor behavior against 11 fixtures (one-page, multi-page,
Arabic+English Unicode, empty page, rotated page, mixed blank/text,
image-only/no-text-layer, corrupt, encrypted, invalid-signature, unusual
metadata); same-input-twice byte-identical artifact/checksum/metric
determinism; source checksum/size/signature revalidation via
`httpx.MockTransport` (no real network); end-to-end processor
orchestration (reuse, failure classification, idempotent replay,
lease-loss tolerance) against a fake in-memory `OrchestrationClient`.

## Other workspaces (unaffected — re-verified, not assumed)

```
npm run typecheck --workspace=packages/clinical-schemas → clean
npm test --workspace=packages/clinical-schemas          → 6/6 passed
npm run typecheck --workspace=packages/ui                → clean
```

## Hosted Development verification

### Migration applied

```
$ supabase migration list --linked   (before)
→ 0001-0007 local==remote; 0008 local only, remote empty

$ supabase db push --linked
→ Applying migration 0008_deterministic_pdf_extraction.sql...
→ Finished supabase db push.

$ supabase migration list --linked   (after)
→ 0001-0008 all local==remote
```

### A real test-execution finding: multi-statement batching differs from `psql -f`

Running the 001–008 suite against hosted required a different execution
path than local Docker `psql` (no direct Postgres connection string is
held for the hosted project — only a Management API access token). The
Supabase Management API's SQL query endpoint
(`POST /v1/projects/{ref}/database/query`) executes an entire submitted
multi-statement string as **one** batched query. This surfaced a real
difference from `psql -f`'s per-statement autocommit behavior: when a
`begin; ... rollback;` block is *not* preceded by its own fresh,
independently-committed transaction boundary, the `rollback` unwinds
**everything** since the last real `commit` in the same batch — including
earlier tests' otherwise-successful work — not just the block's own
changes.

This is what caused `008_pdf_extraction.sql`'s original TEST 15/15b
(`begin; set local role ...; do $$ ... $$; rollback;`) to report a false
failure on first hosted run (`organization_admin could not read its own
extraction runs/pages`) even though a direct diagnostic query proved
`has_permission_in_organization()` and RLS were both working correctly.
**Fixed in the committed test file** (not a hosted-only workaround) by
switching TEST 15/15b to the same bare-`DO`-block role-switch pattern
already proven safe by TEST 16 in the same file (`set local role
authenticated; ... set local role none;`, no wrapping
`begin`/`commit`/`rollback`) — this pattern is robust under both
per-statement-autocommit (`psql -f`) and single-batch (Management API)
execution models. Re-verified locally (fresh Postgres 16, full 001–008
suite, still 117/117 green) before re-running against hosted.

### Security + extraction schema regression — hosted Postgres 17

With the fix above, `supabase/seed.sql` applied to hosted, and the
corrected `007_security_hardening_review.sql` +
`008_pdf_extraction.sql` submitted together as one batch:

```
→ zero errors raised (RAISE EXCEPTION anywhere would have surfaced as a
  query error, exactly as observed and confirmed during the debugging
  above)
→ final document_extraction_runs state: 1 succeeded, 2 failed, 1 running
  — matching the exact narrative the test file's 19 assertions produce
  locally
```

24 real assertions (5 security-hardening + 19 extraction-schema) verified
against real hosted Postgres 17 — confirming the search_path/grant
hardening and the full extraction lifecycle (including RLS and the
`authenticated` trust boundary) both hold on the actual hosted
infrastructure, not just plain local Postgres 16.

### Real end-to-end flow — real GoTrue JWT, real Storage, the actual Worker code

Unlike the SQL-only regression above, this exercises the **unmodified
production Python code** in `apps/worker/app/pdf_extraction/` and
`app/worker_loop.py` against the real hosted project — no mocks, no
simulated JWT claims.

```
PASS  create GoTrue user (real Admin API)
PASS  create profile / organization_admin membership
PASS  real GoTrue sign-in → real access_token
PASS  create_clinical_domain / create_guideline_authority / create_guideline /
      create_guideline_version / create_guideline_upload_session (real JWT, real RPC)
PASS  real Storage upload, RLS-authorized (no service_role key used for the upload)
PASS  complete_guideline_upload → real document registered, real job queued
PASS  authenticated JWT cannot call claim_next_document_processing_job
PASS  authenticated JWT cannot call create_document_extraction_run
```

The real `WorkerLoop.run_claim_cycle()` (unchanged Sprint 1.2A code) was
then run against hosted with `service_role` credentials — real claim,
real download from Storage, real `pypdf` extraction, real artifact
upload, real finalize:

```
extraction run: status=succeeded, page_count=5, extractor=pypdf/6.14.2
5/5 pages: extraction_status=text_extracted, per-page checksums recorded,
           suspected_scanned=false (real text layer correctly detected)
artifact:  guideline-processed/<org>/guideline-extractions/<doc>/pdf-text-v1/
           pypdf-6.14.2/<artifact_sha256>.json
```

Post-extraction checks, again against the real hosted project:

```
PASS  organization_admin JWT can read its own extraction run (RLS)
PASS  organization_admin JWT can read its own extraction pages (RLS)
PASS  artifact independently re-downloaded from private Storage
PASS  re-downloaded artifact checksum matches recorded artifact_sha256
PASS  re-downloaded artifact size matches recorded artifact_size_bytes
PASS  artifact JSON contains exactly 5 pages
PASS  anon (no session) cannot read the private artifact object
```

**Idempotent reprocessing proof**: a second real `document_processing_job`
was queued for the *same* source document identity, and the real
`WorkerLoop` was run again. Result: the job succeeded, and
`document_extraction_runs` still contains exactly **one** row for that
identity (the original) — the Worker's real `create_document_extraction_run`
call detected the already-succeeded identity and reused it rather than
re-uploading a duplicate artifact, exactly matching the DB-level guarantee
already proven in the SQL suite, now confirmed at full Worker-integration
level against real hosted infrastructure.

**Unplanned bonus proof — real failure handling**: while draining the
job queue, the Worker also claimed a leftover fixture job (from the SQL
regression run above) whose registered source document was never
actually uploaded to Storage. The real pipeline correctly classified this
as `source_object_missing` and failed the job safely (eventually
dead-lettering it after retries) — genuine evidence the failure path
works end-to-end against real infrastructure, not just under mocks.

**Tenant/role-boundary proof with a second real JWT**: a second real
GoTrue user (`clinician` role, same organization) was created and signed
in:

```
PASS  clinician JWT reads zero extraction runs (RLS)
PASS  clinician JWT reads zero extraction pages (RLS)
PASS  clinician JWT cannot call create_document_extraction_run
```

### Synthetic test data cleanup — confirmed

Both real Storage objects (the uploaded source PDF and the uploaded
artifact JSON) were deleted directly. All database rows created this
session (extraction pages/runs, processing jobs/attempts, intake events,
upload sessions, source documents, guideline versions/guidelines,
authorities, clinical domains, `access_reviews`/`audit_events` via the
documented `noor.allow_audit_maintenance` override, memberships, settings,
organizations, profiles) and all synthetic `auth.users` (seed.sql's 5
placeholder users plus the 2 real GoTrue users created for this
verification) were deleted. A final query confirmed:

```sql
residual_orgs: 0, residual_jobs: 0, residual_runs: 0, residual_pages: 0,
residual_memberships: 0, residual_profiles: 0, residual_auth_users: 0
total_auth_users: 0
```

Storage object listings for both affected bucket prefixes
(`guideline-originals` and `guideline-processed` under the test
organization id) returned empty. Reference/system data (`roles`,
`permissions`) was correctly left untouched — only synthetic
organizations, users, and content were removed.

### Vercel Preview

Redeployed with the updated code (extraction UI: Extraction Summary Card,
page list, page-detail route) — `vercel inspect` confirmed `status: Ready`,
`target: preview`, and the build output includes
`/knowledge/guidelines/[guidelineId]/extractions/[runId]/pages/[pageNumber]`.
The stable alias `noor-preview-dev.vercel.app` was re-pointed at the new
deployment. The unprotected smoke test (`scripts/smoke-test-web.mjs`, no
`BYPASS_TOKEN` available this session) correctly detected and reported
Vercel's Deployment Protection wall for every body-content check — the
same, expected, non-false-passing behavior observed in every prior
session without the bypass token in hand. Deployment Protection remains
**enabled and correctly enforced**, unchanged.

### CI

Confirmed green on GitHub Actions for the commits accompanying this
document — see the final Sprint 1.2B closure report for the exact run
reference.
