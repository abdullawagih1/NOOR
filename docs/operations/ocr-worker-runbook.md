# OCR Worker Runbook (Sprint 1-D2)

Operational reference for running the controlled page-scoped OCR
processor. See `docs/operations/worker-processing-runbook.md` for the
base orchestration loop this plugs into (claim/lease/heartbeat/complete)
and `docs/operations/pdf-extraction-worker-runbook.md` for the extraction
mode this mirrors one layer deeper — this document covers only what's
new: `WORKER_PROCESSING_MODE=ocr`.

## Turning OCR on

Requires everything `noop`/`extraction` mode requires
(`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) plus:

```env
WORKER_PROCESSING_MODE=ocr
WORKER_ENABLED_JOB_TYPES=document_ocr
```

`OCR_PIPELINE_VERSION`/`OCR_CONFIGURATION_VERSION`/`OCR_RENDER_CONFIGURATION_VERSION`/
`OCR_RENDER_DPI`/`OCR_RENDER_COLOR_MODE`/`OCR_RENDER_IMAGE_FORMAT` should
stay empty in normal operation — leaving them empty uses the pinned
defaults in `app/ocr/config.py`. Only override them as part of a
deliberate, reviewed version bump (ADR 0012's upgrade policy; see
`docs/operations/ocr-model-upgrade.md`) — a stale/mismatched value here
would silently create OCR results under the wrong recorded identity.

At startup (`app/main.py`'s `lifespan`, `WORKER_PROCESSING_MODE=ocr`
branch), three pin-assertions run and **crash the process** on mismatch,
the same fail-closed discipline `assert_pinned_extractor_version()`
already established for extraction:

- `assert_pinned_renderer_version()` — installed `pypdfium2` package
  version must match `RENDERER_VERSION`.
- `assert_pinned_provider_version()` — `tesseract --version` output must
  match `OCR_PROVIDER_VERSION` (`5.5.0`).
- `assert_pinned_tessdata_models(tessdata_dir)` — both `eng.traineddata`
  and `ara.traineddata` must exist at `OCR_TESSDATA_DIR` (default:
  `app/ocr/config.py`'s `DEFAULT_TESSDATA_DIR`, i.e. the repo-local
  `apps/worker/tessdata/`) with the exact pinned byte size and SHA-256 —
  see `docs/operations/ocr-model-upgrade.md`.

## What actually runs

Each claimed `document_ocr` job (`app/ocr/processor.py::make_ocr_processor`),
one page per job:

1. `get_ocr_job_context` — join the claimed job back to its
   `document_ocr_request_pages` row and the request's pinned
   provider/renderer/model identity.
2. `get_source_document` — the registered source document's storage
   location and checksum.
3. **Phase 1 — render**: download and revalidate the exact source object,
   then rasterize the exact page (`pypdfium2`), bounded by
   `OCR_MAX_SECONDS` via a `ThreadPoolExecutor` + `future.result(timeout=...)`
   — on timeout, the render thread keeps running to completion in the
   background rather than being unsafely killed (mission §26); its
   eventual result is discarded, and the attempt is reported as
   `ocr_timeout`. The rendered image lives only in memory — never written
   to disk or Storage.
4. **Phase 2 — create/reuse the OCR run**: call `create_document_ocr_run`
   with the now-known `page_image_sha256`/`page_image_size_bytes`. If an
   identical identity already `succeeded`, the call returns
   `out_reused = true` and the request page is immediately marked
   `succeeded` — recognition is skipped entirely, no second provider call,
   no duplicate artifact.
5. **Phase 3 — recognize** (only if not reused): run Tesseract
   (`app/ocr/provider.py`), normalize the text, build the canonical
   artifact, upload it to `guideline-processed`, and independently
   re-download + re-hash it to verify (never trust the upload response
   alone) — bounded by a second `OCR_MAX_SECONDS` timeout.
6. `finalize_document_ocr_page` — marks the run and request page
   `succeeded`.
7. Return a `succeeded` `ProcessingOutcome` — the existing, unchanged
   `WorkerLoop._report_outcome` then calls `complete_document_processing_job`
   exactly as it always has.

On any `OcrError` **after** a run row exists (i.e. rendering already
succeeded), step 7 instead calls `fail_document_ocr_run` and returns a
`retryable_failure`/`terminal_failure` outcome, classified by
`app/ocr/errors.py`'s `RETRYABLE_BY_ERROR_CODE` map — the existing
`WorkerLoop` then calls `fail_document_processing_job` with the same
classification, driving retry/dead-letter behavior unchanged from Sprint
1.2A. A render failure (before any run row exists) skips straight to a
`ProcessingOutcome` with no `fail_document_ocr_run` call — there is no
run to report failure against.

## Heartbeat during OCR

Same as extraction: no manual heartbeat calls exist inside the OCR
pipeline itself. `WorkerLoop._process_claimed_job` already starts a
background heartbeat thread before calling the configured processor and
stops it after — this covers the render and recognition phases
automatically. A stale Worker's attempt to finalize or report failure
after its lease was reclaimed is structurally rejected by
`assert_lease_owner` inside `create_document_ocr_run`/
`finalize_document_ocr_page`/`fail_document_ocr_run` — no new
client-side detection logic needed.

## Language hints

`app/ocr/config.py`'s `SUPPORTED_LANGUAGE_HINTS = ("eng", "ara")`. The
OCR request's `language_hints` array (set at request-creation time,
server-side — never an arbitrary browser-supplied provider argument) is
passed straight through to Tesseract as `lang="+".join(hints)` (e.g.
`"eng+ara"` for a mixed-language page).

## Local run (with OCR active)

```bash
cd apps/worker
python scripts/fetch_tessdata_models.py   # once, or whenever tessdata/ is empty
cp .env.example .env
# edit .env:
#   WORKER_INTERNAL_TOKEN=<openssl rand -hex 32>
#   SUPABASE_URL=<hosted or local-with-PostgREST Supabase URL>
#   SUPABASE_SERVICE_ROLE_KEY=<matching service role key>
#   WORKER_PROCESSING_MODE=ocr
#   WORKER_ENABLED_JOB_TYPES=document_ocr
uvicorn app.main:app --reload --port 8080
```

Requires a real `tesseract` binary on `PATH` (`apt-get install
tesseract-ocr` on Debian/Ubuntu, matching the version pinned in
`app/ocr/config.py`; already provisioned in the production Dockerfile).
Same caveat as the base runbook: the local Docker Postgres container used
for `supabase/tests/rls/*.sql` does not run PostgREST — point
`SUPABASE_URL` at a real Supabase project to exercise this end-to-end.

## Verification (reproducible)

```bash
python -m compileall apps/worker
cd apps/worker && pytest tests/ -v
```

`test_ocr_processor.py` proves Worker orchestration (claim, render-then-
create-run ordering, reuse, finalize/fail, error classification, timeout,
lease-loss tolerance) against a fake in-memory `OrchestrationClient` with
`render_source_page`/`recognize_and_build_artifact` monkeypatched — no
real rendering or recognition, no real network. `test_ocr_renderer_and_provider.py`
separately proves the *real* renderer and provider against the synthetic
PDF fixtures (real rasterization, real Tesseract recognition including
mixed Arabic/English) — skipped cleanly, not failed, on a machine lacking
the `tesseract` binary or pinned tessdata models. See
`docs/verification/sprint-1-d2-controlled-ocr-verification.md` for the
full record, including a real Docker-image build-and-run smoke test.

## Known limitations

* One OCR provider (Tesseract), no failover — see ADR 0012.
* No handwriting recognition, no table reconstruction, no form
  understanding, no manual text correction (mission §6).
* Provider confidence (`image_to_data`'s per-word confidence) is
  technical metadata only — never presented as clinical or evidence
  confidence, and not comparable across providers (mission §20).
* `WORKER_MAX_CONCURRENT_JOBS` remains declared but unenforced (unchanged
  from Sprint 1.2A) — one OCR page at a time per Worker process.
* Orphaned temp files from a hard-killed (`SIGKILL`) Worker process are
  not actively swept by a startup routine (same limitation carried
  forward from `pdf-extraction-worker-runbook.md`).
* OCR quality has not been benchmarked against real, complex clinical
  guideline scans — only synthetic fixtures. Production-scale
  performance is untested.
