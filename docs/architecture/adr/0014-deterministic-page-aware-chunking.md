# ADR 0014: Deterministic Page-Aware Chunking

Status: Accepted
Sprint: S1-D3

Numbered 0014, not 0013 as the mission text suggested — 0013 was
already used by UX-1 (`0013-noor-brand-and-design-system-alignment.md`).
Verified against the actual repository state, not assumed from the
mission's own guess.

## Context

Sprint 1-D1/1-D2 built `get_document_page_text_readiness()`: for every
page of a succeeded extraction run, it derives exactly one canonical
text representation (native or accepted OCR) or reports the page not
ready. This sprint turns that canonical, page-level text into ordered,
provenance-preserving chunks — the hand-off point the mission has
pointed at since ADR 0012 — without yet touching embeddings, vector
storage, or retrieval, which remain explicitly out of scope.

## Decisions

### Input comes only from canonical accepted representations

The chunker never reads `document_extraction_pages`/`document_ocr_runs`
directly by client-supplied ID. It re-derives readiness by calling
`get_document_page_text_readiness()` itself (server/Worker-side, not
browser-supplied), the same authority S1-D2's eligibility function
already uses. A page with no accepted representation blocks the whole
document from becoming chunking-eligible — there is no partial-document
chunking in V1.

### One job per document, not per page or per chunk

Unlike OCR (deliberately page-scoped, ADR 0012), chunking needs
document-wide context: stable chunk ordering across pages, one coverage
proof, one canonical artifact. A page-scoped or chunk-scoped job would
need to reinvent that coordination inside the job layer instead of
using the database transaction that already provides it. `job_type =
'document_chunking'` reuses the existing generic orchestration
(`claim_next_document_processing_job`, etc., migration 0007) with zero
changes to that layer — confirmed by re-reading it, not assumed.

### The input manifest is Worker-computed, not SQL-computed

Every other canonical artifact in this codebase (extraction, OCR) is
serialized and checksummed in Python by the Worker, never in SQL — the
database's role is to atomically validate and persist Worker-computed
results, not to compute them. The input manifest follows the same
division: the Worker calls `get_document_page_text_readiness()`, reads
the actual accepted text per page, builds the canonical manifest
(sorted keys, compact separators, UTF-8), and computes
`input_manifest_sha256` itself — exactly like `build_canonical_artifact`
already does for extraction and OCR. `create_document_chunking_run`
revalidates the Worker's claimed identity against live readiness state
at run-creation time rather than trusting it blindly.

### Deterministic identity, idempotent reuse

`organization_id + source_document_id + source_sha256 +
input_manifest_sha256 + pipeline_version + configuration_version +
normalization_version + tokenizer_name + tokenizer_version` is the
complete identity. A partial unique index guarantees at most one
succeeded run per identity — the same pattern as extraction's and OCR's
identity uniqueness, one layer wider (a whole-manifest hash instead of
a single source checksum).

### Tokenizer: a pinned, deterministic technical proxy — not tiktoken

Evaluated tiktoken (BPE, real embedding-model vocabularies) against a
custom Unicode word/punctuation splitter:

| Criterion | tiktoken | `noor-simple-tokenizer` (chosen) |
|---|---|---|
| Determinism | Deterministic given a pinned encoding | Deterministic, pure regex, no external vocabulary file |
| Arabic handling | BPE merges are Latin-corpus-biased; Arabic often over-fragments | Unicode `\w`/punctuation split treats Arabic and Latin scripts identically |
| Dependency footprint | A new pinned package + vocabulary download to verify/pin | Zero new dependency — pure Python `re`, already available |
| Coupling risk | Tempting to treat its count as "the" future embedding-model token count | mission explicitly warns against this; a custom name makes the boundary explicit |
| License | MIT (fine) | N/A (in-repo code) |

**`noor-simple-tokenizer` v1** counts tokens as the number of matches of
`\w+|[^\w\s]` (Python `re`, Unicode mode) over NFC-normalized text —
each run of word characters (any script) or each non-whitespace
punctuation/symbol character is one token. This is a **technical size
proxy only** — used exclusively to bound chunk size for a future
embedding step, never labeled as "the" token count of whatever
embedding model is eventually chosen (mission §12's own explicit
warning). See `docs/domain/chunking-technical-review.md` for the exact
algorithm and worked Arabic/English examples.

### Hard page boundaries, zero overlap (V1)

A chunk never crosses a page boundary (`page_start = page_end` is an
enforced database constraint, not just a convention) and chunks never
overlap. Both are the mission's own explicitly recommended V1 policy,
adopted directly: page boundaries give exact, unambiguous citation
provenance and radically simplify coverage proof (a page's characters
are covered by exactly one ordered, non-overlapping sequence of spans);
zero overlap means no duplicated evidence and no ambiguity about which
chunk "owns" a given span. Both are documented as revisitable only
after real retrieval evaluation exists (S1-E), not a permanent
architectural ceiling.

### Deterministic block segmentation, not semantic segmentation

Blocks are detected by line/paragraph structure only: blank-line
paragraph breaks, list markers (`-`/`*`/`•`/digit-period, including
Arabic-indic digits), short unpunctuated lines as heading candidates,
and multi-line groups with repeated internal whitespace as table-like
blocks. These are **technical hints**, not a clinically validated
document structure — no block type is ever asserted to be a real
section, and none is used to justify dropping or reordering content.

### Oversized-block fallback, in strict order

Sentence boundaries (Arabic `؟`/`؛`/`.`/`!`/`?`-aware) → line boundaries
→ punctuation-safe boundaries → a last-resort tokenizer-window split.
Every fallback split records its own strategy and raises a chunk
warning — content is never silently truncated.

### Coverage and duplication are proven, not assumed

Before a chunking run is allowed to succeed, the Worker computes exact
character-level coverage and duplication across every page's canonical
text against the union of that page's chunk source spans. The default
acceptance bar is 100% coverage, 0% duplication — enforced by the
Worker raising `coverage_validation_failed`/`content_loss_detected`/
`unexpected_duplication_detected` rather than finalizing a run that
fails this proof. See `docs/domain/chunk-provenance-and-source-spans.md`.

### Chunking success ≠ chunk acceptance — the same boundary one layer deeper

Identical to ADR 0011 (extraction) and ADR 0012 (OCR): a successful
`document_chunking_runs` row only proves the pipeline ran and coverage
was proven — it says nothing about whether the resulting boundaries are
actually good for a future embedding step. `eligible_for_embedding`
only becomes true once a human technical reviewer accepts (or
accepts-with-warnings) every chunk in a `document_chunking_reviews`
round.

### Embedding boundary

This sprint stops at `eligible_for_embedding`. No embedding provider,
no vector column, no pgvector extension, no embedding computation of
any kind exists after this sprint — the boundary is a plain boolean
derived function, `get_document_embedding_readiness()`, with nothing on
the other side of it yet.

### Retrieval boundary

`eligible_for_retrieval` remains hard-coded `false` everywhere it is
returned, exactly as it has been since ADR 0011 — chunking readiness is
necessary for a future retrieval pipeline, never sufficient by itself.
