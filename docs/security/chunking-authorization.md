# Chunking Authorization

Sprint 1-D3. Mirrors `docs/security/ocr-and-storage-authorization.md`
one layer deeper.

## Two trust boundaries, never conflated

1. **Client-facing functions** (`create_document_chunking_job`,
   `create_document_chunking_review`, `mark_chunk_reviewed`,
   `submit_document_chunking_review`, `get_document_embedding_readiness`,
   etc.) — authenticated via `auth.uid()` and gated by
   `assert_permission(organization_id, 'guideline_chunking.*')`. Granted
   to `authenticated`, revoked from `anon`.
2. **Worker-only functions** (`get_document_chunking_job_context`,
   `create_document_chunking_run`, `finalize_document_chunking_run`,
   `fail_document_chunking_run`) — authenticated via
   `assert_lease_owner()` against a claimed `document_processing_jobs`
   lease, **never** via organization permissions. Explicitly revoked
   from both `authenticated` and `anon`; only reachable via the
   `service_role` credential the Worker holds.

These two boundaries must never be mixed. A Worker-only function calling
a permission-gated one would always fail (service_role's JWT has no
`sub` claim, so `auth.uid()` is `NULL`, so
`has_permission_in_organization` always returns `false`) — this is
exactly the bug `get_document_chunking_job_context` exists to avoid (see
`docs/database/deterministic-chunking-schema.md`). Conversely, a
client-facing function must never accept a lease token as a substitute
for a real permission check.

## Permission model

| Permission | Who (default role mapping) |
|---|---|
| `guideline_chunking.read` | organization_admin, quality_manager, clinical_reviewer, safety_officer, auditor |
| `guideline_chunking.create` | organization_admin, quality_manager |
| `guideline_chunking.read_artifacts` | quality_manager |
| `guideline_chunking.review` | quality_manager, clinical_reviewer |
| `guideline_chunking.submit_review` | quality_manager, clinical_reviewer |
| `guideline_chunking.reopen_review` | organization_admin, quality_manager |
| `guideline_chunking.invalidate` | quality_manager |

`clinician` holds none of these — chunking technical review is a quality/
reviewer-workspace concern, matching extraction and OCR review's own
access model.

## Self-review is blocked

`start_document_chunking_review` rejects a reviewer who uploaded or
registered the source document, exactly like
`start_document_extraction_review`/`start_document_ocr_review` — a
technical reviewer must be independent of who introduced the source
material, even though this is a technical (not clinical) review.

## RLS

Every one of the six chunking-related tables carries a single SELECT
policy gated on `has_permission_in_organization(organization_id,
'guideline_chunking.read')`. All mutation happens through `security
definer` functions — there are no direct table-level INSERT/UPDATE/
DELETE grants for `authenticated`.

## Storage authorization

The `guideline-processed` Storage bucket's read policy (migration 0010,
extended by 0011 for OCR) now also accepts
`guideline_chunking.read_artifacts` as an authorizing permission for
objects under a `.../guideline-chunking/...` path — a reader with only
`guideline_ocr.read_artifacts`, for instance, cannot read a chunking
artifact, and vice versa. Each processing layer's artifacts require
their own specific permission, not a blanket "can read this bucket"
grant.

## No new secrets, no new external calls

Chunking introduces zero new credentials, zero new external API/provider
calls, and zero new attack surface beyond what extraction/OCR already
established — it reads already-accepted text directly from the
database via the Worker's existing service_role connection, and writes
back through the same RPC pattern every other pipeline stage uses.
