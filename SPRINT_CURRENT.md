# Sprint Current: Sprint 1.2B — Deterministic PDF Page and Text Extraction

**Status:** Complete and Hosted-Verified. Local verification (Postgres 16
full suite, two genuine dual-process concurrency proofs, 91/91 Worker
pytest assertions, full web build/lint/test) and hosted Development
verification (real GoTrue JWT, real Storage, the actual unmodified Worker
code processing a real PDF end-to-end, idempotent reprocessing, trust
boundary, RLS, full synthetic-data cleanup) both green, and Vercel
Preview redeployed and healthy — see
`docs/verification/sprint-1.2b-pdf-extraction-verification.md` for the
full record.

Workstreams `S1-A`/`S1-B`/`S1-C1` closed in prior sessions. This sprint is
workstream `S1-C2` — see `MASTER_BACKLOG.md` for the reconciled
`S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D`/`S1-E` breakdown.

## Mandatory first review completed

- [x] **Security-definer schema-resolution hardening (mission §5)** —
      verified `PUBLIC`/`authenticated`/`anon` cannot `CREATE` in `public`
      (and, where it exists, `extensions`) on both environments; confirmed
      every migration-0007 orchestration function's `search_path` is
      exactly `public` or `public, extensions`, never broader; confirmed
      (again) the six Worker-only functions carry no
      `authenticated`/`anon` EXECUTE grant. Turned into a **permanent**
      regression suite (`supabase/tests/rls/007_security_hardening_review.sql`)
      rather than a one-off check, so the exact hosted-only bug found in
      Sprint 1.2A can never silently regress unnoticed.

## Objectives

- [x] Extractor selection documented — ADR 0010: `pypdf` (BSD-3-Clause)
      over the mission's suggested `PyMuPDF` (AGPL-3.0 since v1.24.1 — a
      real licensing risk for a commercial SaaS, not a capability gap)
- [x] Source integrity revalidated twice, independently — Worker-side
      streaming checksum/size/signature check, and again by
      `create_document_extraction_run()` against the registered document
      row — before any extraction begins; a mismatch produces zero
      artifact
- [x] Secure, unpredictable temp-file handling with guaranteed cleanup
      (`finally`-equivalent, verified even on early-abort paths)
- [x] Deterministic page-level extraction, text normalization, page and
      artifact checksums, technical quality metrics, conservative
      suspected-scanned detection (image-XObject-based, never OCR)
- [x] Canonical, deterministic JSON artifact — proven byte-identical
      across repeated runs of the same fixture; no timestamps in hashed
      content
- [x] Artifact uploaded privately, independently re-downloaded and
      re-hashed before being trusted as the finalized result
- [x] Atomic finalization with idempotent identity-based reuse — one
      succeeded run per `(org, source_sha256, pipeline_version,
      configuration_version, extractor_name, extractor_version)`
- [x] Extraction integrated into the existing, unchanged Sprint 1.2A
      `WorkerLoop` — `WORKER_PROCESSING_MODE=extraction`, reusing
      `document_parsing` as the job_type (not a new
      `document_extraction` value — see
      `docs/domain/document-extraction-lifecycle.md`)
- [x] Minimal UI: Extraction Summary Card, permission-gated page list,
      read-only page-detail route — no editing, no fabricated progress
- [x] Local Postgres 16 verification — full 001–008 suite green,
      including the pre-existing 001–007 suites unmodified on top of
      migration 0008
- [x] Two genuine dual-OS-process concurrency proofs — the unchanged
      1.2A claim-race proof, and a new extraction-identity race proof (5
      consecutive runs, all 4 possible race outcomes observed, zero
      unexpected errors)
- [x] Worker verification — 91/91 pytest assertions (59 pre-existing +
      32 new), `python -m compileall` clean
- [x] Hosted Development verification — migration applied, real
      end-to-end extraction with real JWTs/`service_role`, failure
      fixtures, deterministic reprocessing, tenant isolation, synthetic
      data cleaned up
- [x] Vercel Preview redeployed and confirmed healthy

## Real bugs found locally (by actually running the concurrency tests, not by reading the SQL)

1. **`finalize_document_extraction_run()` raised a raw `unique_violation`**
   when two genuinely simultaneous extraction attempts at the same
   identity both tried to mark themselves `succeeded`. Fixed with an
   exception handler that gracefully adopts the winning run instead of
   surfacing a raw constraint-violation error.
2. **A second, related race surfaced immediately after fixing the
   first**: a job superseded mid-flight (its own `create` call committed,
   but it was superseded by a different job's attempt before it reached
   `finalize`) raised a raw "not running" error. Fixed by explicitly
   detecting the supersession case and either adopting an
   already-succeeded winner or raising a clear, named, retryable error —
   never a raw, unclassified exception. Both fixes re-verified together
   across 5 consecutive concurrency-script runs.

See `docs/database/deterministic-pdf-extraction-schema.md` for the full
technical account.

## A real hosted-only test-execution finding (not a product bug)

Running the SQL test suite against hosted required the Supabase
Management API's SQL query endpoint (no direct Postgres connection string
held for the hosted project), which batches an entire multi-statement
submission differently than `psql -f`'s per-statement autocommit — a
`begin/rollback` block not preceded by its own fresh commit can unwind
earlier, otherwise-successful statements in the same batch. This surfaced
as a false failure in `008_pdf_extraction.sql`'s original TEST 15/15b.
Fixed in the committed test file by switching to the same bare-`DO`-block
role-switch pattern already proven safe by TEST 16 in the same file — no
product/RLS defect involved; re-verified locally with zero regression.
See `docs/verification/sprint-1.2b-pdf-extraction-verification.md`.

## Explicitly out of scope this task (per the mission)

OCR, table reconstruction, image extraction, clinical section
classification, semantic/fixed-size chunking, embeddings, retrieval,
reranking, LLM calls, human correction UI, knowledge activation based on
extraction. The pipeline stops at immutable, deterministic, page-level
extraction artifacts and technical metrics.

## Next sprint

```text
Begin Sprint 1-D — Extraction Review, OCR Decision, and Deterministic Chunking
```

See `MASTER_BACKLOG.md` (S1-D).
