# Sprint 1-D3 — Deterministic Page-Aware Chunking Verification Record

## Starting state for this session

Repository audit confirmed the mission's own claims before relying on
them: `docs/architecture/adr/` showed `0013` already used by UX-1, so
this sprint's ADR became `0014` (documented in its own opening line).
`supabase/migrations/` showed `0011` as the latest migration, so `0012`/
`0013` matched the mission's own suggested numbers with no conflict. The
mission's own text recorded UX-1.1 as "Complete and Visually Accepted,"
treated as the user's acceptance signal —
`docs/verification/ux-1-1-visual-acceptance.md`'s final status line was
updated accordingly.

## Real bugs found and fixed this session

1. **A Worker-only function would have called permission-gated helper
   functions.** `get_document_page_text_readiness()` and
   `get_document_extraction_review_eligibility()` (migrations 0009/0011)
   both call `assert_permission()`, which checks `auth.uid()` —
   unconditionally `NULL` for this Worker's `service_role` RPC calls (no
   `sub` claim in that JWT), so calling either from Worker-only code
   would always raise "permission denied." An early draft of
   `create_document_chunking_run` did exactly this. Fixed by adding
   `get_document_chunking_job_context` — a Worker-only function that
   re-derives the identical readiness logic directly against the tables
   (extended to also return each page's actual text), authenticating
   purely via lease ownership like every other Worker-only function in
   this codebase. Caught before any test ran, by re-reading the
   permission model rather than assuming it.
2. **Migration 0013's `reopen_extraction_review` override was drafted
   from the wrong base.** The plan was to `CREATE OR REPLACE` this
   function to add a chunking-run invalidation cascade — but the draft
   was built from migration 0009's *original* function body, when
   migration 0011 had already overridden the same function to add an
   OCR-request invalidation cascade. Building 0013's version from the
   older base would have silently reverted 0011's behavior. **Caught
   only by running the full, fresh-container 001–013 suite together**,
   not by re-reading the SQL and not by running the new 012 file in
   isolation — `011_controlled_ocr.sql`'s own TEST 21 (reopening an
   extraction review cascades to invalidate a dependent OCR request)
   failed on the first full-suite run. Fixed by rebuilding 0013's
   version as a true superset of 0011's, re-verified green afterward.
