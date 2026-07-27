# ADR 0011: Extraction Review and Technical Quality Gate

Status: Accepted
Sprint: 1-D1

## Context

Sprint 1-C2 made PDF extraction real and deterministic, but "extraction
execution succeeded" is not the same claim as "extraction quality is fit
for downstream use." `pypdf` can return text for a page whose reading
order is wrong, whose Arabic shaping is broken, whose table structure is
lost, or whose content is entirely absent (image-only page) — and none of
that is visible from `document_extraction_runs.status = 'succeeded'`
alone. Before any future OCR decision, chunking, embedding, or retrieval
work begins, Noor needs a human, auditable, page-aware technical quality
decision that sits between "extraction ran" and "extraction is usable."

## Repository audit (existing patterns considered for reuse)

| Area | Current Pattern | Reusable | Gap | Decision |
|---|---|---|---|---|
| Guideline review (`guideline_reviews`, migration 0005) | Single-round accumulation: any holder of `guidelines.review` inserts an unlimited number of review rows against a `guideline_version`; approval requires ≥1 `recommended_for_approval` row plus a separate lifecycle-transition function | Partially | No reviewer assignment, no "one active round," no page-level granularity | Reuse the **submission-function skeleton** (`assert_permission` → validate target state → lock → insert decision → `record_audit_event`) and the **self-review-blocking trigger** shape; do **not** reuse the unlimited-accumulation model — extraction review needs assignment and one active round per run |
| `document_extraction_runs.status` (migration 0008) | `running/succeeded/failed/invalidated` — execution-only, drives the deterministic-identity partial unique index | No | Must not be overloaded with review decisions (would break the identity/reuse logic) | New, separate `document_extraction_reviews.review_status` column; execution and review state remain two independent state machines (§3 of the mission, enforced structurally) |
| `document_extraction_pages` (migration 0008) | Immutable, `unique(extraction_run_id, page_number)`, `unique(organization_id, id)` | Yes, as FK target | None | Page-level findings and page-review rows FK to `document_extraction_pages(organization_id, id)` |
| Permissions (`apps/web/lib/auth/permissions.ts`) | Flat `PERMISSIONS` const, `dot.separated` keys, grouped by sprint | Yes | New namespace needed | Add `guideline_extraction_reviews.*`, `guideline_extraction_findings.*`, `guideline_extraction_source.*` — deliberately **not** `guideline_extractions.*` (that namespace is execution-read-only; keeping review permissions in their own namespace enforces the architecture boundary from the outside as well as the inside) |
| Signed Storage access | Only `createSignedUploadUrl` exists (write path); no signed-download pattern anywhere | No | Must build fresh | New server action mints a short-lived `createSignedUrl` (read) using the session-bound client (never service-role), after `requirePermission` + explicit organization-match check, mirroring the existing "RLS on `storage.objects` is the real authorization" principle |
| Append-only pattern | Two established styles: GUC-override (`noor.allow_audit_maintenance`, used for `guideline_reviews`/`guideline_lifecycle_events`) and unconditional (`document_extraction_pages`) | Yes | Choose one | Reuse the **GUC-override style** for review/finding/event tables — review decisions are human judgment calls that may occasionally need a documented emergency-maintenance correction, same rationale as `guideline_reviews` |
| `SECURITY DEFINER` grant convention | `revoke all ... from public` inline; `grant execute ... to authenticated` deferred to one guarded `do $$ if exists(...) $$` block at the end of the migration (role doesn't exist at CI migration-apply time) | Yes | The RLS test file must **also** issue its own explicit grants (found as a real CI bug in Sprint 1.2B) | Migration 0009 follows the exact same guarded-grant convention; `009_extraction_review.sql` explicitly grants SELECT and EXECUTE at its own top, not relying on the migration's guarded (locally no-op) grant |
| UI (`app/reviewer/guidelines/`) | Server Component queue page → inline `<form action={serverAction}>` per item → `?error=` redirect convention | Yes | None | New review queue/detail pages under `app/reviewer/extractions/` follow the identical shape |
| Web tests | `tsx`-run, `node:assert/strict`, flat `apps/web/tests/*.test.ts`, chained in `package.json`'s `test` script, no DOM | Yes | None | New test files follow the same naming and chaining convention |

## Decision

### 3.1 Two independent state machines, structurally separated

`document_extraction_runs.status` (execution: `running/succeeded/failed/invalidated`)
and `document_extraction_reviews.review_status` (human quality judgment:
`pending_review/in_review/accepted/accepted_with_warnings/ocr_required/
reprocessing_required/rejected/invalidated`) live in **different tables**.
A review row cannot exist for a run that has never reached `succeeded`,
and an `invalidated` extraction run forces every review's derived
eligibility to `false` regardless of what the review itself says — but
the review's own historical decision text is never mutated by that
invalidation. This makes "extraction execution succeeded ≠ extraction
quality accepted" a database-enforced fact, not a UI convention.

### 3.2 Review rounds, not review edits

Each `document_extraction_reviews` row is one **round**. Only one row per
`extraction_run_id` may be in an active state (`pending_review` or
`in_review`) at a time (partial unique index). A submitted (terminal)
round is immutable — reopening never edits it; reopening inserts a new
round with `review_round = previous + 1` and `reopened_from_review_id`
pointing at the prior round. This mirrors the append-only philosophy
already used for `guideline_lifecycle_events`, applied to the review
record itself rather than a separate event log (an additional append-only
`document_extraction_review_events` table still exists for fine-grained
transition auditing, matching `guideline_lifecycle_events`'s role).

### 3.3 One generalized findings table, not two

Both page-level and document-level findings live in
`document_extraction_review_findings`, with a nullable
`extraction_page_id` (§10.3 of the mission explicitly prefers this if it
stays clear and constrained — a `check` constraint enforces that
document-level finding types are only used with a null page, and
page-level types only with a non-null page, so the taxonomy itself
prevents ambiguity without needing two tables).

### 3.4 Decision rules are database-enforced, not UI-trusted

`submit_document_extraction_review()` is the single, narrow, transactional
entry point for every terminal decision (§28 of the mission). It
re-validates page coverage, open-finding counts by severity, and
decision-specific required fields **inside the function**, under lock,
regardless of what the client believes the state to be. The UI's own
client-side validation exists only for user experience — the database
function is the actual gate.

### 3.5 Eligibility is derived, never stored as an editable flag

`get_document_extraction_review_eligibility()` is a `stable` SQL function
computed from the **latest round's** `review_status` plus the extraction
run's own `status`. There is no `eligible_for_chunking` column anywhere
a client could write to. Chunking eligibility becomes `false` the instant
a round is reopened (the latest round reverts to `pending_review`) or the
extraction run is invalidated, with no separate bookkeeping required.

### 3.6 Self-review: documented V1 policy, not a full quorum system

Unlike `guideline_reviews`' unconditional self-review block, extraction
review's "the uploader/registerer of the source document" is not
necessarily the same trust boundary as "the guideline version's clinical
author." For V1, Noor blocks a reviewer from starting or submitting a
review for a run whose source document they personally uploaded or
registered (`guideline_source_documents.uploaded_by` /
`registered_by`) — the same unconditional-block shape as
`prevent_self_review()` on `guideline_reviews`, not a "unless no one else
is available" exception (that would require a live headcount query at
submission time, adding real complexity for a scenario V1's synthetic
single-reviewer-org test fixtures can't safely exercise anyway). This is
recorded as a known limitation, not silently assumed correct at scale.

## Consequences

* Downstream Sprint 1-D2 (OCR) and 1-D3 (chunking) can query
  `get_document_extraction_review_eligibility()` directly and never need
  to understand review internals.
* A future "human-corrected text" workflow (explicitly out of scope) can
  be added as a wholly separate artifact/table without touching this
  schema, because nothing here ever mutates `normalized_text`,
  `raw_text`, or any checksum.
* The "100% of pages reviewed before any terminal decision" policy (§22
  of the mission) is enforced uniformly across all five terminal
  decisions, including `rejected` — a reviewer who determines the wrong
  document was uploaded on page 1 still must mark every page reviewed
  (even trivially, "not reviewed in detail — document rejected on sight")
  before submitting. This trades some reviewer friction for a single,
  simple, always-true invariant rather than a decision-dependent
  exception matrix; documented as a policy that may be revisited once
  Controlled Beta reviewer feedback exists.
