# Database Schema — Deterministic PDF Extraction (Sprint 1.2B)

Source: `supabase/migrations/0008_deterministic_pdf_extraction.sql`.
Builds directly on `docs/database/document-processing-orchestration-schema.md`'s
patterns — read that first, especially its "output-column shadowing" and
"hardened trust boundary" sections, both directly reused here.

## Tables

| Table | Purpose | Mutability |
|---|---|---|
| `document_extraction_runs` | One row per extraction attempt; provenance-complete | Mutable in place while `running`; provenance/artifact columns frozen forever once `succeeded` (trigger) |
| `document_extraction_pages` | One row per extracted page | Fully immutable from insertion (trigger blocks all UPDATE unconditionally) |

No separate artifact table — see
`docs/domain/document-extraction-artifacts.md`'s "canonical JSON artifact"
section for why.

## Deterministic identity: one partial unique index

```sql
create unique index document_extraction_runs_one_succeeded_per_identity
  on document_extraction_runs (organization_id, source_sha256, pipeline_version, configuration_version, extractor_name, extractor_version)
  where status = 'succeeded';
```

This is the database's own, ultimate guarantee — independent of whatever
application-level reuse logic `create_document_extraction_run()` performs
first. Proven under real concurrency (not just code review):
`supabase/tests/concurrency/verify_concurrent_extraction_identity.sh`
races two genuinely separate OS processes/Postgres backends at the same
identity — regardless of the exact timing outcome (clean reuse, a
genuinely simultaneous double-insert, or one attempt superseding a stale
one), exactly one row ever reaches `succeeded`.

## A real design gap found by actually running the concurrency test

The first version of `finalize_document_extraction_run()` had no
awareness that a *different* `document_extraction_runs` row might win the
race to `succeeded` at the same identity first — its `UPDATE ... SET
status = 'succeeded'` would hit the partial unique index directly and
raise a raw `unique_violation` all the way up to the Worker, which had no
way to distinguish that from a genuine database error. Found immediately
on the first real dual-process run (not by reading the SQL): both workers
legitimately created separate `running` rows (the identity-check inside
`create_document_extraction_run` only locks an *existing* row via `FOR
UPDATE` — there's nothing to lock the first time both callers race in
simultaneously), and the second `finalize` call crashed.

**Fixed** by wrapping the `UPDATE` in a `BEGIN ... EXCEPTION WHEN
unique_violation ...` block: on that specific exception, the losing run is
marked `invalidated` (`error_code = 'superseded_by_concurrent_success'` —
its uploaded artifact is simply orphaned, a bounded, rare, harmless waste,
never an unbounded accumulation) and the function looks up and returns
the *winning* run's id/status instead — the Worker completes its job
exactly as if it had cleanly reused the result from the start.

**A second, related race surfaced immediately after fixing the first**
(again by actually re-running the concurrency script, not by re-reading
the SQL): the claim → create → insert-pages → finalize sequence is
several separate auto-committed `psql`/PostgREST statements, not one
spanning transaction. This opened a window where a job's
`create_document_extraction_run` row could be superseded by a *different*
job's attempt at the same identity (the legitimate "stale attempt"
supersession path, §ADR/lifecycle docs) *after* the first job had already
committed its own `create` call but *before* it reached `finalize`.
`finalize_document_extraction_run` would then find its own run in status
`failed` (`superseded_by_retry`) and raise a raw, generic "not running"
error — not a `unique_violation` this time, so the first fix's exception
handler didn't catch it either. **Fixed** by adding an explicit check for
`status = 'failed' and error_code = 'superseded_by_retry'`: look up
whether the identity already has a `succeeded` run to adopt (the
superseding attempt may have finished by now) and return it if so;
otherwise raise a clear, named, retryable error
("...superseded... before this attempt could finalize") that a real
Worker's error-classification layer maps straightforwardly — never a raw,
unclassified exception. Both fixes were re-verified together: 5
consecutive runs of
`supabase/tests/concurrency/verify_concurrent_extraction_identity.sh`,
naturally exercising all four now-documented race outcomes (clean reuse,
simultaneous-insert/`unique_violation`, supersession-then-winner-found,
and supersession-with-no-winner-yet), zero unexpected errors across all
five.

## A third real bug found via CI, not by reading the SQL: a missing test-file grant

