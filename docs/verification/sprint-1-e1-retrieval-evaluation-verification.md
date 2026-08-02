# Sprint 1-E1 Verification — Retrieval Preparation and Evaluation Foundation

## Starting state for this session

Sprint 1-D3 (deterministic page-aware chunking) was complete and verified.
This sprint (`S1-E1`) built the retrieval evaluation foundation: a frozen
evaluation-dataset lifecycle, a versioned 17-category query taxonomy,
graded relevance judgments, a deterministic lexical baseline
(`noor-lexical-baseline-v1`), versioned metrics, deterministic failure
analysis, provider-independent retrieval contracts, and a Quality
workspace UI — with zero embeddings, zero vector storage, zero external
AI calls anywhere. See ADR 0015 for the full design rationale.

## Real bugs found and fixed this session

1. **`claim_next_document_processing_job` could never claim a
   dataset-scoped job.** Migration 0007's original eligibility check
   required every claimable job to resolve `source_document_id` to a
   `registered` `guideline_source_documents` row — true for every job
   type until `retrieval_evaluation` (dataset-scoped,
   `source_document_id is null`). Without a fix, every evaluation job
   would sit `queued` forever. Caught by the local RLS suite
   (`013_retrieval_evaluation.sql` TEST 7) before any hosted attempt.
   Fixed by re-declaring the function in migration 0015 with one added
   eligibility branch for `dataset_id`/`frozen` datasets — the same
   "extend a prior migration's function via `create or replace`, one
   layer over" pattern migration 0013 already used for
   `reopen_extraction_review`.
2. **`get_retrieval_candidates` had a `real`/`numeric` return-type
   mismatch.** `ts_rank_cd()` returns Postgres `real`; the function's
   declared output column was `numeric`. Fixed with an explicit
   `::numeric` cast. Also caught by the local RLS suite before any
   hosted attempt.
3. **Two hosted-only `search_path` bugs** (invisible on local plain
   Postgres, where `pgcrypto` was installed directly into `public` by
   migration 0001; on hosted Supabase `pgcrypto` lives in the
   `extensions` schema — the same fact migration 0007's
   `assert_lease_owner`/`claim_next_document_processing_job` already
   documented for `gen_random_bytes()`/`digest()`): `freeze_retrieval_
   evaluation_dataset` (migration 0014) and `create_retrieval_
   evaluation_run` (migration 0015) both call `digest()` directly to
   compute checksums/identity hashes but were missing `extensions` in
   their `search_path`. Both failed with `function digest(bytea,
   unknown) does not exist` on the first real hosted freeze/run attempt.
   Fixed by adding `extensions` to both functions' `search_path`.
4. **Web: a real ordering bug in `toRetrievalEvaluationError`.** A
   generic `raw.includes("immutable")` catch-all was checked *before*
   the more specific "a failure annotation's core content is immutable"
   case, so the specific case was unreachable dead code — every
   failure-annotation-immutability error was mapped to the generic
   `"immutable"` code instead of `"failure_content_immutable"`. Caught
   by `tests/retrieval-evaluation-errors.test.ts`; fixed by reordering
   the specific check before the generic one.
5. **A test-expectation bug**, not a product bug: an early draft of
   `retrieval-evaluation-schemas.test.ts` asserted `z.coerce.boolean()`
   would coerce the *string* `"false"` to `false` — it does not (`Boolean("false")
   === true`, standard JS coercion). The real server action never hits
   this path (it resolves a real boolean before calling the schema).
   Fixed the test to assert against a real `false` value and documented
   the coercion gotcha inline.
