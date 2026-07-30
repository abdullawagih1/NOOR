# Controlled Page-Scoped OCR — Database Schema (Sprint 1-D2)

Migration: `supabase/migrations/0011_controlled_page_scoped_ocr.sql`.
Storage hardening: `supabase/migrations/0010_permission_scoped_storage_access.sql`
(see `docs/security/ocr-and-storage-authorization.md`). See ADR 0012 for
the architectural rationale and `docs/domain/ocr-eligibility-and-lifecycle.md`
/ `docs/domain/ocr-page-representations.md` for the domain lifecycle.

## Tables

| Table | Purpose |
|---|---|
| `document_ocr_requests` | One row per OCR request (governance/aggregate state) — groups every eligible page from one extraction-review round, pins provider/renderer/model/config identity for the whole request. |
| `document_ocr_request_pages` | One row per eligible page within a request. `eligibility_source_type` is constrained to exactly `'page_review_ocr_candidate'`, FK'd to the specific `document_extraction_page_reviews` row that authorized it — eligibility can never be client-supplied. |
| `document_ocr_runs` | One row per execution *attempt*/identity. Full pinned identity columns including `page_image_sha256`. A partial unique index (`status = 'succeeded'`) guarantees at most one succeeded run per identity; failed attempts at the same identity are preserved alongside it. |
| `document_ocr_reviews` | One row per human technical-review round. `ocr_required` is deliberately excluded from its status check constraint. |
| `document_ocr_page_reviews` | Per-page review decision, frozen once the parent round is submitted. |
| `document_ocr_findings` | 18-value finding-type taxonomy, 4 severities, append-only (delete requires the `noor.allow_audit_maintenance` override, included from the start this time — see below). |

`document_processing_jobs` is extended with a nullable `ocr_request_page_id`
column and a page-scoped partial unique index
(`document_processing_jobs_one_active_ocr_per_page`), alongside the
existing document-scoped one for `document_parsing` — two different pages
of the same document can have simultaneously-active `document_ocr` jobs;
the same page cannot have two.

## Functions

Client-facing (permission-checked, `SECURITY DEFINER`, `search_path =
public`): `create_document_ocr_request`, `cancel_document_ocr_request`,
`create_document_ocr_review`, `assign_ocr_reviewer`, `claim_ocr_review`,
`start_document_ocr_review`, `mark_ocr_page_reviewed`,
`create_ocr_finding`, `update_ocr_finding_status`,
`submit_document_ocr_review`, `reopen_ocr_review`, `invalidate_ocr_review`.

Worker-only (revoked from `PUBLIC`/`anon`/`authenticated`, callable only
by `postgres`/`service_role`): `create_document_ocr_run`,
`finalize_document_ocr_page`, `fail_document_ocr_run`.

Read-only derivation: `get_document_page_text_readiness`.

Extended via `create or replace` (originally Sprint 1-D1, migration
0009): `get_document_extraction_review_eligibility`,
`submit_document_extraction_review` (now requires ≥1 `ocr_candidate` page
before accepting `ocr_required`), and `reopen_extraction_review` (now
cascades into any active dependent OCR request — see below). Postgres
preserves a function's existing `GRANT EXECUTE` privileges across a
same-signature `CREATE OR REPLACE`, so none of these needed re-granting.

## The two-phase OCR-run creation design

Unlike extraction (whose identity is fully known before any work starts),
an OCR run's identity includes the *rendered page image's* checksum —
something that can only be known after rendering. The Worker therefore:

1. Calls `render_source_page()` (download + revalidate source, render the
   exact page) — no database call yet.
2. Calls `create_document_ocr_run()` with the now-known
   `page_image_sha256`/`page_image_size_bytes` — this is where
   identity-based reuse is detected.
3. Only if step 2 reports a fresh run (`out_reused = false`) does it call
   `recognize_and_build_artifact()` (OCR + artifact upload) and then
   `finalize_document_ocr_page()`.

A real bug was found and fixed while writing this sprint's tests, not by
reading the SQL: the reused branch of `create_document_ocr_run()`
originally returned early without ever marking the request page
`succeeded`. Since the Worker (`app/ocr/processor.py`) deliberately never
calls `finalize_document_ocr_page()` for a reused run (there is nothing
new to finalize), that request page would have stayed `processing`
forever, permanently blocking `create_document_ocr_review()`'s
all-pages-terminal check. Fixed by having the reused branch itself mark
the request page `succeeded` — proven by
`supabase/tests/rls/011_controlled_ocr.sql` TEST 23, which drives an
actual second OCR request to the same identity across two different
review rounds and asserts the new page reaches `succeeded` immediately,
with no `finalize_document_ocr_page()` call in between.

A second, related bug was found in the Worker's own Python: the original
`app/ocr/processor.py` called `create_ocr_run()` *before* rendering,
passing an empty-string placeholder for `page_image_sha256` — meaning
every succeeded run's identity was permanently recorded with an empty
checksum, silently defeating the reuse mechanism for genuinely identical
pages. Fixed by restructuring the processor into the three-phase sequence
above; see `apps/worker/app/ocr/processor.py` and `pipeline.py`.

## Extraction-review-reopen cascade

`reopen_extraction_review()` (migration 0011's `create or replace` of the
0009 function) now cascades: after creating the new round, it looks for
any `document_ocr_requests` row still active
(`status not in ('cancelled', 'invalidated')`) for that extraction run
and, if found, cancels its non-terminal jobs, marks its non-terminal
pages `invalidated`, marks any open `document_ocr_reviews` round
`invalidated`, and marks the request itself `invalidated` with a reason
referencing the reopening. Already-`succeeded`/`failed` pages and runs
are left untouched — proven by TEST 21, which reopens a review whose OCR
request has one succeeded page and confirms the request is invalidated
while the succeeded page's status is unchanged.

`create_document_ocr_run()` independently re-verifies, under lock, that
no later extraction-review round exists for the request before creating
or reusing a run — a second, structural line of defense in case a Worker
call races ahead of the cascade.

## Self-review

`start_document_ocr_review()` blocks whoever uploaded or registered the
underlying source document from starting (i.e. technically reviewing)
its own OCR output — identical in shape to `start_document_extraction_review()`'s
policy (migration 0009), applied one layer deeper. Proven by TEST 24.

## Identity, reuse, and cross-tenant isolation

See ADR 0012 for the full identity tuple. Reuse never crosses
`organization_id` — every lookup and insert is scoped by it. The RLS
suite's TEST 14 confirms a cross-tenant admin cannot even read another
organization's OCR requests, let alone trigger reuse against them.
