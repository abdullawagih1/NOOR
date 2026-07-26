# Sprint 1.1 — Secure Document Intake Verification Record

Every command and result below was actually run — nothing here is inferred
or assumed. Companion docs: `docs/domain/guideline-source-documents.md`,
`docs/domain/document-intake-lifecycle.md`,
`docs/database/secure-document-intake-schema.md`,
`docs/security/document-intake-authorization.md`.

## G-12 regression (mandatory correction, closed this session)

`supabase/tests/rls/004_g12_self_approval_regression.sql` — a synthetic
role combining `guidelines.create` + `guidelines.submit_for_review` +
`guidelines.approve` on one user, who authors a guideline version, gets a
legitimate recommending review from a different user, then attempts to
approve their own version:

```
NOTICE:  G12 PASSED: self-approval request denied (self-approval is not permitted: the version author cannot approve their own version)
NOTICE:  G12b PASSED: lifecycle_status unchanged (ready_for_review)
NOTICE:  G12c PASSED: no approval lifecycle event was created
NOTICE:  G12d PASSED: no audit event falsely claims approval
ALL G-12 REGRESSION TESTS PASSED
```

Run against plain Postgres 16 (below) and hosted Development (§ Hosted
Verification). **G-12 is closed.**

## Local web verification

```
npm run lint --workspace=apps/web        → clean
npm run typecheck --workspace=apps/web   → clean
npm run test --workspace=apps/web        → 63/63 assertions passed
npm run build --workspace=apps/web       → succeeded, 18 routes generated
                                            (guideline detail route grew to
                                            80.6 kB First Load JS — the new
                                            client-side UploadPanel bundle)
```

Three new test suites this sprint: `tests/documents-schemas.test.ts` (14
assertions), `tests/documents-errors.test.ts` (7 assertions),
`tests/documents-config.test.ts` (1 assertion — confirms
`MAX_UPLOAD_SIZE_BYTES` in `apps/web/lib/documents/config.ts` matches the
byte value hardcoded in migration 0006). `tests/permissions.test.ts`
extended with an 8-permission document-intake role-mapping check.

## Local database verification — real Postgres 16

A real `postgres:16` Docker container (matching CI's `database` job
exactly) had all 6 migrations, seed data, and the full RLS test suite
applied and run:

```
$ for f in supabase/migrations/*.sql; do psql ... -f "$f"; done
→ 0001-0006 all applied with zero errors

$ psql ... -f supabase/seed.sql   → applied cleanly

$ for f in supabase/tests/rls/*.sql; do psql ... -f "$f"; done
→ 001_tenant_isolation.sql:            7/7  PASSED
→ 002_auth_hardening.sql:              4/4  PASSED
→ 003_guideline_registry.sql:         26/26 PASSED
→ 004_g12_self_approval_regression.sql: 4/4 PASSED
→ 005_document_intake.sql:            19/19 PASSED
```

**Two real bugs were found and fixed by actually running migration 0006**,
not by reading the SQL — see `docs/database/secure-document-intake-schema.md`
for the technical detail: both `create_guideline_upload_session()` and
`complete_guideline_upload()` use `RETURNS TABLE`, which creates an
implicit PL/pgSQL variable per output column; two of those column names
(`status`, `source_document_id`) collided with real table columns
referenced later in the same function body, producing `column reference
"..." is ambiguous` only at execution time. Fixed by table-qualifying the
two ambiguous references. Also hit, a third time, the same psql `:'var'`
substitution-inside-`DO $$...$$` limitation documented in Sprint 1's
verification record — the fixture-passing helpers (`test_fixture_set`/`fx`)
were reused directly rather than re-discovering the same bug.

### Document intake test coverage (005_document_intake.sql)

| # | Assertion | Result |
|---|---|---|
| 1 | Upload session created and authorized for an eligible (draft) version | PASS |
| 2 | Active (released) version rejects a new source upload | PASS |
| 3 | Cross-tenant upload-session creation denied | PASS |
| 4 | Replayed idempotency_key returns the existing session | PASS |
| 5 | One active primary source per version enforced at session creation | PASS |
| 6 | Completion verifies, registers, and creates a queued processing job | PASS |
| 7 | Repeated completion is idempotent (no duplicate job) | PASS |
| 8 | Cross-version, same-organization duplicate allowed and explicitly recorded | PASS |
| 9 / 9b | Clinician cannot read any intake record / a permitted role can | PASS |
| 10 / 10b | Suspended / removed membership denied | PASS |
| 11 | Registered document's file identity is immutable via raw UPDATE | PASS |
| 12 | Quarantine cascades to cancel the active processing job | PASS |
| 13 | A new upload session is allowed after the prior primary was quarantined | PASS |
| 14 | `cancel_upload_session` cancels the session and rejects the pending document | PASS |
| 15 | Unauthorized (clinician) job cancellation denied | PASS |
| 16 | `document_intake_events` UPDATE blocked without the maintenance override | PASS |
| 17 | `audit_events` recorded across the intake flow | PASS |