6. **Two synthetic-fixture SHA-256 collisions** while writing the new
   local RLS test file, both matching a documented recurring class of
   bug from Sprint 1-D3 (content-addressed extraction identity is keyed
   on `source_sha256`, not `source_document_id`): the fixture first used
   `repeat('e', 63) || '1'`, already used by `009_extraction_review.sql`;
   then `repeat('9', 63) || '1'`, already used by
   `011_controlled_ocr.sql`. Both caused the new fixture to silently
   reuse an unrelated prior test file's already-succeeded extraction run
   (and its pages), producing a duplicate-key error at the finalize
   step. Fixed by using an unused `repeat('r', 63) || '1'` (confirmed via
   a repo-wide grep before use).

None of these were caught by writing the code carefully the first time —
every one surfaced by actually running the local test suite, then actually
running the hosted end-to-end script, exactly the discipline this
session's own mission repeatedly calls for ("verify early, verify for
real, do not fabricate results").

## Local database verification — real Postgres 16, fresh container

Migrations 0001-0015 applied cleanly, in order, on a genuinely fresh
`postgres:16` Docker container (recreated from scratch, not reused,
immediately before the final verification pass). `supabase/seed.sql`
loaded cleanly. The full RLS/SQL test suite (`001` through `013`, 12
files — `010` does not exist, matching this codebase's own established
numbering gaps) passed in full:

| File | Assertions |
|---|---|
| `001_tenant_isolation.sql` | 8 |
| `002_auth_hardening.sql` | 7 |
| `003_guideline_registry.sql` | 28 |
| `004_g12_self_approval_regression.sql` | 5 |
| `005_document_intake.sql` | 20 |
| `006_processing_orchestration.sql` | 25 |
| `007_security_hardening_review.sql` | 5 |
| `008_pdf_extraction.sql` | 19 |
| `009_extraction_review.sql` | 41 |
| `011_controlled_ocr.sql` | 27 |
| `012_deterministic_chunking.sql` | 17 |
| `013_retrieval_evaluation.sql` (new) | 12 |
| **Total** | **214** |

`013_retrieval_evaluation.sql` builds a real 3-chunk accepted document
(English/Arabic/unrelated content, reusing the exact fixture-construction
pattern from `012_deterministic_chunking.sql`) and exercises, end to end:
draft dataset creation and corpus/query/judgment authoring; freeze
rejection before `ready_for_review`; the two-person review rule
(creator blocked from self-review, then a distinct reviewer succeeds);
freeze producing deterministic checksums and immutable search
representations, and idempotent replay; a clinician denied
`create_retrieval_evaluation_run`, then a real run created and
idempotently reused while active; the Worker-only trust boundary
(context read + English/Arabic/negative-control lexical candidate
recall all behave correctly, and every Worker-only function is
unreachable from `authenticated`); `finalize_retrieval_evaluation_run`
persisting immutable results/metrics; run-identity reuse for an
already-succeeded run; RLS read-gating; and failure-annotation
create/update with immutable core content.

This suite was re-run in full a second time, on another genuinely fresh
container, after fixing the two hosted-only `search_path` bugs (bug #3
above) — confirming the fix is purely additive and changes no local
behavior.

## Worker verification — real Python, no mocked scoring/metrics logic

`apps/worker/app/retrieval/*` (config, tokenizer, scoring, retriever,
metrics, failure_analysis, checksums, artifact, errors, pipeline,
processor) plus extensions to `orchestration_client.py` (4 new Worker-only
RPC wrappers), `settings.py` (`retrieval_evaluation` processing mode),
and `main.py` (wiring). 155/155 Worker pytest tests passed (114
pre-existing + 41 new), with zero regressions:

- `test_retrieval_scoring.py` — hand-computed `final_score` formula
  proofs, token-coverage/exact-phrase-match correctness, and
  deterministic tie-break ordering (including order-independence).
- `test_retrieval_metrics.py` — hand-computed Precision/Recall/Hit
  Rate/MRR/nDCG against fixed fixtures, plus the negative-control
  exclusion rule.
- `test_retrieval_failure_analysis.py` — one fixture per system-detectable
  failure category, plus a check that at most one category is ever
  emitted per query.
- `test_retrieval_retriever.py` — `LexicalRetriever` unit tests against a
  fake in-memory candidate fetcher (no network/database access).
