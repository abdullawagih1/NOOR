# Sprint Current: Sprint 1-D2 — Controlled Page-Scoped OCR

**Status:** Complete and verified — locally, on hosted Development, and
on a real Vercel Preview deployment (build `Ready`, CI green on
`main`). The one gap left is a real browser-rendered check of the
Preview URL, blocked by this Vercel team's own SSO Deployment
Protection — see
`docs/verification/sprint-1-d2-controlled-ocr-verification.md` for the
full, honest account.

Workstreams `S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D1` closed in prior
sessions. This sprint is workstream `S1-D2` — see `MASTER_BACKLOG.md` for
the reconciled `S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D1`/`S1-D2`/`S1-D3`/`S1-E`
breakdown.

## Governing principle

OCR execution success and OCR technical acceptance are two independent
facts, exactly as S1-D1 established for extraction. OCR is page-scoped —
only the pages a human reviewer explicitly flagged `ocr_candidate` are
ever rendered or sent to the OCR engine, never a whole document — and
never overwrites the deterministic native extraction it supplements.

## Objectives

- [x] Permission-scoped Storage hardening — `guideline-originals`/
      `guideline-processed` `SELECT` now require an explicit permission
      (`guideline_documents.read` / `guideline_extractions.read_artifacts`
      / `guideline_ocr.read_artifacts`), not mere organization membership
      — migration `0010_permission_scoped_storage_access.sql`, closing
      the residual risk S1-D1 documented.
- [x] OCR eligibility derived exclusively from explicit review evidence
      (`document_extraction_page_reviews.review_status = 'ocr_candidate'`)
      — never client-supplied, never from a technical heuristic alone.
- [x] One controlled OCR request per extraction-review round, one durable
      processing job per eligible page (not one document-wide job) —
      migration `0011_controlled_page_scoped_ocr.sql`.
- [x] Deterministic page rendering (`pypdfium2`) and self-hosted OCR
      (`tesseract`, no cloud API) — see ADR 0012 for the selection
      rationale against the mission's own criteria.
- [x] OCR identity fully pinned (organization + source checksum +
      extraction run + page + native page checksum + renderer identity +
      rendered-image checksum + provider identity + model identity + OCR
      config + language hints), idempotent reuse enforced by a partial
      unique index, verified end-to-end including the reuse path.
- [x] OCR results and native extraction kept as separate, independently
      provenanced representations; `get_document_page_text_readiness()`
      is the one place that derives which representation is canonical
      per page — the underlying rows are never merged.
- [x] OCR technical review, structurally separate from execution status,
      with the same self-review block and reopen/invalidate semantics S1-D1
      established for extraction review, plus a new cascade: reopening the
      extraction review now invalidates any still-active dependent OCR
      request, not just future request creation.
- [x] Downstream chunking eligibility correctly derived for the
      `ocr_required` path (every requested page must have an accepted
      representation); retrieval eligibility remains hard-coded `false`.
- [x] Local Postgres 16 verification — full 001–011 suite green across
      four genuinely fresh containers (25 OCR assertions in 011, plus a
      tightened, cross-sprint-consistent `submit_document_extraction_review`
      rule bringing 009 to 41/41).
- [x] Worker verification — 79/79 pytest assertions, including real
      (non-mocked) rendering and Tesseract recognition against English/
      Arabic/mixed-language synthetic fixtures, plus a real Docker-image
      build-and-run smoke test.
- [x] Web application UI — OCR request status on the guideline detail
      page, an OCR review queue (`/reviewer/ocr`), and a side-by-side
      review workspace (`/reviewer/ocr/[ocrReviewId]`) comparing the
      original page, native extraction, and OCR result. Lint/typecheck/
      build all clean; 136/136 test assertions (33 new).
- [x] Hosted Development verification — real GoTrue JWTs, a real upload,
      real extraction, real page-scoped OCR execution (Tesseract +
      pypdfium2 against real Storage), a real downstream chunking-
      eligibility flip, and a real permission-scoped Storage RLS proof;
      all synthetic hosted data verified deleted back to zero afterward.
- [x] Vercel Preview redeploy — deployment `Ready`
      (`noor-pe7sql42t-abdullah-wagihs-projects.vercel.app`), build log
      confirms both new routes in the production route table. A real
      browser-rendered check is blocked by this team's own Vercel SSO
      Deployment Protection and remains the one open item.

## A prior session's work found non-functional, not merely incomplete

This session began by auditing in-progress, uncommitted work from an
earlier Claude Code session (schema, Worker module, and an initial ADR
already existed but had never been documented or verified). The audit
found the Worker module could not even be imported
(`app/ocr/processor.py` called a function that does not exist in
`pipeline.py`), and a follow-on trace found the OCR-run identity was
being recorded with a permanently empty image checksum — see
`docs/verification/sprint-1-d2-controlled-ocr-verification.md` for the
full account of these and six other real bugs (plus one real,
hosted-only permission-model fact) found and fixed this session, none of
which were assumed away.

## Explicitly out of scope this task (per the mission)

Document-wide automatic OCR, multiple OCR providers/failover, handwriting
recognition, table reconstruction, form understanding, manual text
correction, chunk generation, embeddings, retrieval, reranking, LLM calls,
clinical interpretation or evidence grading, automatic guideline
activation, and any mutation of `document_extraction_pages`/
`document_extraction_runs` (both remain exactly as immutable as S1-D1
left them).

## Next sprint

```text
Begin Sprint 1-D3 — Deterministic Page-Aware Chunking
```

See `MASTER_BACKLOG.md` (S1-D2/S1-D3).
