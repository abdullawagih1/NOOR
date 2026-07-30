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

**Closed in Sprint 1-D2** (was a known, documented gap at the time this
sprint was written): `storage.objects`' RLS policy for
`guideline-originals` was, at the time, organization-scoped rather than
permission-scoped — any active org member who constructed the exact
Storage object path and called Supabase's Storage API directly could, in
principle, mint their own signed URL for a source PDF regardless of
their actual permissions. Migration `0010_permission_scoped_storage_access.sql`
closed this by requiring `guideline_documents.read` at the Storage RLS
layer itself, proven end-to-end against real hosted infrastructure with
real GoTrue JWTs (a clinician denied, permitted roles allowed) — see
`docs/security/ocr-and-storage-authorization.md` and
`docs/verification/sprint-1-d2-controlled-ocr-verification.md`.

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