## Other workspaces (unaffected — re-verified, not assumed)

```
npm run typecheck --workspace=packages/clinical-schemas → clean
npm test --workspace=packages/clinical-schemas          → 6/6 passed
npm run typecheck --workspace=packages/ui                → clean
python -m pytest tests/ -q (apps/worker)                  → 9/9 passed
python -m compileall app (apps/worker)                     → clean
```

## Hosted Development verification

### Migration applied

```
$ supabase migration list --linked   (before)
→ 0001-0005 local==remote; 0006 local only, remote empty

$ supabase db push --linked --yes
→ Applying migration 0006_secure_guideline_document_intake.sql...
→ Finished supabase db push.

$ supabase migration list --linked   (after)
→ 0001-0006 all local==remote
```

### Real end-to-end flow — 16/16 hosted checks passed

Unlike Sprint 1's registry-only hosted verification, this flow exercises
**real Supabase Storage I/O**, not only PostgREST RPCs: a synthetic
`%PDF-`-signed fixture file was actually uploaded to the private
`guideline-originals` bucket via a real RLS-authorized (not service-role)
request, then independently re-downloaded, hashed, and verified — the
exact sequence `apps/web/lib/documents/actions.ts` performs.

```
PASS  fixture: domain/authority/guideline/draft version created
PASS  admin creates a real upload session
PASS  real object uploaded to private Storage via RLS-authorized session
PASS  uploaded object can be independently re-downloaded (same RLS)
PASS  downloaded bytes match what was uploaded and have a valid PDF signature
PASS  upload completes: verified, registered, job queued
PASS  queued job has job_type=document_parsing, status=queued
PASS  repeated completion is idempotent (same job, no duplicate)
PASS  clinician cannot read the source document (RLS)
PASS  cross-tenant upload-session creation denied
PASS  cross-version same-org duplicate registered (allowed)
PASS  duplicate explicitly recorded
PASS  quality quarantines the document
PASS  quarantine cascaded to cancel the active job
PASS  G-12: creator holding guidelines.approve still cannot self-approve (hosted)
PASS  G-12: lifecycle_status unchanged after denied self-approval (hosted)

ALL HOSTED DOCUMENT INTAKE + G-12 CHECKS PASSED
```

### G-12 regression — closed on hosted too

The same synthetic combined-permission role used in the Docker regression
(`004_g12_self_approval_regression.sql`) was recreated on hosted (real
`roles`/`role_permissions` rows, cleaned up afterward — see below), and
the identical scenario was run entirely over real HTTP with a real GoTrue
JWT: creator authors and submits a version, a different real user
(`reviewer` role) submits a recommending review, then the creator — who
genuinely holds `guidelines.approve` on hosted — attempts to approve their
own version. **Denied**, with the self-approval message, and
`lifecycle_status` confirmed unchanged via a direct hosted query
afterward. **G-12 is closed on both plain Postgres 16 and hosted
Development with real JWTs.**

### Synthetic test data and Storage object cleanup — confirmed

Both uploaded Storage objects were removed
(`storage.remove`/prefixes delete), all database rows (documents,
sessions, jobs, intake events, lifecycle events, reviews, versions,
guidelines, authorities, domains, audit events, memberships, both test
organizations) were deleted (lifecycle/intake events required the
documented `noor.allow_audit_maintenance` override, being append-only),
both test auth users were deleted, and — because this test recreated the
G-12 synthetic role directly on the shared hosted `roles` table — that
role and its `role_permissions` mappings were also explicitly deleted. A
final query confirmed zero residual organizations, zero residual source
documents, zero residual test users, and zero residual G-12 test role:
**PASS — all synthetic hosted test data (including the G-12 test role and
Storage objects) confirmed deleted.**

### Vercel Preview

Redeployed with the updated code (new upload/document-intake application
layer and UI) — `vercel inspect` confirmed `target: preview`,
`status: Ready`. The stable alias `noor-preview-dev.vercel.app` was
re-pointed at the new deployment. Deployment Protection re-confirmed
**enabled and correctly enforced** after the redeploy — the unprotected
smoke test correctly detected and reported the protection wall on every
content check rather than false-passing, unchanged from Sprint 1 (no
Deployment Protection configuration changed this session).

### CI

Confirmed green on GitHub Actions for the commit accompanying this
document — see the final Sprint 1.1 closure report for the exact run URL.
