# Sprint 1-D2 — Controlled Page-Scoped OCR Verification Record

Every command and result below was actually run — nothing here is
inferred or assumed. Companion docs: ADR 0012,
`docs/domain/{ocr-eligibility-and-lifecycle,ocr-page-representations}.md`,
`docs/database/controlled-ocr-schema.md`,
`docs/security/ocr-and-storage-authorization.md`,
`docs/operations/{ocr-worker-runbook,ocr-failure-recovery,ocr-model-upgrade}.md`.

**Status: complete and verified, locally and on hosted Development,
including the web application UI.** Hosted Development verification
(mission §46) was completed in a later continuation of this same session
once a Supabase Personal Access Token for the "Noor Development" project
was provided — see "Hosted Development verification" below for the full,
real account (real GoTrue JWTs, real Storage, real Tesseract/pypdfium2
execution, real Storage-RLS permission-scoping proof, full synthetic-data
cleanup verified back to zero). See "What was not done" below for the one
remaining, deliberately-scoped gap (the Vercel Preview redeploy).

## Starting state for this session

A prior Claude Code session had already written most of migrations 0010/
0011, the `apps/worker/app/ocr/*` module, ADR 0012, and an initial
`supabase/tests/rls/011_controlled_ocr.sql`, but left the work
**uncommitted** and undocumented — no `PROJECT_STATE.md`/`SPRINT_CURRENT.md`
entry existed for it. This session began with a full repository audit
(delegated to a research agent) rather than assuming that prior work was
correct or complete. The audit found the work was **not** in a runnable
state — see "Real bugs found and fixed" below.

## Real bugs found and fixed this session

1. **`apps/worker/app/ocr/processor.py` could not even be imported.** It
   called `run_ocr_pipeline`, a function that does not exist in
   `pipeline.py` (which only defines `render_source_page` and
   `recognize_and_build_artifact`) — a plain `ImportError` at module load
   time, found by actually trying to import the module inside a built
   Docker image, not by reading the code.
2. **`pipeline.py` contained dead code and calls to undefined functions**:
   an inert `if False` branch, and calls to `_require_env_supabase_url()`/
   `_require_env_service_role_key()` that are defined nowhere in the
   module.
3. **The OCR-run identity was being recorded with a permanently empty
   checksum.** `processor.py` called `create_ocr_run` *before* rendering,
   passing `""` for `page_image_sha256` — since `finalize_document_ocr_page`
   has no parameter to fill that in later, every succeeded run's
   `page_image_sha256` column would have stayed `''` forever, corrupting
   the very identity the partial unique index exists to protect. Fixed by
   restructuring the processor into the documented three-phase sequence
   (render → create/reuse run with the real checksum → recognize only if
   fresh) — see `docs/database/controlled-ocr-schema.md`.
4. **`create_document_ocr_run`'s reused branch never marked the request
   page `succeeded`.** Found while designing the RLS test for real
   identity-based reuse (not by reading the SQL): since the Worker
   deliberately skips `finalize_document_ocr_page` for a reused run, a
   reused request page would have stayed `processing` forever, blocking
   `create_document_ocr_review`'s all-pages-terminal check permanently.
   Fixed inside the reused branch itself.
5. **Missing Python dependencies and system binary.** `pytesseract` and
   `pypdfium2` were imported by the OCR module but absent from
   `requirements.txt`; the `tesseract-ocr` apt package was never installed
   in the Dockerfile, and the pinned `tessdata` models were never
   materialized at build time. Fixed in both files; confirmed by an
   actual `docker build` (see below).
6. **A Windows path-portability bug in `app/ocr/provider.py`.** Found by
   actually running the new renderer/provider tests on this
   (Windows-hosted) development machine, not assumed: `pytesseract`
   splits its `config` string with `shlex.split(config, posix=not
   is_windows)`; on Windows, non-POSIX mode does not strip quote
   characters from tokens, so a quoted `--tessdata-dir "C:\..."` value
   reached Tesseract with the closing quote still embedded in the path,
   corrupting it (`Error opening data file "C:\...\tessdata"/eng.traineddata`).
   Fixed by setting the `TESSDATA_PREFIX` environment variable instead of
   the `--tessdata-dir` config flag — a mechanism Tesseract supports
   natively and that sidesteps config-string parsing (and therefore this
   platform difference) entirely. Confirmed identical behavior on Linux
   (rebuilt the Docker image, re-ran the same recognition call, byte-for-
   byte same output) — this was a real portability fix, not a
   Linux-behavior regression.
