# Sprint 1-D1 — Extraction Review and Technical Quality Gate Verification Record

Every command and result below was actually run — nothing here is
inferred or assumed. Companion docs: `docs/domain/{extraction-review-lifecycle,
extraction-quality-findings}.md`, `docs/database/extraction-review-schema.md`,
`docs/security/extraction-review-authorization.md`,
`docs/operations/{extraction-review-runbook,extraction-review-reopening-and-invalidation}.md`,
ADR 0011.

## Local database verification — real Postgres 16, multiple genuinely fresh containers

Sprint 1.2B's own real CI-only bug (a migration's guarded `grant ... to
authenticated` block being a no-op at CI's migration-apply time, since
the RLS test file itself must issue the grant) was applied proactively
here: `009_extraction_review.sql`'s explicit grants were written at the
top of the file from the start, and the full suite was verified against
**several genuinely fresh `postgres:16` containers** — not the same
reused container across iterations — before being trusted:

```
$ for f in supabase/migrations/*.sql; do psql ... -f "$f"; done
→ 0001-0009 all applied with zero errors

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
→ 009_extraction_review.sql:             39/39 PASSED (+1 anon check
                                          correctly SKIPPED locally, no
                                          anon role on plain Postgres)
```

Repeated against 3 separate, freshly-created `postgres:16` containers —
100% green every time, no flake.

### Extraction review test coverage (009_extraction_review.sql)

39 assertions covering: review creation (success, idempotent reuse,
permission denial, rejection for a non-succeeded run); reviewer
assignment (success, denial for a non-permitted target, self-claim);
review start (success, re-start rejection, self-review blocking, a
different reviewer succeeding where the uploader was blocked); page-level
review coverage (mark-reviewed success, denial for a non-assigned
reviewer); findings (page-level, document-level, "other" requiring a
description, dismiss-with-no-reason rejection then success once a reason
is given); submission gating (rejected before full page coverage, then
succeeding with only minor/informational findings open); idempotent
replay; terminal-round immutability (direct UPDATE rejected, a second
genuine submission attempt rejected); reopening (creates a fresh round,
reverts eligibility, the prior round stays historically intact, an
active round cannot be reopened, the partial unique index blocks a
duplicate active round); invalidation (succeeds once, is itself
immutable); all 5 decision rules exercised end-to-end
(`accepted`/`accepted_with_warnings`/`ocr_required`/
`reprocessing_required`/`rejected`, each with both a rejection case and a
success case, and each decision's correct eligibility output); RLS
(clinician denied everywhere, organization_admin permitted, cross-tenant
denied); the `authenticated` trust boundary for the submit function; the
anon-role check (skipped locally, would run on hosted); findings cannot
be deleted; a finding's core content is immutable; append-only events;
and eligibility reporting `false` for everything when no review exists
at all.

## Local web verification

```
npm run lint --workspace=apps/web        → clean
npx tsc --noEmit (apps/web)              → clean
npm run build --workspace=apps/web       → succeeded; new routes generated:
  /reviewer/extractions
  /reviewer/extractions/[reviewId]
npm run test --workspace=apps/web        → all 12 test files pass individually
  (27 new assertions: extraction-review-schemas.test.ts,
  extraction-review-errors.test.ts, plus an extended permissions.test.ts
  check)
```

## Other workspaces (unaffected — re-verified, not assumed)

```
python -m compileall apps/worker         → clean
cd apps/worker && pytest tests/ -q       → 59/59 passed (unchanged)
npm run typecheck --workspace=packages/clinical-schemas → clean
npm test --workspace=packages/clinical-schemas          → 6/6 passed
npm run typecheck --workspace=packages/ui                → clean
```

## Hosted Development verification

### Migration applied

```
$ supabase migration list --linked   (before)
→ 0001-0008 local==remote; 0009 local only, remote empty

$ supabase db push --linked --yes
→ Applying migration 0009_extraction_review_quality_gate.sql...
→ Finished supabase db push.

$ supabase migration list --linked   (after)
→ 0001-0009 all local==remote
```

### A real test-execution finding: temp-table collision across concatenated files

Submitting `007+008+009` as one concatenated batch to the Management
API's SQL query endpoint (the same technique used successfully in Sprint
1.2B for 007+008) failed with `relation "test_fixtures" already exists`
— both 008's and 009's own fixture scaffolding create a temporary table
of that name, and since a batched submission runs as one session, the
second file's `CREATE TEMPORARY TABLE` collided with the first's still-
live table. **Fixed by submitting each file as its own separate request**
(each a genuinely independent session) rather than concatenating them —
007, 008, and 009 each ran clean with zero errors this way.

### Security + extraction + review regression — hosted Postgres 17

```
$ (seed.sql, then 007, 008, 009 each as a separate request)
→ zero errors raised in any of the three (a RAISE EXCEPTION anywhere
  would have surfaced as a query error, confirmed working correctly
  during Sprint 1.2B's debugging)
→ final document_extraction_reviews state: 1 accepted, 1 in_review,
  1 invalidated, 1 ocr_required, 2 pending_review, 1 rejected,
  1 reprocessing_required — matching the exact narrative the 39
  assertions produce locally
→ final document_extraction_review_findings state: 1 critical
  accepted_risk, 1 critical open, 1 informational open, 2 major open,
  1 minor open — also matching the local narrative
```

