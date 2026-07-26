# Sprint 1 — Guideline Registry Verification Record

Every command and result below was actually run — nothing here is inferred
or assumed. Companion docs: `docs/domain/guideline-registry.md`,
`docs/domain/guideline-lifecycle.md`,
`docs/database/guideline-registry-schema.md`,
`docs/security/guideline-registry-authorization.md`.

## Local web verification

```
npm run lint --workspace=apps/web        → clean, no warnings/errors
npm run typecheck --workspace=apps/web   → clean
npm run test --workspace=apps/web        → 34/34 assertions passed
npm run build --workspace=apps/web       → succeeded, 18 routes generated
                                            (5 new: /knowledge/guidelines,
                                            /knowledge/guidelines/new,
                                            /knowledge/guidelines/[guidelineId],
                                            /reviewer/guidelines,
                                            /clinician/knowledge — all
                                            correctly force-dynamic)
```

`npm run test --workspace=apps/web` includes two new suites this sprint:
`tests/guidelines-schemas.test.ts` (13 assertions — Zod validation:
required fields, date-ordering refinements, reason-required transitions)
and `tests/guidelines-errors.test.ts` (8 assertions — Postgres error →
safe user-facing message mapping, confirming raw constraint/column names
never leak into what a client sees). `tests/permissions.test.ts` was
extended to scan every `supabase/migrations/*.sql` file (previously
hardcoded to migration 0002 only), since permissions now legitimately span
0002 and 0005 — and to assert every new guideline permission is mapped to
at least one role.

## Local database verification — real Postgres 16, not assumed

A real `postgres:16` Docker container (matching CI's `database` job image
exactly) was created, and every step CI performs was run against it
directly:

```
$ docker run -d --name noor_test_pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=noor_test -p 55432:5432 postgres:16

$ for f in supabase/migrations/*.sql; do psql ... -f "$f"; done
→ 0001, 0002, 0003, 0004, 0005 all applied with zero errors

$ psql ... -f supabase/seed.sql
→ applied cleanly

$ for f in supabase/tests/rls/*.sql; do psql ... -f "$f"; done
→ 001_tenant_isolation.sql:    7/7  PASSED
→ 002_auth_hardening.sql:      4/4  PASSED
→ 003_guideline_registry.sql: 26/26 PASSED (TEST 1 through TEST 21c,
                                             including 1b/5b/6b/12b/18b)

ALL RLS TESTS PASSED / ALL AUTH HARDENING TESTS PASSED /
ALL GUIDELINE REGISTRY TESTS PASSED
```

**A real bug was found and fixed by actually running this**, not just by
writing the SQL and assuming it would work: the first draft of
`003_guideline_registry.sql` used psql's `\gset`/`:'var'` substitution to
thread fixture UUIDs (domain/guideline/version IDs) between statements.
That works for plain top-level SQL but **psql does not perform `:'var'`
substitution inside dollar-quoted (`$$ ... $$`) PL/pgSQL bodies** — which is
where nearly every assertion in the file lives — so the first run failed
with a literal `syntax error at or near ":"` the moment a `DO $$ ... $$`
block tried to reference a fixture ID. Fixed by threading fixture IDs
through a session-scoped temporary table plus two small `SECURITY DEFINER`
SQL helper functions (`test_fixture_set`/`fx`), which work identically
inside and outside `DO` blocks. Re-run from a freshly recreated database
after the fix: 26/26 passed.

### Guideline registry test coverage (003_guideline_registry.sql)

| # | Assertion | Result |
|---|---|---|
| 1 | Duplicate `internal_code` per organization rejected | PASS |
| 2 | Duplicate `version_label` per guideline rejected | PASS |
| 3 | `effective_date` before `publication_date` rejected | PASS |
| 4 | Cross-tenant guideline creation denied | PASS |
| 5 / 5b | Clinician cannot see a draft version / `read_all` role can | PASS |
| 6 / 6b | `draft → active` rejected; rejected transition leaves no partial write | PASS |
| 7 | `draft → ready_for_review` succeeds | PASS |
| 8 | Non-reviewer cannot submit a review | PASS |
| 9 | Legitimate (non-creator) reviewer records a recommending review | PASS |
| 10 | Non-approver cannot approve | PASS |
| 11 | Approval without a recommending review fails | PASS |
| 12 / 12b | Non-creator approver: `ready_for_review → approved → active`; `guidelines.current_active_version_id` updates | PASS |
| 13 | Clinician sees the version once active | PASS |
| 14 | Raw client UPDATE against an active version rejected (immutability) | PASS |
| 15 | Activating a second version transactionally supersedes the first; exactly one active version | PASS |
| 16 | Self-supersession rejected (check constraint) | PASS |
| 17 | Cross-guideline supersession rejected (composite foreign key) | PASS |
| 18 / 18b | Withdrawal without a reason rejected; withdrawal with a reason clears `current_active_version_id` | PASS |
| 19 | `guideline_lifecycle_events` UPDATE blocked without the maintenance override | PASS |
| 20 | `audit_events` recorded for a full lifecycle sequence (6 rows for one version) | PASS |
| 21 / 21b / 21c | Suspended / removed / anonymous denied read access | PASS |