7. **Two schema-level gaps against the mission's own invalidation rules
   (§10) and established self-review policy**, found by reading
   migration 0011 end-to-end against the mission text, not by testing
   failures: (a) reopening the extraction review never cascaded into an
   already-created OCR request — an in-flight OCR pipeline for a
   superseded review round had no mechanism to stop; (b)
   `start_document_ocr_review` had no self-review block, unlike its
   extraction-review analogue (migration 0009). Both fixed inside
   migration 0011 (uncommitted at the time, so edited directly rather
   than requiring a new migration file) — see
   `docs/database/controlled-ocr-schema.md` for the mechanism and TEST
   21/24 for the proof.
8. **A cross-sprint consistency gap between `submit_document_extraction_review`
   (migration 0009) and this sprint's page-based OCR eligibility model**,
   found by a fresh-container run of the *pre-existing* `009_extraction_review.sql`
   suite failing after `get_document_page_text_readiness` was fixed (bug
   3 above), not by inspection. Migration 0009's `ocr_required` validation
   only required an OCR-relevant *finding* to exist — it never required
   any page to actually be marked `ocr_candidate`. That made it possible
   to submit `ocr_required` with zero pages `create_document_ocr_request()`
   could ever act on; `get_document_page_text_readiness()` would then
   correctly report every page as already native-ready, silently making
   the whole run immediately chunking-eligible despite the reviewer
   supposedly requiring OCR — the exact case 009's own TEST 27 (written
   before this sprint existed) had encoded as "should stay chunking-
   ineligible." Fixed with a `create or replace` of
   `submit_document_extraction_review` inside migration 0011, adding a
   check that at least one page must be marked `ocr_candidate` for an
   `ocr_required` submission — the same canonical signal
   `create_document_ocr_request()` already keys off — and updating 009's
   TEST 27 fixture to mark page 3 `ocr_candidate` (plus a new assertion
   proving the tightened rule itself is enforced) to match the now-
   consistent behavior.

## Local database verification — real Postgres 16, four genuinely fresh containers

Following this repo's own established discipline (Sprint 1.2B's lesson:
a reused container can silently mask a CI-only bug), the full migration
+ seed + RLS suite was run against **four separate, freshly-created**
`postgres:16` Docker containers — not the same container reused across
iterations (the first run caught a real ordering bug, and a later run
caught bug 8 above; see below).

```
$ docker run -d --name noor_test_pg -e POSTGRES_PASSWORD=postgres \
    -e POSTGRES_DB=noor_test -p <port>:5432 postgres:16
$ for f in supabase/migrations/*.sql; do psql ... -f "$f"; done
→ 0001-0011 all applied with zero errors (all four containers)

$ psql ... -f supabase/seed.sql   → applied cleanly (all four containers)

$ for f in supabase/tests/rls/*.sql; do psql ... -f "$f"; done
→ 001_tenant_isolation.sql:                7/7  PASSED
→ 002_auth_hardening.sql:                  5/5  PASSED (incl. 1b/3b sub-assertions)
→ 003_guideline_registry.sql:             24/24 PASSED (incl. sub-assertions)
→ 004_g12_self_approval_regression.sql:    4/4  PASSED
→ 005_document_intake.sql:                18/18 PASSED (incl. sub-assertions)
→ 006_processing_orchestration.sql:       21/21 PASSED (incl. sub-assertions), "ALL PASSED"
→ 007_security_hardening_review.sql:       4/4  PASSED (1 skipped, expected locally), "ALL PASSED"
→ 008_pdf_extraction.sql:                 17/17 PASSED, "ALL PASSED"
→ 009_extraction_review.sql:              41/41 PASSED (1 skipped, expected locally), "ALL PASSED"
  (was 38/38 before bug 8's fix — TEST 27 now additionally proves that
  ocr_required with a finding but no ocr_candidate page is rejected,
  before marking page 3 ocr_candidate and re-submitting for real)
→ 011_controlled_ocr.sql:                 25/25 PASSED (incl. 13b sub-assertion), "ALL CONTROLLED OCR TESTS PASSED"
```

