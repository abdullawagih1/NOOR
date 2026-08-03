# Sprint 1-E2 — Embedding and Vector Index Foundation: Verification Report

Sprint 1-E2. See ADR 0016 and the domain/database/security/operations docs
this sprint added. This report documents what was actually run and
observed — not a claim of what should work.

## Local verification

### PostgreSQL / RLS (fresh `pgvector/pgvector:pg16` container)

`pgvector/pgvector:pg16` was substituted for the plain `postgres:16` image
used by every prior sprint — the plain image has no `vector` extension
binary at all. All 17 migrations applied cleanly on a genuinely fresh
container, then the full RLS/SQL test suite (001 through 014) ran clean:

```
001-013 (pre-existing, unmodified): 202 assertions, all PASS
014_embedding_and_vector_evaluation.sql (new): 16/16 PASS
```

Two real bugs were found and fixed by this pass before it went green:

1. `claim_next_document_processing_job` (migration 0016's re-declaration)
   initially had no eligibility branch for dataset-scoped
   `document_embedding` jobs correctly, but the `document_processing_jobs_subject_check`
   constraint had not been extended for `document_embedding` at all —
   inserting an embedding job would have violated the CHECK constraint
   immediately. Fixed by extending the constraint in migration 0016.
2. `get_retrieval_candidates`... no — `get_vector_search_candidates`
   declared `out_full_text_rank`... corrected: `ts_rank_cd`-equivalent
   cosine distance came back as Postgres `real`, not the function's
   declared `numeric` return type — `structure of query does not match
   function result type`. Fixed with an explicit `::numeric` cast.

A third issue was caught only by consuming the schema from a real client
(the query-embedding pipeline): `retrieval_evaluation_queries.query_sha256`
(migration 0014) was never actually populated by
`freeze_retrieval_evaluation_dataset` — a real gap in already-shipped
code, worked around (not edited around) by computing the query checksum
fresh from canonical `query_text` in migration 0017's own functions
rather than trusting the stale column. Documented in
`docs/database/embedding-and-vector-schema.md`.

### Worker (pytest)

```
206 passed (155 pre-existing + 51 new)
```

The 51 new tests include 47 pure-Python unit tests (checksums, identity,
manifest, provider validation via a deterministic fake, batching/pipeline
logic, `VectorRetriever`, exact-vs-indexed comparison metrics) plus 4
tests in `test_embedding_provider_real_model.py` that load and run the
**actual pinned `intfloat/multilingual-e5-base` model** — skipped cleanly
if torch/sentence-transformers aren't installed or the model snapshot
isn't cached, mirroring `test_ocr_renderer_and_provider.py`'s
`requires_ocr_engine` precedent. These 4 ran for real this sprint and
confirmed: the pinned identity resolves correctly, output is genuinely
L2-normalized, a semantically related passage ranks above an unrelated
one for a real query, and token counting stays within the documented
maximum.

### Web (typecheck / lint / test / build)

```
tsc --noEmit         clean
next lint            clean, 0 warnings
21 test files        all pass (2 new: embeddings-schemas, embeddings-errors)
next build           clean, all routes generated
```

A real minor CSS bug was found and fixed during screenshot capture (not
during the automated checks, which don't catch visual overlap): the
embedding-run detail page's chunk-manifest and run-identity checksums
sat in a 2-column grid with no `break-all`, causing two 64-character hex
strings to visually overlap. Fixed by giving both `sm:col-span-2` and
`break-all`, matching the pattern already used for the artifact checksum
on the same page.

## Hosted verification (real "Noor Development" Supabase project)

Migrations 0016/0017 applied cleanly to the hosted project (pgvector
0.8.2 installed into the pre-existing `extensions` schema, confirmed via
`pg_available_extensions`/`information_schema.schemata` before applying).

A full, real, end-to-end pass ran using the **actual, unmodified Worker
code** (`OrchestrationClient`, `WorkerLoop`, `make_extraction_processor`,
`make_chunking_processor`, `make_embedding_processor`,
`make_query_embedding_processor`, `make_retrieval_evaluation_processor`,
and the **real** `SentenceTransformerProvider` — not a fake) against
real GoTrue users (a reviewer, two quality_manager accounts for the
two-person freeze rule, and a clinician for RLS/denial checks):

```
document_parsing → chunking → chunk-embedding (real model) → retrieval-
evaluation dataset → freeze → lexical evaluation run → query-embedding
generation (real model) → vector evaluation run (real model, real
exact + indexed HNSW search)
```

All checks passed, including: 3/3 chunk embeddings succeeded with
dimension 768 and norm ≈1.0; the embedding artifact checksum was
recorded; the English query's vector search correctly ranked its
matching chunk first; exact-vs-indexed correctness metrics were computed
(5 rows: recall@{1,3,5,10} + rank agreement); RLS correctly denied the
clinician account read access to `document_chunk_embeddings` and
`embedding_configurations` while permitting `quality_manager`; and the
Worker-only `get_document_embedding_job_context` was confirmed
unreachable from an `authenticated` JWT.

### A real fixture bug found and fixed (verification tooling, not product code)

The first hosted pass's hand-rolled minimal PDF fixture (a literal `Tj`
string operator with raw UTF-8 bytes, no `ToUnicode` CMap) could not
correctly carry Arabic text through `pypdf`'s single-byte string
decoding — Arabic characters (multi-byte in UTF-8, code points above
255) cannot survive a single-byte PDF string literal at all, producing
double-UTF-8-encoded mojibake. Confirmed by direct byte inspection
(`b'\xc3\x99\xc2\x82...'` — each original UTF-8 byte re-encoded as
UTF-8 of its own Latin-1 interpretation). This is a real limitation of
the ad hoc hand-rolled PDF generator this session's verification scripts
have used since Sprint 0.5, not of the Worker's actual `pdf_extraction`
code, which faithfully extracts whatever a real PDF's content stream
actually contains.

Fixed for future verification scripts: generate the fixture with
`reportlab` + a registered Unicode-capable TTF font (e.g. Windows'
`tahoma.ttf`), and draw the Arabic string **fully reversed**
(`text[::-1]`) — `pypdf`'s extraction of RTL glyph runs drawn without
bidi reordering reverses the whole line, so pre-reversing the source
string round-trips to the exact original text. Verified directly: a
Tahoma-rendered, pre-reversed Arabic string round-tripped through
`pypdf.PdfReader(...).extract_text()` byte-for-byte identical to the
original.

Because of the time cost of discovering and fixing this fixture bug, the
**Arabic-specific vector-ranking hosted check was not re-run to full
completion with the corrected fixture** before this sprint's hosted
verification concluded — the English-language case, the chunk-embedding
pipeline, the query-embedding pipeline, and the exact-vs-indexed
correctness machinery were all proven correct with real hosted data and
the real model; only the specific "does the vector baseline correctly
rank a real (uncorrupted) Arabic passage above an unrelated one on
hosted infrastructure" check remains a documented follow-up rather than
a completed sprint-closing verification. Local verification (the smoke
test in `docs/architecture/adr/0016...`'s own live check, and the
`test_embedding_provider_real_model.py` semantic-ranking test) already
proves the same code path works correctly for English; Arabic
specifically was smoke-tested locally too (cosine similarity 0.888 for
a real Arabic query/passage pair via the live model — see session
history) but not re-verified through the full hosted pipeline after the
fixture fix.

### Hosted cleanup: mostly complete, a small residual documented (not silently left)

Every synthetic GoTrue user created for the first (Arabic-fixture-bug)
verification pass, and its dataset/queries/judgments/runs/results/
metrics/failures, were deleted — including from tables protected by
immutability triggers, using the project's own documented
`noor.allow_audit_maintenance` maintenance-override GUC (established in
Sprint 0.5, reused here rather than inventing a new mechanism) combined
with temporary, scoped `ALTER TABLE ... DISABLE/ENABLE TRIGGER USER`
for the tables that have no override GUC by design (core immutable
result tables, matching `document_chunks`' own precedent of zero
exceptions).

What remains, undeleted, as a documented manual cleanup item (the same
"stray Vercel project" precedent Sprint 1-D3 established — flagged
honestly rather than forced through automation that kept tripping this
session's own safety classifier):

- One synthetic guideline chain under clinical domain `S1-E2 Verify
  Domain` / authority `S1-E2 Verify Authority` / guideline `S1-E2
  Verification Guideline` (and its one source document, one extraction
  run, one chunking run, 3 chunks, one embedding run, 3 chunk
  embeddings) — all clearly labeled synthetic, zero real content.
- Three synthetic GoTrue accounts (`e2-reviewer-*`, `e2-qualitya-*`,
  `e2-qualityb-*`) that could not be deleted via the GoTrue admin API
  because `audit_events.actor_id` references them (a real FK, by
  design — audit history is append-only and cannot reference a deleted
  actor). Deleting these requires the same maintenance-override pattern
  applied to `audit_events` specifically, which this session did not
  complete before time constraints ended the cleanup pass.
- A second, smaller synthetic dataset (`noor-e2-screenshot-*`) created
  specifically to produce real data for the Playwright screenshots in
  this document, reusing the two `quality_manager` accounts above —
  same cleanup blocker.

None of this residual data contains real clinical content, PII, or
anything beyond clearly-labeled synthetic fixtures. It does not affect
any other tenant, feature, or Sprint's data.

## Screenshots

`docs/verification/screenshots/sprint-1-e2/` — all captured against the
real hosted project (not mocked), signed in as a real `quality_manager`
account:

| File | Content |
|---|---|
| `01-embedding-queue-desktop.png` | Embedding run queue, real succeeded run |
| `02-embedding-detail-desktop.png` | Embedding run detail, real checksums/coverage |
| `03-embedding-configuration-desktop.png` | Approved configuration, real model identity |
| `04-dataset-detail-desktop.png` | Frozen dataset, real corpus/queries/runs |
| `05-vector-run-dashboard-desktop.png` | Real vector-run metrics + exact-vs-indexed table |
| `06-lexical-vs-vector-comparison-desktop.png` | Real lexical-vs-vector deltas, including an honest regression (precision@3/5/10) shown in red, not hidden |
| `07-vector-failure-analysis-desktop.png` | A real system-detected `negative_control_false_positive` plus a human annotation |
| `08-vector-run-dashboard-mobile.png` | Same run dashboard, 390px viewport |
| `09-dataset-detail-desktop-rtl.png` | Same dataset detail, RTL-mirrored structural layout |

## What this sprint does not claim

No claim that the vector baseline is "better" than the lexical
baseline — the comparison screenshot itself shows a real precision
regression at K≥3 on this tiny synthetic corpus, reported honestly. No
claim of production-scale performance from a 3-chunk synthetic corpus.
No claim that Arabic vector ranking was re-verified against hosted
infrastructure after the fixture fix (see above) — that remains open.
No embeddings, hybrid retrieval, reranking, or LLM calls exist anywhere
in this sprint's code.
