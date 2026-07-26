# Database Schema — Secure Guideline Document Intake (Sprint 1.1)

Source: `supabase/migrations/0006_secure_guideline_document_intake.sql`.
Builds directly on `docs/database/guideline-registry-schema.md`'s patterns
— read that first; this document only covers what's new or different.

## Tables

| Table | Purpose | RLS |
|---|---|---|
| `guideline_source_documents` | File record for a guideline version | Enabled — `guideline_documents.read`; write only via functions; immutable once verified/registered (trigger) |
| `document_upload_sessions` | Authorizes one upload attempt to a server-generated path | Enabled — `guideline_documents.read`; write only via functions |
| `document_processing_jobs` | Durable system of record for future processing (queued only this sprint) | Enabled — `guideline_processing_jobs.read`; write only via functions |
| `document_processing_attempts` | Retry/recovery foundation, stays empty | Enabled — `guideline_processing_jobs.read`; no write path exists at all yet |
| `document_intake_events` | Append-only intake history, integrates with `audit_events` | Enabled — `guideline_documents.read` or `audit.read`; append-only |

## What's genuinely new compared to migration 0005's pattern

Migration 0005 (guideline registry) could keep 100% of its logic in SQL —
every fact it needed already lived in Postgres. This migration cannot:
file existence, size, the first bytes of content, and a SHA-256 hash are
facts about a Supabase Storage object, which SQL has no way to read. See
**ADR 0008** for the full reasoning; in short:

* `create_guideline_upload_session()` remains pure SQL (permission,
  eligibility, one-primary-per-version, path generation, idempotency) —
  no different from 0005's functions.
* `complete_guideline_upload()` takes `p_detected_media_type`,
  `p_size_bytes`, `p_sha256` as **inputs**, computed by the calling
  Next.js server (which independently re-downloaded the object from
  Storage before calling this function — never trusting the browser). The
  function is still the sole place the *decision* is atomically recorded
  alongside job creation and an audit event.

## A real bug found by actually running this migration, twice

Both `create_guideline_upload_session()` and `complete_guideline_upload()`
use `RETURNS TABLE (...)`, which creates an implicit PL/pgSQL variable for
each named output column, scoped to the whole function body. Two of those
output column names (`status` in the first function, `source_document_id`
in the second) collided with real table column names used later in the
same function's `WHERE` clauses, producing `column reference "..." is
ambiguous` at runtime — not a syntax error, so it wasn't caught until the
function was actually **executed** against a real Postgres instance
(`supabase/tests/rls/005_document_intake.sql`), not merely applied.
Fixed by table-qualifying the two ambiguous references
(`guideline_source_documents.status`, `document_processing_jobs.source_document_id`).
Documented here because the same class of bug can recur in any future
`RETURNS TABLE` function whose output column names happen to match a
column queried inside the body — worth an explicit review step, not just
"the migration applied cleanly."

## Design decision: one active job per document+type is a database guarantee

```sql
create unique index document_processing_jobs_one_active_per_document_type
  on document_processing_jobs (source_document_id, job_type)
  where status in ('queued', 'claimed', 'processing');
```

Combined with `unique (organization_id, idempotency_key)` and
`complete_guideline_upload()`'s `ON CONFLICT ... DO UPDATE ... RETURNING`
upsert (keyed on `idempotency_key = 'intake:' || document_id`), job
creation is idempotent two ways at once: replaying the whole completion
call returns the same job via the session-terminal-state short-circuit,
and even a direct retry of just the job insert would collide on the
idempotency key rather than create a duplicate.

## Design decision: immutability via BEFORE UPDATE trigger, keyed on OLD.status

Unlike `guideline_versions` (migration 0005), which achieves immutability
by having *no* RLS UPDATE policy at all once released,
`guideline_source_documents` legitimately needs in-place `UPDATE`s for the
`pending_upload → verified/rejected` transition itself (all mediated
through `complete_guideline_upload()`, which runs as the function owner
and bypasses RLS). So immutability here is enforced by a trigger
(`prevent_verified_source_document_mutation`) that inspects `OLD.status`:
if it was already `verified` or `registered`, changing the file-identity
columns (`sha256`, `storage_path`, `storage_bucket`, `detected_media_type`)
raises — but the *first* transition into `verified`/`registered` (where
`OLD.status` is still `pending_upload`) is unaffected. This fires for
every role, including the function owner, matching the same
defense-in-depth philosophy as `audit_events`' trigger (0002).

## Migration safety

Guarded exactly like 0004/0005: `authenticated`-role grants and function
EXECUTE grants are wrapped in `if exists (select 1 from pg_roles where
rolname = 'authenticated')`, a documented no-op at CI plain-Postgres
migration-apply time, real on hosted. Verified for real: all statements
applied to a fresh Postgres 16 container with zero errors, immediately
followed by the full RLS/idempotency test suite (see
`docs/verification/sprint-1.1-document-intake-verification.md`).