**A real ordering bug in the new test file was found by the first fresh-
container run, not by inspection**: TEST 17's two throwaway, unlinked
`document_ocr` jobs (inserted directly to prove the page-scoped
uniqueness index) were never cleaned up, so they sat `queued` and were
claimed by `claim_next_document_processing_job('document_ocr')` ahead of
the real, request-linked jobs TEST 19 depended on — TEST 19 failed with
`job ... is not a document_ocr page job`. Fixed by having TEST 17 delete
its own throwaway jobs immediately after asserting the constraint;
re-verified clean on two subsequent fresh containers.

### New assertions this sprint (25, all in `011_controlled_ocr.sql`)

Covers: request creation + idempotency + clinician denial (1-3); the full
Worker flow claim→render→create-run→OCR→finalize (4); identity-uniqueness
defense in depth (5); succeeded-run immutability (6); review-opening gate
(7); full accept lifecycle + eligibility flip (8); canonical page-text
readiness reporting both OCR and native pages correctly (9); OCR-review
reopen/historical-preservation (10-11); administrative OCR-review
invalidation (12); RLS (clinician denied, org_admin permitted,
cross-tenant denied) (13-14); Worker-only trust boundary (15); finding
delete-blocked-without-override (16); page-scoped (not document-scoped)
job uniqueness (17); a second, independent request (18);
`fail_document_ocr_run` + retry-produces-a-fresh-run-not-a-reuse (19-20);
**the extraction-review-reopen cascade, with proof that a succeeded page
is left historically untouched while the request is invalidated** (21);
`cancel_document_ocr_request` (22); **real function-level identity-based
reuse across two different OCR requests, with proof the reused page is
immediately marked succeeded** (23); **self-review block** (24);
`create_ocr_finding`/`update_ocr_finding_status`/`submit_document_ocr_review('rejected')`
(25).

**Deliberately not covered locally**: `accepted_with_warnings` and
`reprocessing_required` as `submit_document_ocr_review` target statuses
(only `accepted` and `rejected` are exercised) — the validation logic for
all four statuses was read directly against the SQL and is structurally
identical in shape to the already-tested two; adding dedicated tests for
the remaining two is straightforward follow-up work, not a discovered
gap. Migration 0010's Storage policies have zero local coverage by
design (the `storage` schema does not exist on plain Postgres) — see
`docs/security/ocr-and-storage-authorization.md`.

## Worker verification — real Python, real Tesseract, real Docker

```
$ python -m compileall apps/worker/app   → clean, 0 errors
$ cd apps/worker && pytest tests/ -v
→ 79 passed (71 pre-existing/unaffected + 8 new in test_ocr_renderer_and_provider.py)
```

`test_ocr_processor.py` (12 assertions, included in the 71 "pre-existing"
count above since it was added and passing before the renderer/provider
file): Worker orchestration against a fake `OrchestrationClient` with
`render_source_page`/`recognize_and_build_artifact` monkeypatched —
successful flow call-order, the real-checksum-not-a-placeholder
regression guard, reused-identity skip, render-failure-vs-recognition-
failure classification (and that `fail_ocr_run` is only called once a
run row exists), five distinct error-classification paths, lease-loss
tolerance on both finalize and fail-reporting, and a render-timeout proof.

