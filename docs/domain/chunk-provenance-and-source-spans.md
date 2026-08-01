# Chunk Provenance, Source Spans, and Coverage Proof

Sprint 1-D3. See ADR 0014 for the architectural rationale, and
`docs/domain/chunking-eligibility-and-lifecycle.md` for the surrounding
lifecycle.

## The offset convention

Every `document_chunk_source_spans` row records `start_character_offset`
and `end_character_offset` into the exact accepted page representation's
normalized text (native `document_extraction_pages.normalized_text` or
accepted OCR `document_ocr_runs.normalized_text`, after NFC
normalization — see "Normalization" below). The convention, stated once
here as the single source of truth:

**Zero-based, start-inclusive, end-exclusive** — identical to Python
slicing (`text[start:end]`) and to how every offset in this codebase
(extraction, OCR) has always been documented, just applied one layer
deeper.

## V1: one span per chunk

Because chunk detection tiles each page's text into contiguous,
non-overlapping blocks (see `docs/domain/chunking-technical-review.md`)
and chunks never cross a page boundary (`page_start = page_end`,
enforced as a real `check` constraint on `document_chunks`), every chunk
in V1 maps to **exactly one contiguous span of exactly one page's
text**. `document_chunk_source_spans` still exists as its own table
(rather than inlining offsets onto `document_chunks`) because the schema
is deliberately shaped for a future version where a chunk could carry
multiple spans (e.g. cross-page chunking, should that ever become
policy) — V1 just never exercises that generality.

## Normalization

`normalization_version` (currently `"1"`) pins exactly one transform:
Unicode NFC normalization, nothing else — no whitespace stripping, no
case changes, no newline collapsing. Offsets in
`document_chunk_source_spans` are always into the **NFC-normalized**
text, not the raw DB-recorded text, because NFC composition can change
character counts (e.g. a combining-character sequence collapsing into a
single precomposed character). Any future normalization change is a
`normalization_version` bump — a new deterministic identity, never a
silent change to an already-succeeded run's meaning.

## The coverage and duplication proof

Before a chunking run is allowed to succeed, two numbers are computed
and enforced as a hard gate, both by the Worker (as a first, defensive
check) and by the database (`finalize_document_chunking_run`, migration
0012 — the authoritative gate, since the Worker's own check could in
principle have a bug):

- **`coverage_percentage`** — what fraction of every page's total
  character count is covered by at least one chunk source span. Must be
  exactly `100`.
- **`duplication_percentage`** — what fraction of characters are covered
  by *more than one* span. Must be exactly `0`.

If either check fails, `finalize_document_chunking_run` raises
`coverage_validation_failed` or `unexpected_duplication_detected`
(`errcode = 'P0001'`) and the run never reaches `succeeded` — there is
no partial-success state. This is the sprint's one mandatory,
non-negotiable acceptance bar (see ADR 0014).

## Why the Worker computes coverage independently, not just trusts tiling

The block-segmentation algorithm is *designed* to tile every page's text
with zero gaps and zero overlap (`docs/domain/chunking-technical-review.md`),
which should make coverage 100% and duplication 0% by construction. The
Worker's coverage module (`app/chunking/coverage.py`) recomputes both
numbers from the actual emitted spans anyway, independently of how they
were built — this is a genuine verification pass, not a restatement of
an assumption, so a bug in segmentation is caught before
`finalize_document_chunking_run`'s own database-level gate is ever
reached, and both layers can never both be wrong in the same way at
once.

## Checksums as provenance, not as byte-identity proof of normalization

`document_chunk_source_spans.representation_checksum` is copied directly
from the accepted representation's own identity checksum
(`document_extraction_pages.page_checksum` or
`document_ocr_runs.text_checksum`) — it identifies *which* accepted
representation a span was derived from, for audit and re-verification
purposes. It is **not** a checksum of the NFC-normalized text the
chunker actually sliced (that would change if normalization_version
changes even though the underlying accepted representation did not).
`source_fragment_checksum` (a SHA-256 of the chunk's own exact text
substring) is the checksum that *does* describe the sliced content.
