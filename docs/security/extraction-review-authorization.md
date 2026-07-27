# Extraction Review Authorization (Sprint 1-D1)

Companion docs: ADR 0011, `docs/database/extraction-review-schema.md`,
`docs/security/pdf-extraction-security.md` (the execution-side security
model this sprint builds on top of, unchanged).

## Trust boundary

Every write to the four new tables goes through one of eleven
`SECURITY DEFINER` functions — there is no `INSERT`/`UPDATE`/`DELETE` RLS
policy for `authenticated` on any of them. Each function calls
`assert_permission()` explicitly at its own entry point rather than
relying solely on a table-level policy, matching the established pattern
from migrations 0005–0008.

## RLS

All four tables (`document_extraction_reviews`,
`document_extraction_review_findings`, `document_extraction_page_reviews`,
`document_extraction_review_events`) carry a single `SELECT` policy each,
gated on `has_permission_in_organization(organization_id,
'guideline_extraction_reviews.read')`. A clinician holds none of the
extraction-review permissions by design, so RLS returns zero rows to a
clinician session regardless of any UI mistake — proven directly (real
role-switch, not just "no button shown") in
`supabase/tests/rls/009_extraction_review.sql` TEST 33 and confirmed
again with a real hosted GoTrue JWT.

## Self-review

`start_document_extraction_review()` blocks a reviewer from starting (and
therefore ever submitting) a review of an extraction whose source
document they personally uploaded or registered
(`guideline_source_documents.uploaded_by` / `registered_by`). This is an
unconditional block, the same shape as `guideline_reviews`' own
`prevent_self_review()` trigger — **not** a "unless no other reviewer is
available" exception. See `KNOWN_LIMITATIONS.md` for what that means in
practice for a small organization.

## Assignment integrity

`assign_extraction_reviewer()` verifies the target user actually holds
`guideline_extraction_reviews.review` in the same organization before
assigning them — you cannot assign a clinician (or anyone outside the
organization) as a reviewer, even by direct RPC call bypassing the UI.

## Signed source PDF access

`createExtractionReviewSourceAccessAction()` (application layer, not a
database function) is the only path to the original PDF from the review
workspace:

1. `requirePermission(GUIDELINE_EXTRACTION_SOURCE_READ)` — the first gate;
   a clinician has no path to this action at all.
2. Loads the extraction run and source document server-side and checks
   `organization_id` matches the caller's own organization explicitly
   (belt-and-braces on top of RLS).
3. Mints a short-lived (5 minute) `createSignedUrl()` using **this
   session's own client** — no service-role key anywhere in this path,
   matching the same principle the Sprint 1.1 upload flow already
   established.
4. The signed URL is returned directly to the browser for the PDF
   `<iframe>` panel and is never logged or persisted anywhere.

**A known, pre-existing limitation carried forward, not introduced by
this sprint**: `storage.objects`' RLS policy (migration 0003) authorizes
read access to any object under the caller's own organization's path
prefix — it is organization-scoped, not permission-scoped. This means a
clinician's own real session, if they constructed the exact Storage
object path themselves and called the Supabase Storage API directly
(bypassing Noor's own UI and server actions entirely), could still mint
their own signed URL for a source PDF in their organization. This has
been true since Sprint 1.1's document intake flow and is not something
this sprint's `requirePermission` gate can close from the application
layer alone — it would require tightening `storage.objects` RLS itself,
which is out of this sprint's scope (see `KNOWN_LIMITATIONS.md`).
Noor's own UI and server actions never grant this access to a clinician;
what a clinician could do by hand-crafting raw Storage API calls is a
documented gap, not a silent one.

## Audit and events

Every mutating function writes to both
`document_extraction_review_events` (fine-grained, review-scoped) and the
global `audit_events` table (via `record_audit_event()`), matching the
`guideline_lifecycle_events` + `audit_events` dual-write pattern. Neither
ever stores page text — only IDs, statuses, finding types/severities, and
reasons. Routine page navigation (opening a page to look at it) is never
audited; only the explicit `mark_extraction_page_reviewed()` action is
(mission §44's own distinction between a substantive action and harmless
navigation).

## Explicit non-goals of this sprint's security model

- No new Storage bucket or per-object ACL was introduced.
- No rate limiting was added to the signed-URL-minting action beyond the
  existing per-request permission check.
- No protection against a reviewer taking a screenshot or otherwise
  exporting the source PDF once legitimately viewing it — this is a
  process/policy concern, not a technical control this sprint implements.