63 real assertions (5 security-hardening + 19 extraction-schema + 39
extraction-review) verified against real hosted Postgres 17 in this
session alone (007+008+009 combined), confirming the full review
lifecycle — including RLS and the `authenticated` trust boundary — holds
on real hosted infrastructure, not just plain local Postgres 16.

### Real end-to-end flow — real GoTrue JWTs, the actual production Worker code, then the new review functions

Built on top of a **genuinely fresh** real extraction run: a new real
GoTrue user uploaded a real PDF (`one_page_english.pdf`) via the real
upload flow, and the real, unmodified `apps/worker` code (`WorkerLoop.
run_claim_cycle()`, `service_role` credentials) claimed and extracted it
for real against hosted Storage and Postgres — `status=succeeded,
page_count=1` — before any review testing began.

Two more real GoTrue users were created (`clinical_reviewer`,
`quality_manager` roles) plus a `clinician` for the negative-permission
proof:

```
PASS  create_document_extraction_review (org_admin JWT)
PASS  review starts pending_review
PASS  clinician JWT reads zero reviews (RLS)
PASS  clinician JWT cannot start a review
PASS  assign_extraction_reviewer (org_admin JWT)
PASS  start_document_extraction_review (reviewer JWT)
PASS  review is now in_review
PASS  mark_extraction_page_reviewed (reviewer JWT)
PASS  submit_document_extraction_review accepted (reviewer JWT)
PASS  review is now accepted
PASS  get_document_extraction_review_eligibility (real RPC)
PASS  chunking eligible, OCR not eligible
PASS  reopen_extraction_review (quality_manager JWT)
PASS  reopened round is a new pending_review round
PASS  eligibility reverts to ineligible after reopen (real RPC)

15 passed, 0 failed
```

**Signed source-PDF access, verified at the infrastructure level**: the
exact mechanism `createExtractionReviewSourceAccessAction()` uses
(`supabase.storage.from(bucket).createSignedUrl(path, ttl)` on a
session-bound client) was exercised directly against the real uploaded
object — `POST /storage/v1/object/sign/...` returned `200` with a real
signed token, and downloading through that signed URL returned `200` with
`content-type: application/pdf`, confirming the storage_bucket/
storage_path plumbing the review workspace's PDF panel depends on is
correct end to end.

### A real bug, found only while cleaning up synthetic hosted test data

`prevent_extraction_finding_delete()`'s first version raised
unconditionally with **no** maintenance-override escape hatch —
inconsistent with every other append-only table in this codebase
(`audit_events`, `guideline_reviews`, `guideline_lifecycle_events`,
`document_extraction_review_events`, all of which honor
`noor.allow_audit_maintenance`). This meant synthetic finding rows from
this session's own tests could not be deleted at all, not even as the
connecting superuser — a real, previously-untested cleanup gap. **Fixed**
by adding the same override GUC check; hotfixed directly on hosted
(`CREATE OR REPLACE FUNCTION`, idempotent) so cleanup could proceed
immediately, then corrected in the migration file itself and re-verified
(3 fresh local containers, 41/41 assertions, plus a direct manual proof
that `set noor.allow_audit_maintenance = 'true'; delete from
document_extraction_review_findings;` now works and that it is still
rejected without the override) before being fully trusted.

### Synthetic test data cleanup — confirmed

Both real Storage objects (the uploaded source PDF and the real Worker's
uploaded artifact JSON) were deleted directly. All database rows created
this session (review findings, page reviews, review events, reviews,
extraction pages/runs, processing jobs/attempts, intake events, upload
sessions, source documents, guideline versions/guidelines, authorities,
clinical domains, `access_reviews`/`audit_events` via the documented
`noor.allow_audit_maintenance` override, memberships, settings,
organizations, profiles) and all synthetic `auth.users` (seed.sql's 5
placeholder users plus the 4 real GoTrue users created for this
verification — 1 org_admin analog for the extraction fixture, 1
clinical_reviewer, 1 quality_manager, 1 clinician) were deleted. A final
query confirmed:

```sql
residual_orgs: 0, residual_jobs: 0, residual_runs: 0, residual_reviews: 0,
residual_findings: 0, residual_page_reviews: 0, residual_memberships: 0,
residual_profiles: 0, residual_auth_users: 0
```

Reference/system data (`roles`, `permissions`, including the 9 new
`guideline_extraction_reviews.*`/`guideline_extraction_findings.*`/
`guideline_extraction_source.*` permissions and their role mappings) was
correctly left untouched — only synthetic organizations, users, and
content were removed.

### Vercel Preview

Redeployed with the updated code (review queue, side-by-side review
workspace, the Extraction Summary Card's new "Start technical review" /
"Open review" link) — `vercel inspect` confirmed `status: Ready`,
`target: preview`. The stable alias `noor-preview-dev.vercel.app` was
re-pointed at the new deployment. The unprotected smoke test
(`scripts/smoke-test-web.mjs`, no `BYPASS_TOKEN` available this session)
correctly detected and reported Vercel's Deployment Protection wall for
every body-content check — the same, expected, non-false-passing
behavior observed in every prior session without the bypass token in
hand. Deployment Protection remains **enabled and correctly enforced**,
unchanged.

### CI

Confirmed green on GitHub Actions for the commits accompanying this
document — see the final Sprint 1-D1 closure report for the exact run
reference.
