# Sprint Current: S1-E1 — Retrieval Preparation and Evaluation Foundation

**Status:** S1-E1 — Complete and Verified. See
`docs/verification/sprint-1-e1-retrieval-evaluation-verification.md` for
the full record.

Workstreams `S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D1`/`S1-D2`/`S1-D3`/`UX-1`/
`UX-1.1` closed in prior sessions. This sprint is workstream `S1-E1`.

## What this sprint does

Builds the reproducible foundation every future retrieval approach
(lexical, embedding, hybrid, reranked) will be measured against: frozen
evaluation corpora, a versioned 17-category query taxonomy, graded (0-3)
relevance judgments, a two-person dataset review/freeze lifecycle, one
deterministic lexical baseline (`noor-lexical-baseline-v1`, real
PostgreSQL full-text search + a documented ranking formula + deterministic
tie-breaking), versioned Precision/Recall/Hit-Rate/MRR/nDCG metrics,
deterministic + human failure analysis, provider-independent `Retriever`
contracts, and an internal Quality workspace UI. See ADR 0015 for the
full architectural rationale.

## Explicitly out of scope this sprint

Embeddings, embedding-provider selection/credentials, vector columns,
`pgvector`, vector similarity queries, external AI calls, reranking,
cross-encoders, RRF/hybrid retrieval, query rewriting/expansion via AI,
LLM calls, RAG, citation/answer generation, production search, automated
or LLM-generated relevance judgments, real guideline ingestion,
regulatory/clinical validation claims.

## Objectives

- [x] Migration 0014 — dataset lifecycle (`retrieval_evaluation_datasets`/
      `_corpus_items`/`_queries`, `retrieval_relevance_judgments`,
      `retrieval_evaluation_search_documents`), `normalize_retrieval_text()`,
      the full draft→ready_for_review→frozen→archived lifecycle with
      two-person review, 11 new `retrieval_evaluation.*` permissions, RLS.
- [x] Migration 0015 — `retrieval_evaluation_runs`/`_results`/`_metrics`/
      `_failures`, `document_processing_jobs` extended for dataset-scoped
      jobs, the client-facing run/cancel/failure-annotation functions, and
      the Worker-only context/candidate-recall/finalize/fail functions.
- [x] ADR 0015.
- [x] Worker retrieval module (`apps/worker/app/retrieval/*`): scoring,
      deterministic tie-breaking, metrics, failure analysis, artifact
      construction, and the `retrieval_evaluation` processor — 155/155
      Worker pytest tests passing (114 pre-existing + 41 new).
- [x] Web application layer (`apps/web/lib/retrieval-evaluation/*`) and UI
      (`/quality/retrieval-evaluation/*`: dataset queue, dataset detail,
      judgment workspace, run dashboard, failure analysis).
- [x] Documentation set (4 domain docs, 1 database doc, 1 security doc,
      2 operations docs, 1 verification doc — 9 total).
- [x] Full local verification — RLS suite (214/214), Worker pytest
      (155/155), Web typecheck/lint/test(19 files)/build all clean.
- [x] Hosted Development verification (real Worker, real two-person
      review, real frozen dataset, real lexical run, real Playwright
      screenshots) and zero-residual cleanup.

## Real bugs found and fixed this sprint

1. `claim_next_document_processing_job` could never claim a dataset-scoped
   `retrieval_evaluation` job — migration 0007's original eligibility
   check assumed every job resolves to a `source_document_id`. Caught by
   the local RLS suite before any hosted attempt; fixed via a migration
   0015 re-declaration adding a dataset/frozen eligibility branch.
2. `get_retrieval_candidates` had a `real`/`numeric` return-type mismatch
   (`ts_rank_cd()` returns `real`) — caught by the same local suite run.
3. Two hosted-only `search_path` bugs: `freeze_retrieval_evaluation_dataset`
   and `create_retrieval_evaluation_run` both call `digest()` directly but
   were missing `extensions` in their `search_path` — invisible locally
   (pgcrypto lives in `public` there), real on hosted Supabase (pgcrypto
   lives in `extensions`). Caught by the first real hosted freeze/run
   attempt; fixed and re-verified locally + on hosted.
4. A real ordering bug in the web error-mapper (`toRetrievalEvaluationError`):
   a generic "immutable" check shadowed a more specific failure-annotation
   check below it. Caught by the new web error-mapping test file.
5. A real logic-inversion bug in `_non_relevant_ranked_high` (Worker
   failure-analysis detector) — caught before any test ran, by re-reading
   the detector against its own docstring.
6. Two synthetic-fixture SHA-256 collisions while writing the new local
   RLS test file, reusing hashes already used by `009`/`011` — the same
   documented "content-addressed identity is keyed on hash, not row id"
   gotcha from Sprint 1-D3, recurring here.

## Next step

```text
Begin S1-E2 — Embedding and Vector Index Foundation
```

Do not mark S1-E2, S1-E3, or S1-F complete. See `MASTER_BACKLOG.md` for
the full workstream breakdown.