- `test_retrieval_pipeline.py` — byte-identical-artifact determinism
  across repeated runs, correct top-1 hits for English/Arabic exact
  queries, and correct RPC payload shapes.
- `test_retrieval_processor.py` — end-to-end processor tests against a
  fake `OrchestrationClient` and a mocked Storage HTTP layer (success,
  dataset-no-longer-frozen, no-active-queries, candidate-fetch failure,
  finalize failure).

A real logic bug was caught and fixed during test-writing: `_non_relevant_
ranked_high` in `failure_analysis.py` had its condition inverted (it
would fire whenever there was *no* hit in the top-K, which is the
opposite of its intended meaning — "a relevant item WAS retrieved but is
outranked by a non-relevant item at rank 1"). Caught before any test was
even run, by re-reading the detector against its own docstring while
writing the fixture for it.

## Web application layer — built and verified this session

`apps/web/lib/retrieval-evaluation/*` (queries, schemas, actions, errors,
ui) and five new routes under `/quality/retrieval-evaluation/*` (dataset
queue, dataset detail, judgment workspace, run dashboard, failure
analysis), gated by 11 new permissions
(`RETRIEVAL_EVALUATION_*` in `lib/auth/permissions.ts`), following the
exact conventions already established by `lib/chunking/*` and
`/reviewer/chunking/*`. Verified clean:

- `tsc --noEmit` — 0 errors.
- `next lint` — 0 warnings, 0 errors.
- All 19 web test files (17 pre-existing + 2 new
  `retrieval-evaluation-{schemas,errors}.test.ts`) — 100% passing, run
  directly via `tsx` (bypassing `npm run`, which was independently found
  to hang indefinitely on this session's machine — see "Environment note"
  below).
- `next build` — clean production build; all 5 new routes appear
  correctly in the route table.

## Environment note: `npm run` hangs on this machine

Both `npm run test --workspace=apps/web` and (in earlier sprints) other
`npm run` invocations were observed to hang indefinitely on this specific
session's Windows/Git-Bash environment, producing zero output even after
many minutes, before any test's own output appeared — indicating the hang
is inside `npm`'s own CLI startup (most plausibly its background
update-check network call) and not in any test or build logic. Confirmed
by running the exact same underlying commands directly
(`npx tsx <file>`, `npx next build`) instead of through the `npm run`
wrapper — both completed normally in seconds. Documented here so a future
session does not re-diagnose the same false "something is hanging" signal.

## Hosted Development verification — real, end-to-end

Migrations 0014/0015 applied to the real hosted "Noor Development"
Supabase project via the Management API. All 9 new tables confirmed
present. Real GoTrue users created (never fabricated sessions): a
`clinical_reviewer` (for the upstream extraction/chunking technical
review chain) and two distinct `quality_manager` users (to exercise the
two-person dataset-review rule for real). A real 3-page PDF (English
exact-phrase / Arabic exact-phrase / unrelated content) was uploaded and
processed through the **actual, unmodified** Worker code
(`OrchestrationClient`, `WorkerLoop`, `make_extraction_processor`,
`make_chunking_processor`, `make_retrieval_evaluation_processor`) exactly
as a production Worker would, end to end:

- Real extraction (3 pages, succeeded) → real extraction review
  (accepted) → real chunking (3 chunks, 100% coverage / 0% duplication)
  → real chunk technical review (accepted) → 3 real
  `eligible_for_embedding=true` chunks.
- Real dataset created (`quality_manager` A), 3 corpus items added, 3
  queries authored (`english_exact`, `arabic_exact`, `negative_control`),
  judgments recorded, submitted for review.
- Real two-person review: `quality_manager` B (a distinct user) marked it
  reviewed; `quality_manager` A froze it — real `dataset_sha256` and
  manifest checksums computed and persisted.