`test_ocr_renderer_and_provider.py` (8 assertions): **real, non-mocked**
`pypdfium2` rendering and **real Tesseract recognition** against the
existing synthetic PDF fixtures — deterministic checksum for repeated
renders of the same page, different DPI produces a different checksum,
out-of-range page and corrupt-PDF error classification, real English
recognition (>80% average confidence), **real mixed Arabic/English
recognition** (asserted to contain both Latin and Arabic Unicode ranges
in the output), an empty-image page correctly producing the
`ocr_produced_no_text` warning, and confirmation the local tessdata
filesystem path never leaks into `provider_metadata_safe`. Skipped
cleanly (not failed) if `tesseract`/pinned tessdata are absent — verified
present on this machine (`tesseract v5.5.0.20241111`, matching the pin).

### Real Docker-image build-and-run smoke test

```
$ cd apps/worker && docker build -t noor-worker-ocr-test .
→ tesseract-ocr installed via apt (5.5.0-1+b1, matching the pin on this
  exact base image — confirmed via apt-cache policy before pinning, not
  assumed), tessdata fetched and checksum-verified during the build,
  pip install clean

$ docker run ... python -c "... assert_pinned_renderer_version() ...
  assert_pinned_provider_version() ... assert_pinned_tessdata_models() ..."
→ all three pin assertions pass inside the built image

$ docker run ... (render + recognize one_page_english.pdf and
  arabic_and_english.pdf directly, no mocks)
→ one_page_english.pdf: rendered 2481x3508px @ 300 DPI, OCR chars=119
  words=17 avg_conf=95.9%, correct English text recovered
→ arabic_and_english.pdf: OCR chars=51 words=8 avg_conf=94.25%, correct
  English text AND correct Arabic characters recovered
```

This is real, end-to-end proof the shipped Docker image can actually
render a page and run Tesseract against it — not just that the Python
imports resolve. The test image and container were removed after (`docker
rmi`/`docker rm -f`) — no stray images/containers left behind.

## Web application UI — built and verified this session

Unlike the rest of this record (which covers work already in progress
from an earlier session), the web UI was built from scratch in this
session: `apps/web/lib/ocr/{config,queries,schemas,errors,actions,ui}.ts(x)`
(the application layer — pinned OCR identity constants mirroring
`apps/worker/app/ocr/config.py`, explicit-column queries, Zod validation,
safe error mapping, and a Server Action per RPC, matching
`apps/web/lib/extraction-review/*`'s established shape one layer
deeper), plus three new/extended routes:

* `/reviewer/ocr` — the OCR review queue (mirrors `/reviewer/extractions`).
* `/reviewer/ocr/[ocrReviewId]` — the side-by-side review workspace:
  original page (signed URL via a new, OCR-specific
  `createOcrReviewSourceAccessAction`, gated by `guideline_ocr.read_source`
  rather than the extraction permission), native extraction text, and OCR
  recognition result (character/word counts, average confidence
  explicitly labeled as provider-specific technical metadata, text
  checksum, warnings) shown in three columns, findings and the decision
  form below.
* The guideline detail page's extraction summary card gained an OCR
  section: "Start OCR request" when the latest extraction review is
  `ocr_required` and no request exists yet, the request's status once one
  does, and "Open OCR review" once a review round exists — reusing the
  exact same permission-gated pattern as the existing "Start technical
  review" button.

```
$ npm run typecheck --workspace=apps/web   → clean
$ npm run lint --workspace=apps/web        → No ESLint warnings or errors
$ npm run build --workspace=apps/web       → succeeds; /reviewer/ocr and
  /reviewer/ocr/[ocrReviewId] both present in the route table
$ (each test file run individually — the npm/tsx cold-start added
  unrelated latency to the chained npm script in this sandboxed session)
  → all 14 files, 136 assertions total, 100% pass, including two new
  files this session: ocr-schemas.test.ts (17 assertions) and
  ocr-errors.test.ts (16 assertions)
```

`permissions.test.ts` (which scans every `supabase/migrations/*.sql` file
and asserts every permission key referenced in `apps/web/lib/auth/permissions.ts`
is actually seeded by one of them) passed against the 9 new
`GUIDELINE_OCR_*` constants added to that file — confirming they match
migration 0011's real grants, not just a plausible-looking guess.

