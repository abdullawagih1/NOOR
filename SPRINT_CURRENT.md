# Sprint Current: S1-D3 — Deterministic Page-Aware Chunking

**Status:** S1-D3 — Complete and Verified. See
`docs/verification/sprint-1-d3-chunking-verification.md` for the full
record.

Workstreams `S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D1`/`S1-D2`/`UX-1`/`UX-1.1`
closed in prior sessions. UX-1.1 was accepted by the user before this
sprint began (this sprint's own mission brief recorded it as "Complete
and Visually Accepted"). This sprint is workstream `S1-D3`.

## What this sprint does

Turns canonical, accepted per-page text
(`get_document_page_text_readiness()`, migration 0011) into
deterministic, page-aware chunks with exact provenance, immutable chunk
records, a private canonical JSON artifact, human technical chunk
review, and a derived `eligible_for_embedding` boolean. See ADR 0014
for the full architectural rationale.

## Explicitly out of scope this sprint

Embeddings, embedding-provider selection, vector columns/pgvector,
full-text search, retrieval, reranking, RAG, clinical Q&A, LLM calls of
any kind, semantic/generative chunking, table reconstruction, clinical
section classification, chunk text editing, cross-document/cross-
guideline chunks, real clinical documents.

## Objectives

- [x] Migration 0012 — `document_chunking_runs`/`document_chunks`/
      `document_chunk_source_spans`, `create_document_chunking_job`,
      Worker-only run creation/finalization/failure functions, the
      mandatory 100%-coverage/0%-duplication gate, seven new
      `guideline_chunking.*` permissions, RLS.
- [x] Migration 0013 — `document_chunking_reviews`/
      `document_chunk_reviews`/`document_chunk_findings`/
      `document_chunking_review_events`, the full review lifecycle,
      `get_document_embedding_readiness()`, and the extraction-review
      reopen/invalidate cascade extended to invalidate dependent
      chunking runs.
- [x] ADR 0014 (renumbered from the mission's suggested 0013, which
      UX-1 already used — verified against the actual repository state).
- [x] Worker chunking pipeline (`apps/worker/app/chunking/*`):
      `noor-simple-tokenizer` v1, deterministic block segmentation, the
      strict oversized-block fallback cascade, coverage/duplication
      verification, canonical artifact construction and upload.
- [x] Web application layer (`apps/web/lib/chunking/*`) and UI
      (`/reviewer/chunking` queue + workspace, guideline detail page
      integration).
- [x] Documentation set (domain, database, security, operations,
      verification).
- [x] Full local verification — RLS suite (202/202), Worker pytest
      (149/149), Web typecheck/test/lint/build.
- [x] Hosted Development verification and cleanup.

## Real bugs found and fixed this sprint

1. A Worker-only function would have called permission-gated helper
   functions (`get_document_page_text_readiness`,
   `get_document_extraction_review_eligibility`) that always reject
   `service_role`'s `auth.uid()`-less JWT — caught before any test ran,
   fixed with a dedicated Worker-only context function.
2. Migration 0013's `reopen_extraction_review` override was drafted from
   the wrong base (migration 0009's original, not migration 0011's
   already-cascade-extended version) — would have silently reverted the
   OCR-request invalidation cascade. Caught only by a full, fresh-
   container 001–013 suite run, not the new file in isolation.
3. `information_schema.roles` used instead of the established `pg_roles`
   pattern in both new migrations — caught by the first migration-apply
   attempt.
4. A chunking-run-creation parameter ordering bug that would have broken
   every native-only (non-OCR) chunking run via PostgREST.
5. A block-boundary-tiling bug and a chunk-grouping bug in the Worker's
   segmentation/bin-packing logic, both caught by the Worker's own unit
   tests before any database was involved.

## Next step

```text
Begin S1-E — Retrieval Preparation and Evaluation Foundation
```

See `MASTER_BACKLOG.md` for the full workstream breakdown.
