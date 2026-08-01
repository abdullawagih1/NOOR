# Deterministic Chunking Algorithm and Technical Review

Sprint 1-D3. See ADR 0014 for why each design choice was made this way
rather than another.

## The tokenizer: `noor-simple-tokenizer` v1

A deterministic, dependency-free technical size proxy
(`apps/worker/app/chunking/tokenizer.py`) — **never** the token count of
any real embedding model. Counts tokens as the number of regex matches
of `\w+|[^\w\s]` (Unicode mode) over NFC-normalized text: each run of
"word" characters (any script, so Arabic and Latin are treated
identically) or each non-whitespace punctuation/symbol character is one
token. See ADR 0014's comparison table against tiktoken for why this was
chosen instead. `TOKENIZER_VERSION` is part of a chunking run's
deterministic identity — changing the regex or normalization step
requires a version bump.

## Block segmentation (technical hints only)

`detect_blocks()` (`apps/worker/app/chunking/segmentation.py`) splits one
page's normalized text into blocks by line/paragraph structure only:

- **Blank-line paragraph breaks** — consecutive non-blank lines form one
  group; the surrounding blank-line whitespace is absorbed into the
  boundary between adjacent blocks (never dropped, never double-counted
  — see "Tiling guarantee" below).
- **List markers** — `-`, `*`, `•`, `digit.`/`digit)`, including
  Arabic-indic digits (`٠-٩`). A group where every line matches becomes
  one `list_item` block per line (finer chunk granularity for lists).
- **Heading candidates** — a single short line (≤80 characters) with no
  terminal sentence punctuation.
- **Table-like blocks** — 2+ lines each containing 2+ runs of multiple
  whitespace or a tab character.
- Everything else is `paragraph`.

**No block type is ever asserted to be real document structure.** These
are technical hints recorded on each chunk (`block_type_summary`) purely
to help a future reviewer or embedding step, never used to justify
dropping, reordering, or reinterpreting content, and never claimed as
table reconstruction or clinical section identification.

### Tiling guarantee

`detect_blocks()` always returns blocks that tile the **entire** input
text with zero gaps and zero overlap, including blank lines — this is
what makes the coverage proof possible without a separate "fill the
gaps" pass. Each block's start is exactly the previous block's end (a
single forward pass assigns boundaries; each side is never computed
independently, which is what caused a real overlap bug caught during
this sprint's own local verification and fixed before release).

## Oversized-block fallback (strict order)

A block exceeding `HARD_MAXIMUM_CHUNK_TOKENS` (800) is split by
`split_oversized_block()`, trying each strategy in order and recursing
until every fragment is small enough:

1. **Sentence boundary** — after `. ! ? ؟ ؛` plus whitespace (Arabic and
   Latin sentence-ending punctuation).
2. **Line boundary** — after `\n`.
3. **Punctuation-safe boundary** — after `, ; : ،` plus whitespace.
4. **Tokenizer-window** (last resort) — binary-searches the largest
   prefix that stays within the hard maximum, preferring to cut at the
   nearest preceding space. Guaranteed to terminate (every step consumes
   at least one character) — this is the fallback of last resort, never
   silent truncation.

Every fragment produced this way carries a `split_reason`, surfaced as a
`hard_split:<reason>` warning on the resulting chunk(s) — reviewers can
see exactly which chunks were forced apart and how.

## Chunk assembly: greedy bin-packing, not "one block = one chunk"

`expand_and_group_blocks()` (`apps/worker/app/chunking/chunker.py`)
greedily accumulates blocks toward `TARGET_CHUNK_TOKENS` (400), only
flushing early if the *soft* target would be exceeded and the group is
already at or above `MINIMUM_CHUNK_TOKENS` (50), or if the *hard*
maximum (800) would be exceeded (checked unconditionally, regardless of
the group's current size). A block produced by the oversized-block
fallback is **not** forced into its own standalone chunk — it is
re-packed alongside neighboring blocks exactly like any other block, so
a large paragraph with no natural breaks still produces reasonably-sized
chunks instead of one chunk per forced fragment (a real design flaw
caught and fixed during this sprint's own testing).

## Hard page boundaries, zero overlap (V1)

A chunk never crosses a page boundary and chunks never overlap — both
enforced as real database constraints (`document_chunks.page_start =
page_end`; disjoint, coverage-complete spans per page), not just
convention. See ADR 0014 for why this was chosen for V1 and when it
might be revisited.

## The chunk technical review (migration 0013)

A `document_chunking_reviews` round requires every chunk to be marked
(`mark_chunk_reviewed`: `reviewed_clear` / `reviewed_with_findings` /
`rechunk_candidate` / `rejected`) before `submit_document_chunking_review`
accepts a final decision:

- **`accepted`** — zero open critical or major findings.
- **`accepted_with_warnings`** — zero open critical findings, requires a
  `warning_summary`.
- **`rechunk_required`** — requires at least one supporting finding and
  a `decision_reason`.
- **`rejected`** — requires a `decision_reason` and at least one major
  or critical finding.

Findings (`document_chunk_findings`) use a chunking-specific type
taxonomy (`boundary_splits_sentence`, `heading_detached`,
`oversized_chunk`, `arabic_boundary_issue`, `hard_split_required`, etc.
— see `apps/web/lib/chunking/queries.ts`'s `CHUNK_FINDING_TYPES` for the
full list) distinct from extraction's and OCR's own finding
taxonomies, since the failure modes at this layer are different (boundary
quality, not recognition or parsing quality).
