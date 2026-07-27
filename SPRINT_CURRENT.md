# Sprint Current: Sprint 1-D1 — Extraction Review and Technical Quality Gate

**Status:** Complete and Hosted-Verified. Local verification (Postgres 16
full suite across multiple genuinely fresh containers, full web
build/lint/typecheck/test) and hosted Development verification (real
GoTrue JWTs, the actual unmodified Worker code producing the underlying
extraction, real PostgREST RPC calls exercising the full review
lifecycle, real signed-Storage-access verification, full synthetic-data
cleanup) both green, and Vercel Preview redeployed and healthy — see
`docs/verification/sprint-1-d1-extraction-review-verification.md` for
the full record.

Workstreams `S1-A`/`S1-B`/`S1-C1`/`S1-C2` closed in prior sessions. This
sprint is workstream `S1-D1` — see `MASTER_BACKLOG.md` for the reconciled
`S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D1`/`S1-D2`/`S1-D3`/`S1-E` breakdown.

## Governing principle

"Extraction execution succeeded" and "extraction quality is accepted" are
two independent facts. This sprint adds the second: a human, auditable,
page-aware technical quality decision that gates future OCR and chunking
eligibility, without ever mutating the deterministic extraction artifact
itself.

## Objectives

- [x] Review lifecycle fully separate from execution status — new
      `document_extraction_reviews.review_status` (8 values), migration
      `0009_extraction_review_quality_gate.sql`
- [x] Review rounds, not edits — at most one active round per run
      (partial unique index), submitted rounds immutable except the one
      legal `accepted(-with-warnings) -> invalidated` transition
- [x] One generalized findings table (page-level and document-level),
      23-value controlled taxonomy, 4 severities, immutable core content,
      no deletion ever
- [x] Explicit per-page review coverage — opening a page is never
      inferred as review; 100% coverage required before any of the 5
      terminal decisions
- [x] All 5 decisions (`accepted`, `accepted_with_warnings`,
      `ocr_required`, `reprocessing_required`, `rejected`)
      database-enforced inside one transactional
      `submit_document_extraction_review()` function, re-validated under
      lock regardless of client state
- [x] Downstream eligibility (`eligible_for_ocr`/`eligible_for_chunking`/
      `eligible_for_retrieval`) server-derived, never a client-writable
      column
- [x] Self-review blocked at the database level (uploader/registerer of
      the source document cannot review its own extraction) — documented
      V1 policy, not a full quorum system
- [x] Reviewer assignment, self-claim, and reassignment, each verifying
      the target actually holds review permission
- [x] Short-lived signed original-PDF access — no service-role key, same
      principle as the Sprint 1.1 upload flow
- [x] Review queue + side-by-side review workspace UI (PDF panel,
      extracted-text panel, page navigation, findings panel, decision
      form) — permission-gated throughout
- [x] Separate permission namespace
      (`guideline_extraction_reviews.*`/`guideline_extraction_findings.*`/
      `guideline_extraction_source.*`) reinforcing the architecture
      boundary from outside the schema too
- [x] Local Postgres 16 verification — full 001–009 suite green, run
      against **multiple genuinely fresh containers** (not a reused one)
      from the start
- [x] Web build/lint/typecheck/test all clean, including new routes
- [x] Hosted Development verification — migration applied, real
      end-to-end review with real JWTs, cross-tenant/clinician denial,
      synthetic data cleaned up
- [x] Vercel Preview redeployed and confirmed healthy

## Applying Sprint 1.2B's lesson from the start, not rediscovering it

Sprint 1.2B found — via an actual CI failure on a genuinely fresh
Postgres container, not by reading the SQL — that a migration's own
guarded `grant ... to authenticated` block is a documented no-op at CI's
migration-apply time (the role doesn't exist yet), and that the
corresponding RLS test file must issue its own explicit grant. That exact
grant was written at the top of `009_extraction_review.sql` from the
start, and the full suite was verified against multiple genuinely fresh
`postgres:16` containers (not the same reused container across
iterations) before being trusted — the discipline that lesson was
supposed to produce.

## A real bug found only while cleaning up synthetic hosted data

`prevent_extraction_finding_delete()`'s first version had no
maintenance-override escape hatch at all — inconsistent with every other
append-only table in this codebase, and it meant synthetic finding rows
could never be removed again, not even as the connecting superuser.
Fixed by adding the same `noor.allow_audit_maintenance` override GUC
check used everywhere else; hotfixed directly on hosted, corrected in
the migration file, re-verified locally. See
`docs/verification/sprint-1-d1-extraction-review-verification.md`.

## Explicitly out of scope this task (per the mission)

OCR execution, OCR-provider selection, chunk generation, embeddings,
retrieval, reranking, LLM calls, manual text editing/correction, a
human-corrected-text artifact, clinical interpretation or evidence
grading, and any mutation of `document_extraction_runs` /
`document_extraction_pages` (both remain exactly as immutable as Sprint
1.2B left them).

## Next sprint

```text
Begin Sprint 1-D2 — Controlled OCR Eligibility and OCR Processing Foundation
```

See `MASTER_BACKLOG.md` (S1-D2).
