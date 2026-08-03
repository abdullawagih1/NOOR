# Sprint Current: S1-E2 — Embedding and Vector Index Foundation

**Status:** S1-E2 — Complete and Verified. See
`docs/verification/sprint-1-e2-embedding-and-vector-verification.md` for
the full record, including two real schema bugs found and fixed, a real
verification-tooling fixture bug found and fixed, a real CSS bug found
and fixed, and an honestly documented small residual of hosted synthetic
test data left as a manual cleanup item.

Workstreams `S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D1`/`S1-D2`/`S1-D3`/`S1-E1`/
`UX-1`/`UX-1.1` closed in prior sessions. This sprint is workstream
`S1-E2`.

## What this sprint does

Turns S1-D3's accepted, embedding-ready chunks into immutable,
checksum-verified vectors under one approved, self-hosted embedding
configuration (`noor-multilingual-e5-base-v1` — `intfloat/multilingual-e5-base`,
MIT-licensed, 768 dimensions, cosine distance), stores them in
tenant-scoped `pgvector` tables, builds one approved HNSW index, adds a
second `Retriever` implementation (`noor-vector-baseline-v1`) to S1-E1's
existing evaluation framework, validates the index against an exact
sequential-scan reference path, evaluates the vector baseline against
S1-E1's frozen human judgments, and compares it honestly against the
lexical baseline (regressions reported, never hidden). See ADR 0016 for
the full architectural rationale, including the real disk-space blocker
resolved with the user before any embedding code was written.

## Explicitly out of scope this sprint

Hybrid retrieval, reciprocal-rank fusion, reranking, cross-encoders, LLM
calls, query rewriting/expansion, generative answers, citation
generation, production/clinician-facing search, automated model
selection, multiple simultaneous production providers, real clinical
document ingestion, regulatory/clinical validation claims.

## Objectives

- [x] Provider/model evaluation spike (self-hosted vs. external,
      grounded and cited) — `intfloat/multilingual-e5-base` selected,
      revision-pinned against the live Hugging Face Hub API.
- [x] ADR 0016.
- [x] Migration 0016 — `pgvector` extension (schema-qualified
      consistently across local/hosted), `embedding_configurations`
      (one seeded, approved row), `document_embedding_runs`,
      `document_chunk_embeddings` (fixed `vector(768)` column, HNSW
      index), Worker-only chunk-embedding functions, `document_embeddings.*`
      permissions, RLS.
- [x] Migration 0017 — `retrieval_evaluation_query_embeddings`,
      `get_vector_search_candidates` (one function, exact/indexed modes),
      `create_vector_evaluation_run`/`create_query_embeddings_for_dataset`,
      extended `retrieval_evaluation_runs`/`_metrics`/`_failures` for the
      vector baseline — `finalize_retrieval_evaluation_run` and friends
      reused completely unmodified.
- [x] CI workflow updated to `pgvector/pgvector:pg16` (plain `postgres:16`
      has no `vector` extension binary).
- [x] Local RLS/SQL suite `014_embedding_and_vector_evaluation.sql` —
      16/16, on a genuinely fresh container.
- [x] Worker `app/embedding/*` (provider adapter wrapping the real
      pinned model, identity, checksums, manifest, pipeline, processor,
      query-embedding processor) and `app/retrieval/vector_pipeline.py`
      (exact-vs-indexed comparison, reusing S1-E1's metrics/failure-
      analysis/artifact code unmodified).
- [x] Worker pytest — 206/206 (51 new, including 4 tests that load and
      run the real pinned model).
- [x] Quality workspace UI: `/quality/embeddings`,
      `/quality/embeddings/configuration`, `/quality/embeddings/runs/[runId]`,
      plus vector-aware extensions to the existing S1-E1 dataset/run/
      failure pages and a new lexical-vs-vector comparison page.
- [x] Web verification — typecheck/lint/21 test files/build all clean.
- [x] 9 documentation files (ADR + 2 domain + database + security + 2
      operations + verification), all cross-referenced.
- [x] Hosted verification against the real "Noor Development" project,
      using the real Worker code and the real pinned model — chunk
      embeddings, query embeddings, and a vector evaluation run all
      succeeded end to end; RLS/trust-boundary checks passed.
- [x] Playwright screenshots — 9/9, all real hosted data, including a
      real CSS overlap bug found and fixed during capture.
- [x] Status docs updated (this file, PROJECT_STATE, MASTER_BACKLOG,
      CHANGELOG, KNOWN_LIMITATIONS, SECURITY, README).

## Real bugs found and fixed this sprint

1. `document_processing_jobs_subject_check` was never extended for the
   new `document_embedding` job type in migration 0016's first draft —
   would have rejected every embedding-job insert with a CHECK
   violation. Caught by the local RLS suite before any hosted attempt.
2. `get_vector_search_candidates` had a `real`/`numeric` return-type
   mismatch (the pgvector `<=>` cosine-distance operator returns `real`).
   Caught by the same local suite run.
3. `retrieval_evaluation_queries.query_sha256` (migration 0014, already
   shipped) was never actually populated by
   `freeze_retrieval_evaluation_dataset` — a real, pre-existing gap with
   no prior consumer until this sprint's query-embedding pipeline tried
   to read it. Worked around, not edited around: the checksum is now
   computed fresh from canonical `query_text` in migration 0017's own
   functions.
4. A real CSS overlap bug on the embedding-run detail page: two
   64-character checksum values shared a 2-column grid cell with no
   `break-all`, visually colliding. Found during Playwright screenshot
   capture (the automated typecheck/lint/build suite doesn't catch
   visual overlap); fixed with `sm:col-span-2` + `break-all`.
5. A real bug in this sprint's own hosted-verification tooling (not
   product code): the ad hoc hand-rolled PDF fixture used since Sprint
   0.5 cannot correctly carry Arabic text through `pypdf`'s single-byte
   string decoding — multi-byte UTF-8 characters silently corrupt to
   double-encoded mojibake. Diagnosed by direct byte inspection, fixed
   for future verification scripts (`reportlab` + a Unicode TTF font +
   pre-reversing the source string to compensate for `pypdf`'s RTL
   extraction order), but not re-run to completion against hosted
   infrastructure before this sprint's time budget ended — see the
   verification doc's "what remains open" section.

## Next step

```text
Begin S1-E3 — Hybrid Retrieval
```

Do not mark S1-E3 or S1-F complete. See `MASTER_BACKLOG.md` for the full
workstream breakdown.
