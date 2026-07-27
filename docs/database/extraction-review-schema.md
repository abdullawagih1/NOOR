# Extraction Review Database Schema (Sprint 1-D1, migration 0009)

Companion docs: ADR 0011, `docs/domain/extraction-review-lifecycle.md`,
`docs/domain/extraction-quality-findings.md`,
`docs/security/extraction-review-authorization.md`.

## Tables

**`document_extraction_reviews`** — one row per review round. Key
columns: `extraction_run_id` (FK to `document_extraction_runs`),
`review_round`, `review_status` (8-value check constraint spanning both
active and terminal states), `assigned_reviewer_id`/`assigned_by`/
`assigned_at`, `started_by`/`started_at`, `submitted_by`/`submitted_at`,
per-severity finding counts (`critical_finding_count` etc., maintained by
the functions below, never trusted from a client write since there is no
client write path to this table at all), `pages_reviewed`/`total_pages`/
`all_pages_reviewed`, `requires_ocr`/`requires_reprocessing`,
`decision_reason`, `reopened_from_review_id` (self-FK).

A partial unique index —
`(organization_id, extraction_run_id) where review_status in
('pending_review', 'in_review')` — guarantees at most one **active**
round per run at the database level, not just by convention.

**`document_extraction_review_findings`** — one row per finding,
page-level or document-level (see
`docs/domain/extraction-quality-findings.md` for the full taxonomy and
constraint set).

**`document_extraction_page_reviews`** — one row per (review round, page)
pair, `unique(extraction_review_id, page_number)`, explicit reviewer
coverage tracking.

**`document_extraction_review_events`** — append-only transition history,
parallel to `guideline_lifecycle_events`. Reuses the same
`noor.allow_audit_maintenance` override GUC rather than inventing a
second maintenance mechanism.

## Immutability, three different shapes (deliberately, not by accident)

1. **`document_extraction_reviews`** — a submitted (terminal) round is
   frozen, with exactly one legal further transition:
   `accepted`/`accepted_with_warnings` -> `invalidated`. Any other
   attempted change while terminal is rejected by
   `prevent_terminal_extraction_review_mutation()`. This mirrors
   `document_extraction_runs`' own "conditional freeze once terminal"
   trigger style from migration 0008, not the unconditional
   append-only style.
2. **`document_extraction_review_findings`** — core content is frozen
   immediately on insert (an unconditional trigger, no override); only
   resolution fields (`status`, `resolved_by`, `resolved_at`,
   `resolution_note`) may ever change. `DELETE` is blocked too, but —
   unlike the content-freeze trigger — **with** the same
   `noor.allow_audit_maintenance` override GUC every other append-only
   table in this codebase uses. A first version had no such override at
   all, which meant synthetic hosted test data could never be cleaned up
   again; found and fixed the same session (see "A real bug, found via
   hosted cleanup" below).
3. **`document_extraction_review_events`** — the familiar unconditional
   append-only style (`prevent_extraction_review_event_mutation()`),
   identical to `guideline_lifecycle_events`.

`document_extraction_page_reviews` uses a fourth, simpler rule: mutable
freely while the parent review round is still active, frozen the instant
the parent round reaches any terminal status (a lookup trigger, not a
column on the row itself).

## Permissions: a deliberately separate namespace

`guideline_extraction_reviews.*`, `guideline_extraction_findings.*`, and
`guideline_extraction_source.*` are **not** part of migration 0008's
`guideline_extractions.*` namespace. This is intentional (ADR 0011): the
permission model enforces the execution/review architecture boundary
from outside the schema too, not only inside it. Role mapping:

| Role | read | create | assign | review | submit | reopen | findings.create | findings.resolve | source.read |
|---|---|---|---|---|---|---|---|---|---|
| `organization_admin` | ✓ | ✓ | ✓ | | | ✓ | | | ✓ |
| `quality_manager` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `clinical_reviewer` | ✓ | | | ✓ | ✓ | | ✓ | ✓ | ✓ |
| `safety_officer` | ✓ | | | | | | | | |
| `auditor` | ✓ | | | | | | | | |
| `clinician` | | | | | | | | | |

Clinicians hold none of these permissions, by design — RLS structurally
returns zero rows regardless of any UI mistake.

## Functions

All eleven client-facing functions are `security definer`, narrow
`search_path = public`, `revoke all ... from public` immediately after
creation, and granted to `authenticated` only in one guarded block at the
end of the migration (a documented no-op on CI's plain-Postgres
container, exactly like migrations 0005/0006/0008 — see "A real CI bug,
already learned" below):

`create_document_extraction_review`, `assign_extraction_reviewer`,
`claim_extraction_review`, `start_document_extraction_review`,
`mark_extraction_page_reviewed`, `create_extraction_finding`,
`update_extraction_finding_status`, `submit_document_extraction_review`,
`reopen_extraction_review`, `invalidate_extraction_review`,
`get_document_extraction_review_eligibility`.

`submit_document_extraction_review()` is the single, narrow, transactional
entry point for every terminal decision — it locks the review row, then
re-validates page coverage, finding counts by severity, and
decision-specific required fields entirely inside the function. See
`docs/domain/extraction-quality-findings.md` for the exact rule set.

## A real CI bug, already learned (applied proactively here)

Sprint 1.2B found — via an actual CI failure on a genuinely fresh
Postgres container, not by reading the SQL — that `authenticated` does
not exist at CI's migration-apply time (it's created later by
`001_tenant_isolation.sql`), so a migration's own guarded
`grant ... to authenticated` block is a documented no-op there. Migrations
0005 and 0006 already solved this by having their own RLS test files
issue the grant explicitly; migration 0008's test file initially missed
this for two of its tables, breaking CI. `009_extraction_review.sql`
starts from that lesson: its own explicit `grant select` and
`grant execute` statements appear at the very top of the file, verified
against multiple genuinely fresh `postgres:16` containers (not a reused
one) before being trusted.

## A real bug, found via hosted cleanup, not by reading the SQL

The first version of `prevent_extraction_finding_delete()` raised
unconditionally, with no maintenance-override escape hatch at all —
inconsistent with every other append-only table in this codebase
(`audit_events`, `guideline_reviews`, `guideline_lifecycle_events`,
`document_extraction_review_events`), which all honor
`noor.allow_audit_maintenance`. This was only discovered when actually
cleaning up synthetic hosted test data after verification: the cleanup
script's `DELETE FROM document_extraction_review_findings` failed
outright, and there was no way to remove those rows at all — not even as
the connecting superuser. Fixed by adding the same override GUC check
used everywhere else, hotfixed directly on the hosted function
(`CREATE OR REPLACE FUNCTION`, idempotent) so cleanup could proceed
immediately, then corrected in the migration file itself and re-verified
against a fresh local container before being trusted. See
`docs/verification/sprint-1-d1-extraction-review-verification.md`.

## Eligibility as a function, not a column

`get_document_extraction_review_eligibility(extraction_run_id)` is
`security definer stable`, re-checks `guideline_extractions.read`
internally, and computes its three boolean outputs fresh from the latest
review round plus the run's own execution status every call. There is no
`eligible_for_chunking` (or similar) column anywhere a client could write
to — see `docs/domain/extraction-review-lifecycle.md` for the full
truth table.