**Known, honest gap in test coverage:** self-approval-by-a-creator-who-also-
holds-`guidelines.approve` is blocked by explicit code
(`transition_guideline_version` checks `auth.uid() <> created_by`
independent of the reviewer/approver role split) but this exact combination
isn't exercised end-to-end by the seeded fixtures — no seeded test user
both authors content and holds `guidelines.approve`. Verified by code
review, not a live assertion. See
`docs/security/guideline-registry-authorization.md`.

## Other workspaces (unaffected — re-verified, not assumed)

```
npm run typecheck --workspace=packages/clinical-schemas → clean
npm test --workspace=packages/clinical-schemas          → 6/6 passed
npm run typecheck --workspace=packages/ui                → clean
python -m pytest tests/ -q (apps/worker)                  → 9/9 passed
```

## Hosted Development verification

### Migration applied

```
$ supabase migration list --linked   (before)
→ 0001-0004 local==remote; 0005 local only, remote empty

$ supabase db push --linked --yes
→ Applying migration 0005_guideline_registry_and_lifecycle.sql...
→ Finished supabase db push.

$ supabase migration list --linked   (after)
→ 0001-0005 all local==remote
```

### Schema landed correctly (Management API, direct query)

| Check | Result |
|---|---|
| All 6 new tables exist with `rowsecurity = true` | ✅ (`clinical_domains`, `guideline_authorities`, `guidelines`, `guideline_versions`, `guideline_reviews`, `guideline_lifecycle_events`) |
| 12 guideline-registry permissions seeded | ✅ |
| 24 role↔permission mappings seeded | ✅ |
| All 10 SECURITY DEFINER functions exist | ✅ (spot-checked 6 by name) |
| `guideline_versions_one_active_per_guideline` partial unique index exists | ✅ |
| `authenticated` has SELECT but not INSERT on `guideline_versions` | ✅ (`has_table_privilege` confirms `select=true`, `insert=false`) |

### Real GoTrue-JWT hosted verification — 18/18 passed

A synthetic organization + 4 real GoTrue users (admin/clinician/reviewer/
quality, `noor-hosted-test+sprint1-*@example.test`) were created via the
Auth Admin API, signed in for real access tokens, and exercised entirely
over HTTP (`/rest/v1/rpc/*` and `/rest/v1/guideline_versions`) — the same
interface the deployed app itself uses, not a superuser SQL shortcut:

```
PASS  admin creates a clinical domain
PASS  admin creates a guideline authority
PASS  admin creates a guideline
PASS  admin creates a draft guideline version
PASS  clinician cannot read the draft version
PASS  draft -> active is rejected
PASS  draft -> ready_for_review succeeds
PASS  approval without a recommending review is rejected
PASS  reviewer submits a recommending review
PASS  creator cannot approve (lacks guidelines.approve; self-approval also blocked)
PASS  quality (non-creator) approves the version
PASS  quality activates the version
PASS  clinician can now read the active version
PASS  raw PATCH against the active version is rejected
PASS  withdrawal without a reason is rejected
PASS  withdrawal with a reason succeeds
PASS  audit_events recorded for this version's lifecycle
PASS  cross-tenant guideline creation denied

ALL HOSTED GUIDELINE REGISTRY CHECKS PASSED
```

### Synthetic test data cleanup — confirmed, not assumed

All lifecycle events (via the documented `noor.allow_audit_maintenance`
override, required since they're append-only), reviews, versions,
guidelines, authorities, domains, audit events, memberships, and both test
organizations were deleted; both auth users' identities cascade-deleted
their profiles/memberships. A final zero-count query across
`organizations`, `guidelines`, and `auth.users` (matching the test email
pattern) confirmed: **PASS — all synthetic hosted test data confirmed
deleted.**

### Vercel Preview

Redeployed with the updated code (new `/knowledge/guidelines*`,
`/reviewer/guidelines`, `/clinician/knowledge` routes) —
`vercel inspect` confirmed `target: preview`, `status: Ready`. The stable
alias `noor-preview-dev.vercel.app` was re-pointed at the new deployment.
Deployment Protection was re-confirmed **enabled and correctly enforced**
after the redeploy: `BASE_URL=https://noor-preview-dev.vercel.app node
scripts/smoke-test-web.mjs` (no bypass token) correctly detected and
reported the protection wall on every content check rather than
false-passing — the same, expected, already-verified behavior from Sprint
0.5, unaffected by this session's changes. A full authenticated
(`BYPASS_TOKEN`-backed) re-run remains available on request but wasn't
required here: no Deployment Protection configuration changed this
session, and the smoke script's fixed route list doesn't cover the new
guideline-registry pages (those are exercised directly above, over real
HTTP, against the hosted database).

### CI

Confirmed green on GitHub Actions for the commit accompanying this
document — see the final Sprint 1 closure report for the exact run URL.