- A real evaluation run created and processed by the actual, unmodified
  `retrieval_evaluation` Worker processor: **succeeded**, with a real
  artifact checksum recorded.
- The English exact-phrase query correctly ranked its expected chunk
  first (`is_hit = true`, `relevance_grade = 3`). The negative-control
  query correctly returned zero candidates (no false positive).
  Overall metrics correctly excluded the negative control from every
  aggregate (`sample_size = 2`, not 3).
- The Arabic query returned zero candidates in this specific hosted run
  — attributable to the ad hoc verification script's synthetic PDF using
  a Latin-only base font (Helvetica) for the Arabic content stream,
  which `pypdf` cannot reliably extract as real Arabic Unicode text; this
  is a limitation of the *verification script's* hand-built PDF, not of
  the retrieval-evaluation feature — Arabic normalization and lexical
  matching are separately and rigorously proven correct by
  `013_retrieval_evaluation.sql` (which inserts real, directly-verified
  normalized Arabic text, bypassing PDF text extraction entirely) and by
  the Worker's own pytest suite. The system's own deterministic
  failure-detection pipeline correctly and honestly surfaced this as a
  `query_too_narrow` failure — exactly the behavior it is designed to
  produce, not a crash or a silently fabricated match.
- Real Quality workspace UI screenshots captured via Playwright, signed
  in as a real `quality_manager` user against this real hosted data (not
  a mock): dataset queue, dataset detail, judgment workspace, run
  dashboard, and failure analysis (desktop, 1440×1000); run dashboard
  (mobile, 390×844); and a structural RTL simulation of the dataset
  detail page (real Arabic query text renders correctly; layout mirrors
  correctly) — all under `docs/verification/screenshots/sprint-1-e1/`.

### Cleanup — real, verified zero-residual

All synthetic content created across all verification attempts (3
distinct run suffixes, including two earlier attempts that failed before
the `search_path` fixes above) was deleted: the full guideline →
extraction → chunking chain, the full retrieval-evaluation dataset →
run → results/metrics/failures chain (temporarily disabling the
relevant immutability triggers for this cleanup only, then re-enabling
them immediately after — the same discipline
`docs/verification/sprint-1-d3-chunking-verification.md` established),
9 synthetic GoTrue users (with their `audit_events` rows removed first,
via the documented `noor.allow_audit_maintenance` override, to satisfy
the FK constraint), and 7 orphaned Storage objects (2 source PDFs, 2
chunking artifacts, 2 extraction artifacts, 1 evaluation artifact) across
`guideline-originals` and `guideline-processed`. Final confirmation
query: **zero** synthetic users, **zero** orphan memberships, **zero**
matching datasets/guidelines, **zero** matching Storage objects remain.

## CI

CI's `Supabase` job applies every file under `supabase/migrations/*.sql`
and runs every file under `supabase/tests/rls/*.sql` unmodified — no
workflow changes were needed for the two new migrations/one new test
file to be picked up automatically.

## What was not done (honest account)

- No embeddings, no embedding-provider selection, no vector columns, no
  `pgvector`, no vector similarity queries, no external AI calls, no
  reranking, no RRF/hybrid retrieval, no query rewriting/expansion, no
  LLM calls, no RAG, no citation/answer generation, no production search
  endpoint, no automated/LLM-generated relevance judgments — all
  explicitly out of scope per the mission and ADR 0015.
- The `VectorRetriever`/`HybridRetriever`/`RerankerRetriever` Protocol
  stubs in `app/retrieval/retriever.py` declare the contract shape only;
  nothing behind them is implemented.
- The hosted end-to-end script's Arabic-query miss (see above) was not
  "fixed" by hand-crafting a font-embedded PDF — that would test the
  verification script's own PDF-generation fidelity, not the product,
  and Arabic correctness is already proven at the level that actually
  matters (real normalized text, real FTS, real Worker scoring).
- Only one deterministic lexical baseline exists
  (`noor-lexical-baseline-v1`); no second baseline for comparison.
