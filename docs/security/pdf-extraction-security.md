# PDF Extraction — Security Model (Sprint 1.2B)

Source: `supabase/migrations/0008_deterministic_pdf_extraction.sql`,
`apps/worker/app/pdf_extraction/*`. Builds on
`docs/security/worker-orchestration-authorization.md` — read that first;
this document covers what's new for extraction specifically.

## Source integrity is revalidated, never assumed

The Worker never trusts that the private Storage object still matches
what was registered at intake time. Before any extraction begins
(`app/pdf_extraction/source_download.py`):

1. Stream the exact registered object from Storage incrementally (never
   loading the full file into memory).
2. Compute SHA-256 and byte count over what was *actually received*, not
   what the response headers claim.
3. Check the first bytes equal the literal `%PDF-` signature.
4. Compare against the registered `guideline_source_documents.sha256`/
   `.size_bytes`.
5. Abort immediately on any mismatch — no extraction artifact is ever
   produced from a document that fails this check.

This is checked **twice**, independently: once by the Worker in Python
(above), and again by `create_document_extraction_run()`'s own
database-side comparison against the registered document row before it
will even create a `running` extraction-run row. Neither check alone is
trusted as sufficient — see `supabase/tests/rls/008_pdf_extraction.sql`
TEST 2 for the database-side proof, and
`apps/worker/tests/test_pdf_extraction_source_integrity.py` for the
Worker-side proof.

## Cross-tenant isolation

Every new table carries `organization_id`; every composite foreign key
ties child rows back to their parent by `(organization_id, id)`, making a
cross-tenant reference structurally impossible to insert — the same
pattern established in every migration since 0005. RLS SELECT policies on
both new tables are permission-scoped
(`guideline_extractions.read`/`.read_pages`); verified in
`008_pdf_extraction.sql` TEST 15/15b (clinician sees nothing, a permitted
role sees everything).

## Worker-only trust boundary, hardened from the start

All three new functions are **never granted to `authenticated`/`anon`** —
see `docs/database/deterministic-pdf-extraction-schema.md`'s trust-boundary
section for the exact grant/revoke pattern, which is the same hardened
pattern migration 0007 needed a real hosted-only fix to reach (ADR 0009's
addendum). Migration 0008 applies it from the very first version, not as
a follow-up correction.

## Service-role and lease-token containment

* `SUPABASE_SERVICE_ROLE_KEY` is read once at Worker startup from
  environment configuration (`app/settings.py`, validated,
  never logged) and used only for server-to-server Storage/PostgREST
  calls — the exact same containment as every prior sprint's Worker
  credential handling. It never reaches the browser; the Web app has its
  own, entirely separate, RLS-scoped session for the intake flow.
* The lease token proving a Worker owns a given job's claim is threaded
  through `create_document_extraction_run`/`finalize_document_extraction_run`/
  `fail_document_extraction_run` exactly like the six migration-0007
  functions — hashed comparison only (`assert_lease_owner`, reused
  unchanged), never a plaintext comparison, never persisted anywhere
  beyond the existing `lease_token_hash` column.
* **The lease token never appears in the extraction artifact.** The
  artifact's canonical JSON (`artifact.py::build_canonical_artifact`) is
  built entirely from `ExtractionResult`/provenance data — it has no code
  path that could reference a lease token, a Worker instance id, a signed
  URL, or a local temp file path, because none of those values are ever
  passed into the artifact-construction function at all.

## Temporary file safety

`source_download.py::download_source_to_temp_file`:

* `tempfile.mkdtemp(prefix="noor-extract-")` — OS-managed, unpredictable
  directory name, standard restrictive permissions; never derived from
  the document's original filename.
* Deleted via `shutil.rmtree(tmp_dir, ignore_errors=True)` in a `finally`
  block — runs whether extraction succeeds, fails, or raises before the
  caller's `with` body is ever entered (a Python generator's `finally`
  executes on exit regardless of where within the `try` the exit
  happened, including before the first `yield`).
* Never logged: no log statement in this codebase ever includes the temp
  path, and no `ExtractionError` message includes it either — verified
  directly in
  `apps/worker/tests/test_pdf_extraction_fixtures.py::test_no_extraction_error_message_leaks_internals`.
* No cross-process temp-file accumulation strategy exists beyond
  per-attempt cleanup — see Known Limitations
  (`docs/operations/pdf-extraction-worker-runbook.md`) for the documented
  gap if a Worker process is hard-killed (`SIGKILL`) mid-extraction.

## Artifact privacy and integrity

* Uploaded to the existing private `guideline-processed` bucket
  (migration 0003) — no public read, no signed-URL issuance to the
  browser for this content this sprint.
* Content-addressed path (`{organization_id}/guideline-extractions/{source_document_id}/{pipeline_version}/{extractor_name}-{extractor_version}/{artifact_sha256}.json`)
  — deterministic and tenant-scoped; the client never chooses this path,
  the Worker computes it entirely from server-verified identifiers plus
  the artifact's own just-computed checksum.
* **Never marked as the extraction result until independently
  re-downloaded and re-hashed** (`artifact_storage.py::upload_and_verify_artifact`)
  — an HTTP 200 from the upload call alone is never trusted as proof the
  stored bytes match what was sent.
* Artifact Storage path/bucket are **excluded from every application
  query** (`apps/web/lib/documents/queries.ts`'s `EXTRACTION_RUN_COLUMNS`)
  regardless of the caller's permission level — only the checksum
  (`artifact_sha256`) ever reaches the UI, and only for holders of
  `guideline_extractions.read_artifacts`.

## Error safety

Every extraction failure path raises `ExtractionError` with one of 17
named codes and a hand-written safe message
(`apps/worker/app/pdf_extraction/errors.py`) — never a bare Python
exception's `str(exc)`, which could contain a file path, a partial stack
frame, or other internals. Verified directly:
`apps/worker/tests/test_pdf_extraction_processor.py::test_fail_extraction_run_failure_is_swallowed_not_crashed`
proves even a *secondary* failure (reporting the failure itself failing,
e.g. because the lease was lost) never crashes the Worker or leaks
anything — it's logged and swallowed, matching the exact pattern
`app/worker_loop.py` already established in Sprint 1.2A.

## Remaining risks

* `service_role` is shared by every Worker instance (unchanged from
  Sprint 1.2A) — lease-token hash verification, not the database role,
  is what isolates one Worker instance's extraction attempt from
  another's.
* No malware/antivirus scanning on the source PDF beyond signature
  validation (unchanged limitation from Sprint 1.1) — `pypdf` parsing a
  malicious PDF could theoretically be a vector for a `pypdf`-level
  vulnerability; this sprint's timeout (`extraction_timeout`) and
  exception-containment (every parse path wrapped, classified, never
  crashes the Worker process) are the only mitigations in place.
* Orphaned temp files from a hard-killed (`SIGKILL`) Worker process are
  not actively swept — see the runbook's Known Limitations.
