# ADR 0008: Secure document intake keeps three lifecycles separate, and computes trust facts server-side, not in SQL

**Status:** Accepted
**Source:** Sprint 1.1 mission — Secure Guideline Source Document Intake and
Idempotent Job Registration

## Decision

Three state machines, three separate concerns, never merged:

1. **Clinical publication lifecycle** (`guideline_versions.lifecycle_status`,
   ADR 0007): draft → ready_for_review → approved → active → superseded →
   withdrawn. Unchanged by this migration.
2. **Upload session lifecycle** (`document_upload_sessions.status`):
   `created → authorized → completed`, with `expired` / `rejected` /
   `cancelled` as terminal failure/control outcomes. Governs whether a
   specific signed-upload authorization is still usable.
3. **Processing job lifecycle** (`document_processing_jobs.status`):
   `queued → claimed → processing → succeeded`, with `failed` /
   `cancelled` / `dead_lettered` as terminal outcomes. This sprint creates
   jobs only up to `queued` — claiming and execution are Sprint 1.2 (S1-C).

A fourth, document-level state also exists
(`guideline_source_documents.status`: `pending_upload → uploaded →
verified → registered`, with `rejected` / `quarantined` as failures) — it
answers "is this file trustworthy," which is a different question from "is
this upload authorization still valid" (the session) or "has this
guideline version been clinically approved" (the publication lifecycle).
Collapsing any of these into one column would let an event in one domain
(e.g. "the signed URL expired") accidentally read as an event in another
(e.g. "the document is untrustworthy") — the same reasoning ADR 0007
already applied between clinical and document-processing concerns, applied
here one level deeper.

## A second decision this ADR makes explicit: where trust facts get computed

Sprint 1's guideline registry (migration 0005) could keep 100% of its write
logic in SQL, because every fact it needed (permissions, lifecycle state,
review records) already lived in Postgres. **Document intake cannot**: file
existence, byte size, the first bytes of content (PDF signature), and a
SHA-256 hash are facts about an object in Supabase Storage, which SQL has
no way to read. Postgres cannot open a file.

So the split is:

* **Postgres (SECURITY DEFINER functions)** remains the sole place that
  *records* a trust decision — atomically, alongside job creation and an
  audit event — and the sole place that enforces permissions, tenant
  ownership, idempotency, and immutability. This mirrors migration 0005's
  pattern exactly.
* **The Next.js server** (never the browser) is the sole place that
  *computes* the trust facts: it independently re-fetches the uploaded
  object from Storage using the same RLS-scoped session that uploaded it
  (no service-role key is needed for this — the existing
  `noor_buckets_select_own_org`/`insert_own_org` policies already let an
  org member read/write their own org's objects), checks the size, checks
  the `%PDF-` signature, and computes SHA-256 over the actual bytes. Only
  then does it call `complete_guideline_upload(...)` with those computed
  values as parameters.

The browser is trusted for nothing beyond "which file did the user pick" —
not its extension, not its claimed MIME type, not any checksum it offers
(an optional `expected_sha256` may be supplied for the user's own
early-mismatch feedback, but it is never authoritative). The database
function does not re-derive the file facts either (it cannot); it trusts
the calling Next.js server process precisely because that process
authenticated as the user AND independently re-read the object from
Storage before asserting anything about it — the same authority boundary
Supabase's own signed-URL model assumes.

## Consequences

* `document_upload_sessions` and `guideline_source_documents` carry two
  related but independently-evolving status columns; application code must
  never assume one implies the other's exact value, only a coarse
  correspondence documented in `docs/domain/document-intake-lifecycle.md`.
* `complete_guideline_upload()` takes `p_detected_media_type`,
  `p_size_bytes`, `p_sha256`, and an optional `p_rejection_reason` as
  **inputs**, not values it computes — a change in shape from migration
  0005's functions, which computed everything from database-visible state
  alone. This is intentional, not a weakening of the "server decides"
  principle: the decision is still made by code the client cannot forge
  (the Next.js server action, itself gated by `requirePermission` and RLS),
  it is just made partly outside SQL because SQL has no filesystem access.
* `document_processing_jobs.job_type` uses `'document_parsing'` — the
  Worker's already-existing `JobOperation` literal
  (`apps/worker/app/main.py`) — rather than the mission's suggested
  `'document_extraction'`, to avoid introducing a second, inconsistent
  name for the same future operation. No live Web→Worker call is added in
  this sprint; the job row is the durable system of record, a queue
  message is only ever a delivery mechanism for it (Sprint 1.2, S1-C).