`supabase/tests/rls/008_pdf_extraction.sql`'s TEST 15/15b initially failed
intermittently — passing against a local Docker container that had
already been migrated at least once, but failing deterministically
against a genuinely fresh `postgres:16` container (exactly what GitHub
Actions' `database` job always starts) with a raw `permission denied for
table document_extraction_runs`. Root cause: on CI's plain-Postgres
container the `authenticated` role does not exist until
`001_tenant_isolation.sql` creates it — so migration 0008's own guarded
`grant select ... to authenticated` (section 3) is a documented no-op
there, exactly like the equivalent guarded blocks in migrations 0005 and
0006. Both of those migrations' RLS test files (`003_guideline_registry.sql`,
`005_document_intake.sql`) already carry their own explicit
`grant select on <new tables> to authenticated` near the top, mirroring
what the migration grants on hosted — `008_pdf_extraction.sql` was
written without one. Fixed by adding the same explicit grant for
`document_extraction_runs`/`document_extraction_pages`. Re-verified
against multiple genuinely fresh `postgres:16` containers (not a reused
one) before re-pushing.

## Trust boundary: same hardened pattern as migration 0007, applied from the start

All three new functions (`create_document_extraction_run`,
`finalize_document_extraction_run`, `fail_document_extraction_run`) are
**never granted to `authenticated`/`anon`** — narrow `search_path =
public` (none of them need pgcrypto directly; page/artifact checksums are
computed by the Worker in Python, not by SQL), `revoke all ... from
public`, and an explicit, independently-guarded `revoke execute ... from
authenticated` / `from anon` (local plain Postgres has an `authenticated`
role for RLS-test purposes but no `anon` role at all — each revoke is
guarded by its own `pg_roles` existence check). This is the exact fix
migration 0007 needed only *after* a hosted-only bug was found
(ADR 0009's addendum) — migration 0008 applies it from the start rather
than repeating that discovery. See
`supabase/tests/rls/007_security_hardening_review.sql` (the permanent
regression for the 0007 finding) and 008_pdf_extraction.sql TEST 16 (the
same check for these three new functions).

## Page rows: a direct trusted table write, not a wrapper function

Unlike every other Worker write in this schema,
`document_extraction_pages` rows are inserted via a plain `service_role`
`POST /rest/v1/document_extraction_pages` (`OrchestrationClient.insert_extraction_pages`),
not a `SECURITY DEFINER` RPC function. This is a deliberate simplification,
not an oversight: `service_role` bypasses RLS entirely by default (the
same trust boundary every Worker write already relies on), and the
table's own constraints — `unique (extraction_run_id, page_number)`, the
`page_number >= 1` check, the `extraction_status` enum check, and the
immutability trigger — enforce every correctness property regardless of
*how* a row is inserted. A wrapper function here would only re-state
constraints Postgres already enforces natively, for no additional safety.

## Immutability: two different triggers, deliberately

* `document_extraction_runs`: **conditional** — blocks changes to
  provenance/artifact-identity columns only once `status = 'succeeded'`
  (mirrors `guideline_source_documents`' pattern from migration 0006),
  because the row legitimately mutates in place from `running` to its
  terminal status.
* `document_extraction_pages`: **unconditional** — blocks every `UPDATE`
  from the moment a row exists, full stop. There is no legitimate
  in-place update path for a page ever (a reprocessing attempt creates an
  entirely new extraction run with fresh page rows), so there's no
  conditional logic to write.

Neither trigger blocks `DELETE` (unlike the append-only pattern used for
`audit_events`/`document_intake_events`/`guideline_lifecycle_events`) —
cascade-delete from `organizations`/`document_extraction_runs` works
cleanly for test/hosted-verification cleanup without needing the
`noor.allow_audit_maintenance` override.

## Required indexes

```
document_extraction_runs:  organization_id+source_document_id,
                            organization_id+processing_job_id, status
document_extraction_pages: organization_id+source_document_id,
                            extraction_status, suspected_scanned (partial)
                            unique(extraction_run_id, page_number)
```

## Migration safety

Guarded exactly like 0004–0007: `authenticated`-role grants (the plain
`SELECT` grant, and the guarded revokes above) are wrapped in `if exists
(select 1 from pg_roles where rolname = 'authenticated')` /
`'anon'` checks — a documented no-op at CI plain-Postgres migration-apply
time, real on hosted. Applied to a fresh Postgres 16 container with zero
errors, immediately followed by the pre-existing suite (001–007,
unmodified, still 100% green on top of this migration's schema changes)
and the new extraction suite (008) — see the verification record.