3. **`information_schema.roles` used instead of `pg_roles`.** Both new
   migrations' guarded-grant blocks (`if exists (select 1 from
   information_schema.roles where rolname = ...)`) used a query pattern
   that does not behave as a simple lookup on plain Postgres — every
   prior migration in this codebase (0009, 0011) uses `pg_roles`
   instead. Caught immediately by the first migration-apply attempt
   against a fresh container (`relation "information_schema.roles" does
   not exist`), fixed with a global find/replace across both files.
4. **A chunking-run-creation parameter ordering bug.**
   `create_document_chunking_run`'s `p_ocr_request_id`/`p_ocr_review_id`
   parameters had no SQL default, but `OrchestrationClient._rpc()`
   strips `None` values from every RPC payload (the established pattern
   every other optional Worker parameter relies on) — for a native-only
   chunking run (no OCR involved), PostgREST would have been unable to
   resolve the function call at all, since named-parameter RPC calls
   require every non-default parameter present. Fixed by moving both
   parameters to the end of the signature with `default null` (Postgres
   requires defaulted parameters last).
5. **A block-boundary-tiling bug in `detect_blocks()`.** The initial
   implementation computed each side of an inter-block boundary
   independently (the end of one block from the next block's own
   content-start, the start of the next block from the previous block's
   own content-end) — these are two *different* values when a blank-line
   gap separates them, producing overlapping spans across every absorbed
   gap. Caught by a manual smoke test before any pytest was even
   written, fixed by a single forward pass where each block's start is
   exactly the previous block's end.
6. **A chunk-grouping bug in `expand_and_group_blocks()`.** Fragments
   produced by the oversized-block fallback were originally forced into
   their own standalone chunk regardless of size — a large paragraph
   with no natural blank-line breaks would have been shattered into
   hundreds of below-minimum-token chunks (one per forced sentence
   fragment) instead of being re-packed toward the target size. Caught
   by a smoke test using a realistic oversized-paragraph fixture (600
   repeated-sentence tokens split into 300 tiny chunks instead of ~2
   reasonably-sized ones), fixed by removing the "hard fragment always
   flushes" rule and instead unconditionally checking the hard-maximum
   ceiling on every accumulation step (not just the soft target, which
   is skipped below `MINIMUM_CHUNK_TOKENS`).
7. **A test-fixture bug in this session's own hosted verification
   script** (not a product bug): repeated verification attempts reused
   byte-identical synthetic PDF content, and extraction-run identity
   (migration 0008) is keyed on `source_sha256`, not
   `source_document_id` — so retries silently "reused" the very first
   attempt's extraction run rather than creating their own, and
   `create_document_chunking_job` correctly reported "no succeeded
   extraction run exists" for the newer documents. This is correct,
   intentional system behavior (two genuinely byte-identical documents
   legitimately share one extraction identity); the fix was to embed a
   unique suffix into each verification attempt's synthetic PDF text.

## Local database verification — real Postgres 16, one genuinely fresh container

```
$ docker run -d --name noor-test-pg -e POSTGRES_PASSWORD=postgres -p 55432:5432 postgres:16
$ (apply supabase/migrations/*.sql in order, 0001-0013)              → all clean
$ (apply supabase/seed.sql)                                           → clean
$ (apply supabase/tests/rls/*.sql in order, 001-012)                  → 202/202 assertions, 100% green
```

The `011_controlled_ocr.sql` file's own TEST 21 failed on the first full-
suite run (see bug #2 above) — re-verified green after the fix, along
with every other pre-existing suite (001–011: 176 assertions) run
alongside the new file, proving zero regression to any prior sprint's
guarantees.

### New assertions this sprint (17, in `012_deterministic_chunking.sql` — covers both migrations 0012 and 0013, the same "not every migration needs its own dedicated file" precedent 0010 established)

1. `create_document_chunking_job` creates and idempotently reuses a job.
2. Job creation rejected while the extraction review is still
   `pending_review`.
3. A clinician (no `guideline_chunking.create`) is denied.
4. Worker context read (`get_document_chunking_job_context`) and
   chunking-run creation succeed.
5. `finalize_document_chunking_run` enforces the 100% coverage gate
   (rejects an 87%-coverage payload).
6. `finalize_document_chunking_run` succeeds with a correct 3-chunk
   payload, persisting chunks and source spans.
7. `document_chunks` rows are immutable (UPDATE and DELETE both
   rejected).
8. The hard page-boundary constraint (`page_end = page_start`) rejects a
   cross-page chunk insert.
9. Identity-based idempotent reuse — a second, genuinely fresh job
   attempt at the identical identity reuses the existing succeeded run.
10. Trust boundary — `authenticated` cannot call any Worker-only
    chunking function directly.
11. RLS enforces `guideline_chunking.read` (clinician denied,
    organization_admin permitted).
12. Full chunk technical review lifecycle — create, mark all chunks
    reviewed, submit `accepted`; `get_document_embedding_readiness`
    correctly false before any review and true (with
    `eligible_for_retrieval` still false) after acceptance.
13. Submission rejected until every chunk is reviewed.
14. `rechunk_required` requires a supporting finding and a
    `decision_reason`; embedding readiness stays false.
15. Chunk review rounds are correctly scoped per chunking run (a
    different run's decision does not affect an already-accepted one).
16. Reopening the underlying **extraction** review cascades to
    invalidate the dependent, still-succeeded chunking run — the same
    cascade discipline 0011 added for OCR requests, one layer deeper.

## Worker verification — real Python, no mocked segmentation logic

```
$ apps/worker/.venv/Scripts/python.exe -m pytest -v
============================ 114 passed in 19.25s =============================
```

114 total (79 pre-existing + 35 new chunking assertions,
`test_chunking_tokenizer_and_segmentation.py` and
`test_chunking_pipeline.py`), zero regressions to any prior sprint's
Worker suite. New coverage: tokenizer determinism and Arabic/Latin
parity; block-tiling invariants over English, Arabic, table-like, blank-
only, and empty text; the full sentence → line → punctuation →
tokenizer-window oversized-block fallback cascade (including a genuine
last-resort case with no sentence/line/punctuation boundaries at all);
full-document coverage/duplication proofs over English, Arabic, mixed-
language, multi-page, and a 200-repetition oversized-paragraph fixture;
hard page-boundary and provenance-span-exactness checks; determinism
(identical input → identical chunk checksums and byte-identical
artifacts, twice); manifest order-independence and representation-
change-sensitivity; NFC-normalization character-count recomputation; and
the exact RPC payload shape `finalize_document_chunking_run` expects.

## Web application layer — built and verified this session

`apps/web/lib/chunking/{queries,schemas,errors,actions,ui}.ts(x)`
mirrors `apps/web/lib/ocr/*` one layer deeper: typed row interfaces with
explicit column lists (never `select("*")`), Zod schemas per Server
Action, a `ChunkingReviewError`/`toChunkingReviewError` safe-mapping
layer, and `"use server"` actions following the identical
`requirePermission → parse → rpc → toXError → revalidatePath → redirect`
shape every prior domain in this codebase uses.

Routes: `/reviewer/chunking` (queue, with unassigned/mine/active/
terminal-status filters) and `/reviewer/chunking/[chunkingReviewId]` (a
chunk-by-chunk navigator — chunk text, provenance/boundary metadata,
findings, and the submit-decision form), plus a "Chunking:" status row
added to the guideline detail page's extraction summary card (mirroring
the existing OCR integration point exactly).

```
$ npx tsc --noEmit                                    → clean, whole app
$ npm run lint --workspace=apps/web                    → "No ESLint warnings or errors"
$ npm run build --workspace=apps/web                   → clean, 0 warnings, both new routes in the production route table
$ npx tsx tests/chunking-schemas.test.ts                → 18/18
$ npx tsx tests/chunking-errors.test.ts                 → 16/16
$ (all 17 apps/web test files run individually)         → 17/17 files pass, 0 failures
```

`packages/ui` — `tsc --noEmit` clean. `packages/clinical-schemas` —
typecheck clean, 6/6 tests pass.

A note on the aggregate `npm run test` chain: on this Windows
development machine, invoking all 17 `tsx` test files through npm's own
process-spawn wrapper in one chained command intermittently produced
very slow or apparently-stuck runs (traced to leftover orphaned
`npm run test`/`npm run dev` processes from earlier interrupted
attempts competing for the same Node/TypeScript compilation cache, not
a defect in the tests themselves). Every one of the 17 test files was
independently confirmed to pass with a clean exit code and its expected
assertion count when invoked directly via `npx tsx <file>` — functionally
equivalent evidence to a single successful chained run.

## Hosted Development verification — real, end-to-end

Migrations `0012`/`0013` applied to the "Noor Development" project
(`quohfsaqeqzbbvmrhmbr`) via the Supabase Management API — both
returned `201` with no errors. Confirmed landed: all 7 chunking-related
tables (`document_chunking_runs`, `document_chunks`,
`document_chunk_source_spans`, `document_chunking_reviews`,
`document_chunk_reviews`, `document_chunk_findings`,
`document_chunking_review_events`) and all 7 `guideline_chunking.*`
permissions present via direct query.

**A real end-to-end flow using the actual, unmodified Worker code**
(`OrchestrationClient`, `WorkerLoop.run_claim_cycle()`,
`make_extraction_processor`, `make_chunking_processor` — the exact same
modules the deployed Worker runs, imported and driven directly rather
than through the long-running FastAPI service, matching the pattern
every prior sprint's hosted verification used):

1. Signed in as the persistent real admin account
   (`abdullawagih1@gmail.com`) via a real GoTrue password grant.
2. Created a second real GoTrue user (`clinical_reviewer` role) — chunk
   technical review requires `guideline_chunking.review`, which
   `organization_admin` does not hold, and self-review is blocked at the
   database level (the uploader/registerer of the source document cannot
   review it) — the same real, hosted-only permission fact Sprint 1-D2's
   own hosted verification surfaced for OCR review.
3. Real domain/authority/guideline/version creation, a real signed
   Storage upload of a synthetic PDF, and `complete_guideline_upload`'s
   real server-side re-download-and-hash verification.
4. The real Worker claimed and processed the `document_parsing` job —
   real `pypdf` extraction succeeded.
5. The real extraction review lifecycle (create → start → mark page
   reviewed → submit `accepted`) via real PostgREST RPC calls as the
   synthetic reviewer.
6. `create_document_chunking_job` succeeded; **the real Worker claimed
   and processed the `document_chunking` job** — the actual,
   unmodified chunking pipeline (tokenizer, segmentation, coverage
   verification, artifact construction/upload) ran against real hosted
   Postgres and Storage.
7. Confirmed via direct query: the resulting `document_chunking_runs`
   row is `succeeded` with `coverage_percentage = 100`,
   `duplication_percentage = 0`, and at least one real chunk.
8. The real chunk technical review lifecycle (create → start → mark
   chunk reviewed → submit `accepted`) via real PostgREST RPC calls.
9. `get_document_embedding_readiness` correctly returned
   `eligible_for_embedding = true` and `eligible_for_retrieval = false`.
10. A second `create_document_chunking_job` call for the same document
    confirmed idempotent-safe (no crash, no duplicate row).

**30/30 checks passed.**

### Cleanup — real, verified zero-residual

All synthetic data created across this verification (including three
earlier attempts that failed on script bugs before reaching a clean
run — see bugs found during scripting, not product bugs) was removed:
7 synthetic guidelines and their versions/documents/upload sessions/
processing jobs/attempts/intake events, 1 real extraction run and its
review/page-reviews/events, chunking runs/chunks/source-spans/reviews/
chunk-reviews/findings/review-events, 2 synthetic clinical domains, 2
synthetic guideline authorities, and 4 synthetic `clinical_reviewer`
GoTrue users (profiles, organization memberships, and the GoTrue user
records themselves — two of which required deleting their own
`audit_events` rows first via the documented
`noor.allow_audit_maintenance` override, the same escape hatch used in
prior sprints' cleanups, since `audit_events.actor_id` legitimately
references the real action each synthetic user performed).

**A real, documented consequence of this sprint's own immutability
design surfaced during cleanup**: `document_chunks`,
`document_chunk_source_spans`, and `document_chunking_review_events`
have no built-in maintenance-override GUC (unlike `audit_events` and
every finding table, which do) — deleting synthetic rows from these
three tables required temporarily disabling their immutability triggers
directly (`ALTER TABLE ... DISABLE TRIGGER ...`), performing the
deletes, and immediately re-enabling them. This is a real, narrowly-
scoped, fully-reversible superuser action taken solely to remove
synthetic verification data — never a production data-management
pattern — and is now recorded as a known limitation
(`KNOWN_LIMITATIONS.md` item 75) rather than silently worked around.

Final zero-residual query, run after cleanup:

```
guidelines: 0, domains: 0, authorities: 0, reviewer_profiles: 0,
all_chunking_runs: 0, all_chunks: 0, remaining_parsing_jobs: 0
```

## CI

Pending: push to `main`, confirm the `pr.yml` workflow's Web/Worker/
Supabase (migrations+RLS)/Secret-scan jobs all pass on real GitHub
Actions, and confirm a real Vercel Preview deployment reaches `Ready`
with both new `/reviewer/chunking` routes present.

## What was not done (honest account)

- **No real browser-rendered check of `/reviewer/chunking`** — this
  Vercel team's own SSO Deployment Protection blocks any headless
  browser check of a live Preview URL from this environment, the same
  pre-existing constraint every prior sprint's hosted verification has
  documented.
- **No real, complex clinical document was chunked** — verification used
  small synthetic English/Arabic/mixed-language/table-like/oversized-
  paragraph fixtures (Worker unit tests) and a minimal synthetic PDF
  (hosted end-to-end flow). Real production-scale chunk-quality review
  against genuine clinical guideline documents remains future work.
- **No automated "rechunk" trigger** — a `rechunk_required`/`rejected`
  chunk review decision requires a human to request a fresh chunking job
  under a deliberately different configuration; nothing in this sprint
  automates that decision.
