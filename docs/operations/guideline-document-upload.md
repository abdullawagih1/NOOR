# Operations — Guideline Document Upload

Practical guide to the secure document intake flow (Sprint 1.1). See
`docs/domain/{guideline-source-documents,document-intake-lifecycle}.md` for
the domain model, `docs/security/document-intake-authorization.md` for the
security model.

## Prerequisites

* A guideline version in `draft`, `ready_for_review`, or `approved` status
  with no existing non-rejected primary source document.
* The signed-in user holds `guideline_documents.upload`
  (`organization_admin` or `knowledge_manager` by default).
* The hosted/local Supabase project has the `guideline-originals` Storage
  bucket (created by migration `0003_storage_foundation.sql`).

## Using the UI

1. Open the guideline's detail page (`/knowledge/guidelines/[guidelineId]`).
2. Scroll to the version's **Source Documents** section.
3. If eligible, an upload panel is shown — select a `.pdf` file (≤ 50 MB).
4. The panel shows `Uploading…` then `Verifying…`; on success it reports
   `Registered` and the page refreshes to show the new document row and
   its queued processing job.

## What actually happens (for debugging)

```
1. Browser calls createGuidelineUploadSessionAction(...)
   -> RPC create_guideline_upload_session (creates DB rows, generates path)
   -> storage.createSignedUploadUrl(path) (same session-bound client)
2. Browser calls storage.uploadToSignedUrl(path, token, file)
   -> direct browser-to-Storage PUT, authorized by noor_buckets_insert_own_org RLS
3. Browser calls completeGuidelineUploadAction(sessionId)
   -> server downloads the object back (storage.download, same session client)
   -> server checks size, PDF signature (%PDF-), computes SHA-256
   -> RPC complete_guideline_upload (records the decision, registers, queues a job)
```

No step uses the Supabase service-role key. No step lets the browser
assert size/type/checksum as authoritative — see ADR 0008.

## Verifying manually against a running server

```bash
# Requires an authenticated session (cookie) — easiest via the browser,
# or by scripting a real sign-in first (see scripts/smoke-test-web.mjs for
# the pattern used elsewhere in this repo).
```

There is no separate curl-only smoke script for this flow yet (unlike
`scripts/smoke-test-web.mjs` for route protection) — real verification for
this feature is the RLS/idempotency SQL suite
(`supabase/tests/rls/005_document_intake.sql`) plus the hosted real-JWT
script used during this sprint's hosted verification (see
`docs/verification/sprint-1.1-document-intake-verification.md`), not a
reusable repository script. Consider adding one if this flow needs regular
manual QA.

## Known operational limits

* **File support**: `.pdf` / `application/pdf` only. No DOCX, HTML,
  images, or scanned-image archives.
* **Size limit**: 50 MB (`MAX_UPLOAD_SIZE_BYTES`,
  `apps/web/lib/documents/config.ts`; mirrored in migration 0006 — see
  `docs/database/secure-document-intake-schema.md`).
* **Upload session TTL**: 30 minutes
  (`UPLOAD_SESSION_TTL_MINUTES`). A session used after this expires is
  rejected and the document marked `rejected` with reason `upload session
  expired` — start a new upload.
* **No malware scanning** — PDF signature validation only. Do not upload
  real, sensitive, or unvetted documents to any environment before a
  scanning provider is integrated.
* **No processing yet** — a queued `document_processing_jobs` row is
  created but nothing claims or executes it (Sprint 1.2, S1-C).