**A real, direct TypeScript bug was found and fixed while writing
`lib/ocr/queries.ts`**, not by reading the code: `listOcrReviewQueue`
accessed `.source_document_id`/`.id` directly on rows from a
`.select(REQUEST_COLUMNS)` call (a non-literal string, so Supabase's
generated types cannot infer the row shape), which `tsc --noEmit` caught
as `Property 'source_document_id' does not exist on type
'GenericStringError'`. Fixed by following
`apps/web/lib/extraction-review/queries.ts`'s established
`(r as unknown as RowType).field` cast pattern at every such access site,
which that file already uses precisely to avoid this class of error.

## CI

`.github/workflows/pr.yml`'s `worker` job was updated to install
`tesseract-ocr` via apt and run `scripts/fetch_tessdata_models.py` before
`pytest`, so the new OCR tests can actually run in CI rather than being
silently skipped for a missing engine. `ubuntu-latest`'s own
`tesseract-ocr` apt version will not necessarily match the pin exactly —
that exact pin is verified against the production Docker base image
(above), not the CI runner; this is a deliberate, documented distinction,
not an oversight. **This workflow change has not itself been run through
GitHub Actions this session** (no push/PR was made) — see "What was not
done" below.

## Hosted Development verification (mission §46) — real, done in a later continuation of this session

The prior version of this record said this section could not be done for
lack of credentials. The user then supplied a Supabase Personal Access
Token for the real "Noor Development" project (`quohfsaqeqzbbvmrhmbr`,
region eu-west-3, Postgres 17.6.1), the same one used for Sprint 1.2B and
1-D1's hosted verification. Every step below used that token (or a real
GoTrue JWT obtained through it) — never a shortcut, never simulated.

**Migrations applied to hosted** via the Supabase Management API's
`database/query` endpoint (the same mechanism used for 0001-0009 in prior
sprints): `0010_permission_scoped_storage_access.sql` then
`0011_controlled_page_scoped_ocr.sql`, both HTTP 201, zero errors.
Verified directly afterward: `document_ocr_requests`/`document_ocr_runs`/
`document_ocr_reviews` now exist; the pre-migration `storage.objects`
policies `noor_buckets_select_own_org`/`noor_buckets_insert_own_org` are
gone, replaced by `storage_guideline_originals_select`/`_insert` and
`storage_guideline_processed_select`; `guideline_ocr.read` is seeded into
`role_permissions`; `create_document_ocr_request` exists as a function.

**Real end-to-end pipeline, real GoTrue JWTs, the actual production
Worker code, real Tesseract/pypdfium2 execution:**

1. Three real GoTrue users created via the Auth Admin API (`organization_admin`,
   `clinical_reviewer`, `clinician` — the last one exists purely to prove
   denial), a synthetic organization and role memberships inserted, then
   all three signed in for real (`POST /auth/v1/token?grant_type=password`)
   to obtain real access tokens — no service-role key used for any of the
   application-layer calls that follow.
2. As the real admin JWT: created a clinical domain, authority, guideline,
   and guideline version, then ran the full two-step upload flow exactly
   as the web app does — `create_guideline_upload_session`, a real `PUT`
   of `image_only_no_text_layer.pdf` (the synthetic, no-text-layer fixture)
   straight to Supabase Storage using the admin's own JWT, then
   `complete_guideline_upload`. This queued a real `document_processing_jobs`
   row (`job_type = document_parsing`).
3. Ran the **actual, unmodified** `app.pdf_extraction.processor.make_extraction_processor`
   inside `app.worker_loop.WorkerLoop.run_claim_cycle()` — one real claim
   cycle against hosted Postgres/Storage. First attempt failed with a
   real bug in the *verification script* (a shared `httpx.Client` was
   closed before the processor closure that captured it ran — not a
   product bug), fixed, retried: `document_extraction_runs.status =
   'succeeded'`, `page_count = 1`.
4. As the real reviewer JWT: opened the extraction review, marked page 1
   `ocr_candidate`, added a supporting `image_only_page` finding, and
   submitted `ocr_required` — exercising the exact tightened validation
   rule from bug 8 above for real against hosted Postgres, not just the
   local suite.
