# PDF Extraction Worker Runbook (Sprint 1.2B)

Operational reference for running the real, deterministic PDF extraction
processor. See `docs/operations/worker-processing-runbook.md` for the
base orchestration loop this plugs into (claim/lease/heartbeat/complete) —
this document covers only what's new: `WORKER_PROCESSING_MODE=extraction`.

## Turning extraction on

Requires everything `noop` mode requires (`SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`) plus:

```env
WORKER_PROCESSING_MODE=extraction
WORKER_ENABLED_JOB_TYPES=document_parsing
```

`EXTRACTION_PIPELINE_VERSION`/`EXTRACTION_CONFIGURATION_VERSION` should
stay empty in normal operation — leaving them empty uses the pinned
defaults in `app/pdf_extraction/config.py` (`pdf-text-v1`/`1`). Only
override them as part of a deliberate, reviewed version bump (ADR 0010's
upgrade policy) — setting a stale/mismatched value here would silently
create extraction results under the wrong recorded identity.

At startup, `assert_pinned_extractor_version()` cross-checks the
installed `pypdf` package version against the pinned
`PDF_EXTRACTOR_VERSION` constant and **crashes the process** if they
disagree — a `requirements.txt` bump that forgets to update the constant
fails loudly at import time, not silently during the first real
extraction.

## What actually runs

Each claimed `document_parsing` job (`app/pdf_extraction/processor.py::make_extraction_processor`):

1. Read the registered source document's storage location and checksum
   (`OrchestrationClient.get_source_document` — a plain trusted table
   read).
2. Confirm it's `verified`/`registered`; call `create_document_extraction_run`.
   If an identity match already `succeeded`, skip straight to job
   completion — no download, no extraction, no upload.
3. Download and revalidate the exact source object
   (`source_download.py`), bounded by `EXTRACTION_MAX_SECONDS` (default
   300s) via a `ThreadPoolExecutor` + `future.result(timeout=...)` — on
   timeout, the extraction thread keeps running to completion in the
   background rather than being unsafely killed (mission §26); its
   eventual result is simply discarded, and the attempt is reported as
   `extraction_timeout`.
4. Extract pages (`pypdf`), normalize, checksum, compute metrics.
5. Build the canonical artifact, upload it to `guideline-processed`, and
   independently re-download + re-hash it to verify (never trust the
   upload response alone).
6. Bulk-insert page rows, then call `finalize_document_extraction_run`.
7. Return a `succeeded` `ProcessingOutcome` — the existing, unchanged
   `WorkerLoop._report_outcome` (Sprint 1.2A) then calls
   `complete_document_processing_job` exactly as it always has.

On any `ExtractionError`, step 7 instead calls `fail_document_extraction_run`
(marks the extraction run itself failed) and returns a
`retryable_failure`/`terminal_failure` outcome — the existing `WorkerLoop`
then calls `fail_document_processing_job` with the same classification,
driving retry/dead-letter behavior unchanged from Sprint 1.2A.

## Heartbeat during extraction

No manual heartbeat calls exist inside the extraction pipeline itself.
`WorkerLoop._process_claimed_job` (Sprint 1.2A, unchanged) already starts
a background heartbeat thread on its own timer *before* calling whichever
processor is configured, and stops it *after* — this covers the entire
extraction pipeline call automatically, satisfying "heartbeat must remain
active during source download/extraction/serialization/upload/finalization"
(mission §24) without any extraction-specific heartbeat code.

**If the lease is lost mid-extraction** (background heartbeat calls
failing silently, logged but not itself aborting the foreground
extraction thread — same as Sprint 1.2A's existing behavior for the
no-op processor), the Worker does not need to detect this proactively:
`finalize_document_extraction_run`/`fail_document_extraction_run` both
call `assert_lease_owner` first, so a stale Worker's attempt to finalize
or report failure after its lease was reclaimed is structurally rejected
by the database — "do not finalize, do not complete" (mission §24) is
enforced by the same lease-hash mechanism proven in Sprint 1.2A, not by
new client-side logic.

## Temp file handling

See `docs/security/pdf-extraction-security.md`'s temp-file-safety section.
`EXTRACTION_TEMP_DIRECTORY` (empty by default → OS default
`tempfile.mkdtemp()`) only needs setting if your deployment platform
requires temp files on a specific volume.

## Local run (with extraction active)

```bash
cd apps/worker
cp .env.example .env
# edit .env:
#   WORKER_INTERNAL_TOKEN=<openssl rand -hex 32>
#   SUPABASE_URL=<hosted or local-with-PostgREST Supabase URL>
#   SUPABASE_SERVICE_ROLE_KEY=<matching service role key>
#   WORKER_PROCESSING_MODE=extraction
uvicorn app.main:app --reload --port 8080
```

Same caveat as the base runbook: the local Docker Postgres container used
for `supabase/tests/rls/*.sql` does not run PostgREST — point
`SUPABASE_URL` at a real Supabase project to exercise this end-to-end.

## Verification (reproducible)

```bash
python -m compileall apps/worker
cd apps/worker && pytest tests/ -v
```

91 assertions total this sprint (see
`docs/verification/sprint-1.2b-pdf-extraction-verification.md` for the
exact breakdown): the 59 pre-existing (Sprint 1.2A and earlier,
unaffected) plus new suites covering fixture behavior, determinism,
source-integrity revalidation, and end-to-end processor orchestration
(reuse, failure classification, idempotent replay, lease-loss tolerance)
against a fake in-memory `OrchestrationClient` and mocked Storage HTTP
layer — no real network, no real Supabase project needed to run this
suite.

## Known limitations

* No OCR, no table reconstruction, no image extraction (mission §41).
* Complex multi-column PDFs may have imperfect reading order (a `pypdf`
  characteristic, not fixed or hidden by this pipeline).
* Encrypted/password-protected PDFs are rejected outright, not decrypted
  with a supplied password.
* `WORKER_MAX_CONCURRENT_JOBS` remains declared but unenforced (unchanged
  from Sprint 1.2A) — one extraction at a time per Worker process.
* Orphaned temp files from a hard-killed (`SIGKILL`, not graceful
  shutdown) Worker process are not actively swept by a startup cleanup
  routine this sprint — the OS's own temp-directory lifecycle (container
  restart, `/tmp` cleanup policy) is the only backstop. Worth a dedicated
  startup-sweep if this proves to matter operationally.
* Extraction quality (character/word accuracy) has not been benchmarked
  against real, complex clinical guideline PDFs — only synthetic
  fixtures. Production-scale performance is untested.
