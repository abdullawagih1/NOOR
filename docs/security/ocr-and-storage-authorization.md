# OCR and Permission-Scoped Storage Authorization (Sprint 1-D2)

Companion docs: ADR 0012, `docs/database/controlled-ocr-schema.md`,
`docs/security/extraction-review-authorization.md` (the sprint before
this one, which first documented the Storage gap this sprint closes).

## Storage hardening (migration 0010) — closing a documented residual risk

Sprint 1-D1 documented, in
`docs/security/extraction-review-authorization.md`, that
`storage.objects` RLS was organization-scoped, not permission-scoped: any
member of an organization could, by hand-constructing the exact object
path and calling the Supabase Storage API directly (bypassing Noor's own
UI/server actions), mint a signed URL for any object under that
organization's prefix — including a clinician reading a source PDF or
processed artifact they hold no application-level permission to see.

Migration 0010 closes this for the two buckets that matter most
(`guideline-originals`, `guideline-processed`):

- **`guideline-originals` (source PDFs)**: `SELECT` now requires
  `has_permission_in_organization(org_id, 'guideline_documents.read')`,
  not mere organization membership. `INSERT` requires
  `guideline_documents.upload`, matching the existing upload-session
  ownership check the application layer already enforced.
- **`guideline-processed` (extraction *and* OCR artifacts)**: `SELECT`
  requires **either** `guideline_extractions.read_artifacts` **or**
  `guideline_ocr.read_artifacts`. There is deliberately no `authenticated`
  `INSERT` policy at all — only `service_role` (which bypasses RLS)
  writes here; a browser session can never upload directly into this
  bucket regardless of permissions held.

A clinician holds none of `guideline_documents.read`,
`guideline_extractions.read_artifacts`, or `guideline_ocr.read_artifacts`
by design (see the permission grant tables in migrations 0006/0011) — so
the exact bypass Sprint 1-D1 documented as open is now closed at the
Storage layer itself, not only at the application layer minting signed
URLs. `evaluation-assets` / `generated-reports` / `temporary-uploads`
were deliberately left on the prior organization-scoped-only policy —
none of them hold guideline source content yet, and permission-scoping
them is not required by this sprint's mission.

**Local test coverage**: migration 0010 has no dedicated
`supabase/tests/rls/*.sql` file, matching migration 0003's own
established precedent — the `storage` schema does not exist on plain
Postgres, so its policies are guarded no-ops there and can only be
exercised against a real Supabase stack (local CLI or hosted). Real
hosted verification of this migration is recorded in
`docs/verification/sprint-1-d2-controlled-ocr-verification.md`.

## OCR trust boundary (migration 0011)

Every write to the six new OCR tables goes through one of the
`SECURITY DEFINER` functions listed in
`docs/database/controlled-ocr-schema.md` — there is no
`INSERT`/`UPDATE`/`DELETE` RLS policy for `authenticated` on any of them.
All six tables carry a single `SELECT` policy each, gated on
`has_permission_in_organization(organization_id, 'guideline_ocr.read')`.

The three Worker-only functions
(`create_document_ocr_run`/`finalize_document_ocr_page`/`fail_document_ocr_run`)
are explicitly revoked from `PUBLIC`/`anon`/`authenticated` — proven
directly (a real `authenticated` role-switch attempting to call
`create_document_ocr_run` and receiving `insufficient_privilege`, not
just "no UI button") by
`supabase/tests/rls/011_controlled_ocr.sql` TEST 15.

## New permissions

`guideline_ocr.read`, `.create`, `.cancel`, `.review`, `.submit_review`,
`.reopen_review`, `.read_artifacts`, `.read_source`, `.reprocess` —
granted to `organization_admin` (governance actions, no review actions),
`quality_manager` (full: create/cancel/review/submit/reopen), and
`clinical_reviewer` (review/submit only, no create/cancel/reopen).
`safety_officer` and `auditor` hold `guideline_ocr.read` only. A
clinician holds none of these permissions — the OCR RLS `SELECT` policy
returns zero rows to a clinician session regardless of any UI mistake,
proven directly in TEST 13.

## `guideline_ocr.read_source` — reserved, not yet wired to a signed-URL action

`guideline_ocr.read_source` exists in the permission table and is granted
to the same roles that hold `guideline_ocr.read_artifacts`, mirroring
`guideline_extraction_source.read`'s role in the review-workspace's PDF
panel. It is **not yet called from any application-layer action** — the
OCR review workspace UI (side-by-side original page / native text / OCR
text) is out of scope for this sprint's database/Worker work and is
tracked as remaining UI work (see `KNOWN_LIMITATIONS.md`). When that UI
is built, it should mint a signed URL the same way
`createExtractionReviewSourceAccessAction()` already does — gate on
`requirePermission(PERMISSIONS.GUIDELINE_OCR_READ_SOURCE)`, then rely on
migration 0010's `guideline_documents.read`-gated Storage policy for the
actual object read (the same two-permission pattern
`extraction-review-authorization.md` documents for the extraction review
workspace: one permission gates the application action, a second,
Storage-layer permission gates the actual object bytes).

## Self-review

`start_document_ocr_review()` blocks whoever uploaded or registered the
underlying source document from starting (and therefore ever submitting)
a technical review of OCR output derived from it — an unconditional
block, the same shape as Sprint 1-D1's `start_document_extraction_review()`
policy. See `docs/database/controlled-ocr-schema.md` for the schema
detail and `supabase/tests/rls/011_controlled_ocr.sql` TEST 24 for the
proof.

## Provider secrets and data residency

Tesseract runs self-hosted inside the Worker's own process/container — no
API key, no network call, no guideline page content ever leaves Noor's
own infrastructure for OCR. There is no cloud-provider secret to protect
in this sprint's design, and no subprocessor/DPA question to answer (see
ADR 0012's comparison table for the rejected cloud-API alternative).

## Explicit non-goals of this sprint's security model

- No new Storage bucket or per-object ACL was introduced for OCR
  artifacts — they live in the existing `guideline-processed` bucket,
  under a page-namespaced path (see `docs/database/controlled-ocr-schema.md`).
- Rendered page images are never persisted to Storage or local disk by
  default (mission §16/§17) — only their checksum is recorded.
- No rate limiting was added beyond the existing per-request permission
  check.
- The OCR review workspace UI, and therefore its signed-source-access
  action, is not implemented this sprint (see above).
