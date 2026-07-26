# Secure Document Intake — Authorization Model

Source: `supabase/migrations/0006_secure_guideline_document_intake.sql`,
`apps/web/lib/documents/actions.ts`.

## Defense in depth (ADR 0003, extended to Storage)

1. **Permission-aware UI** — the upload panel only renders when
   `guideline_documents.upload` is held and the version's lifecycle status
   is upload-eligible; quarantine/cancel-job forms only render for holders
   of `guideline_documents.reject`/`guideline_processing_jobs.cancel`.
2. **Server Action gate** — every function in `lib/documents/actions.ts`
   calls `requirePermission(...)` before touching the database or Storage.
3. **Database RLS** — every table's SELECT policy is permission-scoped;
   there is no INSERT/UPDATE/DELETE policy on any of the five new tables
   for `authenticated` at all.
4. **Database function-level checks** — every write function independently
   re-derives `auth.uid()` and calls `has_permission_in_organization`.
5. **Storage RLS** — `noor_buckets_insert_own_org`/`select_own_org`
   (migration 0003) are what actually authorize the signed-upload PUT and
   the server's verification download; no service-role key is used
   anywhere in this flow.

## No arbitrary bucket or path selection

The client never chooses a Storage bucket or path. `create_guideline_upload_session()`
generates the path server-side from server-verified identifiers only —
`organization_id` (from the resolved guideline version, never a client
parameter), `guideline_id`/`guideline_version_id` (from the same lookup),
and a fresh `gen_random_uuid()` document id. The only client-influenced
segment is the filename, and it is sanitized
(`regexp_replace(filename, '[^A-Za-z0-9._-]', '_', 'g')`) before being
appended — `/` is stripped, so no path-traversal segment can survive into
the final key. The resulting path always matches the existing storage
policies' `(storage.foldername(name))[1]::uuid in (select
current_active_organization_ids())` check, since the first segment is
always the caller's own organization id.

## Object verification never trusts the browser

`completeGuidelineUploadAction` (`apps/web/lib/documents/actions.ts`)
independently re-downloads the object from Storage using the same
RLS-scoped session that uploaded it — not a service-role client, not a
value the browser reports. It then, server-side:

* Checks the downloaded byte length against `MAX_UPLOAD_SIZE_BYTES`.
* Checks the first 5 bytes equal the literal PDF signature `%PDF-`.
* Computes SHA-256 over the actual downloaded bytes (`node:crypto`).

None of these three facts are ever accepted as a parameter from client
JavaScript. The optional `expectedSha256`/`expectedSizeBytes` a client may
supply at session-creation time are stored only as the *caller's claim*,
never compared authoritatively, and never substituted for the server's own
computation. See ADR 0008.

**Known, explicitly documented limit:** PDF-signature validation confirms
the file *is a PDF*; it does not prove the file is safe or clinically
valid. No malware-scanning engine is wired in this sprint (mission §14 —
"prepare a future hook... without implementing an unavailable provider").
See `KNOWN_LIMITATIONS.md`.

## Duplicate detection does not leak across organizations

Both duplicate checks inside `complete_guideline_upload()` are scoped by
`organization_id = v_org` (same-version) or explicitly `organization_id =
v_org and ... other version` (cross-version) — there is no code path that
queries `guideline_source_documents` across organizations for duplicate
detection. A caller can therefore never learn, directly or by inference
(timing, a different rejection reason, etc.), whether another organization
has already uploaded a matching file — the query that would need to exist
to leak that information simply is not written.

## Tenant isolation

Every table carries `organization_id`; every write function resolves it
from a server-verified source (the guideline version being uploaded to,
or the existing row being acted on) — never a client-supplied parameter.
Composite foreign keys tie every child table back to
`guideline_source_documents`/`document_upload_sessions`/
`document_processing_jobs` by `(organization_id, id)`, making a
cross-tenant reference structurally impossible to insert. Verified: TEST 3
(cross-tenant upload-session creation denied), TEST 9/9b (clinician sees
nothing; a permitted role sees everything), TEST 10/10b (suspended/removed
denied) in `supabase/tests/rls/005_document_intake.sql`.

## Idempotency

* **Upload-session creation**: `unique (organization_id, idempotency_key)`
  + an explicit pre-check that returns the existing session verbatim on a
  replayed key (TEST 4).
* **Upload completion**: a session already in a terminal state
  (`completed`/`rejected`/`expired`/`cancelled`) short-circuits to return
  its existing outcome rather than re-verifying (TEST 7).
* **Processing job creation**: `unique (organization_id, idempotency_key)`
  keyed as `'intake:' || document_id`, with an `ON CONFLICT ... DO UPDATE
  ... RETURNING` upsert — a second completion attempt (even bypassing the
  session-terminal short-circuit somehow) cannot create a second job for
  the same document.

## Worker boundary

The browser never calls the Worker. This sprint creates
`document_processing_jobs` rows only — no queue message is published, no
HTTP call to the Worker's `/jobs` endpoint happens. `WORKER_INTERNAL_TOKEN`
remains exclusively server-to-server, unused by this sprint's code paths
entirely (Sprint 1.2, S1-C, is where a queue publish first occurs).

## Remaining risks

* No malware/antivirus scanning — PDF signature validation is not a
  security scan (see above).
* Self-quarantine-by-the-uploader is not specially prevented: unlike
  guideline approval, `guideline_documents.upload` and
  `guideline_documents.reject` are never granted to the same role in the
  seeded mapping, so this isn't reachable with default roles — but no
  database-level check would stop it if a future role combined both. Worth
  a dedicated check if that combination is ever introduced.
* Session `expires_at` (30 minutes) is a fixed constant, not yet
  configurable per environment.