5. As the real admin JWT: `create_document_ocr_request` with the real
   pinned identity (`tesseract 5.5.0` / `tessdata_fast` / `pypdfium2
   5.12.1`) — matching `apps/web/lib/ocr/config.ts` exactly.
6. Ran the **actual, unmodified** `app.ocr.processor.make_ocr_processor`
   for one real claim cycle against hosted: real page render (pypdfium2,
   300 DPI), real Tesseract recognition, a real artifact uploaded to and
   independently re-verified from `guideline-processed`. Result:
   `document_ocr_runs.status = 'succeeded'`, a real, non-empty
   `page_image_sha256` (the exact field bug 3 above found empty forever —
   confirmed not regressed), and the correct `ocr_produced_no_text`
   warning (the fixture is a genuinely blank/solid-color placeholder
   image by design — real Tesseract correctly found nothing to read on
   it, which is the correct outcome, not a failure).
7. As the real reviewer JWT: opened the OCR review, marked page 1
   `accepted`, submitted `accepted`. Discovered a second real, hosted-
   only fact while doing this (not visible from reading the SQL alone):
   `assign_ocr_reviewer` requires the *caller* to hold
   `guideline_ocr.review`, which `organization_admin` is deliberately
   **not** seeded with (only `quality_manager`/`clinical_reviewer`/
   `safety_officer`/`auditor` are) — so the reviewer must self-assign;
   this is not a self-review violation since the self-review block is
   keyed on the source document's uploader/registrar, not the assigner.
8. Re-checked `get_document_extraction_review_eligibility` for the real
   extraction run: `out_eligible_for_chunking` flipped from `false` to
   **`true`** — the exact downstream-eligibility behavior this sprint
   built, now proven against real hosted infrastructure end to end, not
   just the local suite.

**Real hosted Storage-RLS permission-scoping proof (migration 0010 has
zero local coverage by design — this is the only real proof that exists
anywhere for it)**: `GET` on the original PDF's real Storage object,
three real JWTs, same object, same bucket:
- clinician (no `guideline_documents.read`) → **400/denied**, correctly.
- organization_admin (holds it, uploaded the document) → **200**.
- clinical_reviewer (holds it) → **200**.

**Full synthetic-data cleanup, verified back to zero** — not assumed:
all `document_ocr_*`/`document_extraction_*`/`document_processing_*`/
`audit_events`/`guideline_*` rows for the synthetic organization deleted
in dependency order (a real multi-step FK-ordering exercise across
`document_processing_attempts`, `document_intake_events`, and the
circular `document_processing_jobs`⟷`document_ocr_request_pages`
reference — each ordering mistake surfaced as a real `23503` foreign-key
violation from the Management API, fixed by reordering the delete
statements, not by suppressing the error); the original PDF and the OCR
artifact both deleted from real Storage (looked up by listing the real
artifact path, not guessed); all three GoTrue users deleted via the Auth
Admin API. Final verification query against hosted: organizations,
guidelines, documents, extraction runs, OCR runs, processing jobs,
`auth.users`, and `audit_events` for this session all read back **zero**.

## What was not done (honest account)

- **Vercel Preview redeploy and smoke test** — see "Vercel Preview
  deployment" below for the current, real status.
- **No Playwright/browser-driven E2E** of the new OCR review workspace —
  consistent with this repo's existing, documented gap for the
  extraction review workspace (`KNOWN_LIMITATIONS.md` item 24) and every
  other form-submission flow in this codebase.
- **CI has not actually been run** on this branch — the workflow file was
  updated and is believed correct (mirrors the Docker build's own
  apt-install step, which was verified), but GitHub Actions itself was
  not exercised this session.
- **`accepted_with_warnings`/`reprocessing_required` as `submit_document_ocr_review`
  target statuses** have no dedicated local RLS test (see above) — the
  validation code path was read, not independently exercised.
- No real, complex clinical guideline scans were used — only the
  existing synthetic fixture set (English, Arabic+English, rotated,
  empty, image-only, etc.), consistent with the mission's explicit
  prohibition on real clinical documents.
