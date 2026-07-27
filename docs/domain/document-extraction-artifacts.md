# Document Extraction — Artifact Format, Normalization, and Checksums (Sprint 1.2B)

Source: `apps/worker/app/pdf_extraction/{artifact,normalization,checksums}.py`.

## Canonical JSON artifact

One artifact per succeeded extraction run — `document_extraction_runs`
carries the artifact fields directly (`artifact_bucket`, `artifact_path`,
`artifact_sha256`, `artifact_size_bytes`, `artifact_media_type`); no
separate `document_processing_artifacts` table exists this sprint
(mission §11.3 explicitly allowed this: "avoid duplicating artifact
fields across tables unless there is a clear reason" — there is exactly
one artifact per run, so a join table would only duplicate the same five
fields under a different name).

```json
{
  "schema_version": "1.0",
  "source": { "source_document_id": "...", "source_sha256": "...", "source_size_bytes": 12345 },
  "pipeline": { "pipeline_version": "pdf-text-v1", "configuration_version": "1", "extractor_name": "pypdf", "extractor_version": "6.14.2" },
  "document": { "page_count": 10, "metadata": {} },
  "metrics": { "pages_with_text": 9, "blank_pages": 1, "suspected_scanned_pages": 0, "total_characters": 40000, "total_words": 7000, "rotated_page_count": 0, "average_characters_per_page": 4000.0, "minimum_characters_on_nonblank_page": 3200, "maximum_characters_on_page": 4800 },
  "warnings": [],
  "pages": [ { "page_number": 1, "width_points": 595.0, "height_points": 842.0, "rotation_degrees": 0, "normalized_text": "...", "character_count": 4000, "word_count": 700, "is_blank": false, "suspected_scanned": false, "extraction_status": "text_extracted", "warnings": [], "page_checksum": "..." } ]
}
```

## Serialization is deterministic by construction, not by convention

`checksums.py::_canonical_bytes()` serializes with
`json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",",
":"))` for **every** hash input (both the whole-artifact checksum and
each page checksum) — `sort_keys=True` means the resulting byte sequence
never depends on Python dict insertion order (which is otherwise
implementation-defined across dict-construction code paths), so two
independently-built dicts describing the same logical content always hash
identically. `ensure_ascii=False` means Arabic and other non-ASCII text
hashes over its real UTF-8 bytes, not `\uXXXX` escapes — a different,
also-deterministic, but less obviously-correct choice would have produced
identical hashes either way; `ensure_ascii=False` was chosen so a human
inspecting the raw artifact bytes (e.g. for a future reviewer diff tool)
sees real characters.

**No timestamp of any kind is ever included in hashed content.** The
artifact's own JSON has no `created_at`/`processed_at`/`generated_at`
field at all — verified directly in
`apps/worker/tests/test_pdf_extraction_determinism.py::test_artifact_bytes_do_not_contain_a_wall_clock_timestamp`.
`document_extraction_runs.started_at`/`completed_at` (real timestamps)
live only in the database row, never inside the artifact bytes that get
hashed and uploaded.

## Text normalization (`normalization.py`)

One canonical, deterministic transform, applied identically regardless of
language:

1. Normalize line endings to `\n` (`\r\n`/`\r` → `\n`).
2. Strip NUL characters.
3. Unicode NFC normalization (`unicodedata.normalize("NFC", text)`).
4. Trim trailing whitespace per line — never collapse all whitespace into
   one line (meaningful line breaks are preserved).

Deliberately **not** done here (mission §17, §2.3): spell-correction,
content reordering, missing-text inference, or any LLM involvement — this
is a pure, offline, character-level transform. Arabic and other RTL text
passes through with its real Unicode codepoints intact — verified
directly in
`apps/worker/tests/test_pdf_extraction_fixtures.py::test_arabic_and_english`.
**Known, accepted limitation**: `pypdf`'s `extract_text()` reconstructs
reading order from the PDF content stream's operator order, not true
BiDi (bidirectional-text) reordering — a right-to-left paragraph's
extracted character sequence may not match its visual reading order. This
is the same category of limitation the mission's own Known Limitations
list anticipates for complex multi-column layouts (§41); Noor's own
normalization code never attempts to "fix" it algorithmically, since doing
so would itself be a form of content inference this sprint explicitly
forbids.

Every change to this function's behavior must bump
`EXTRACTION_CONFIGURATION_VERSION` — the whole reason a configuration
version exists is that "same source + same versions" is a promise about
normalization behavior too, not just the raw extractor's output.

## Page checksum

Computed over a canonical representation of exactly: page number,
rotation, width, height, normalized text, extraction status, and sorted
warnings — **never** processing timestamps, Worker identity, or attempt
ID (mission §18). This is what makes a page checksum meaningful for
reprocessing comparison and future reviewer diffing: it changes if and
only if something about the page's *content or technical classification*
changed, never merely because it was extracted at a different time by a
different Worker instance.

## Suspected-scanned heuristic (mission §20)

A page is `suspected_scanned` when it has **no extractable text** *and*
contains **at least one embedded raster image** (`/Subtype /Image`
XObject, inspected directly via low-level PDF object traversal — see
`extractor.py::_count_image_xobjects`). Deliberately does **not** count
vector graphics (rectangles, table borders, decorative lines) — those are
common in ordinary born-digital PDFs that also have real text elsewhere,
and would produce a false-positive "scanned" signal if counted. A blank
page with **no** images at all is classified `blank_page` (a genuinely
empty page, e.g. a "this page intentionally left blank" divider), not
`no_text_layer` — the two are deliberately distinct statuses. This
heuristic is conservative by design: it never claims certainty ("OCR may
be required in a later workflow" is the warning text, not "this page is
scanned") and OCR is never run to confirm or refute it (out of scope,
mission §4).

## Why `pypdf` doesn't need Pillow at runtime

`_count_image_xobjects` inspects the PDF's own `/Resources`/`/XObject`
dictionary directly rather than using `pypdf`'s `page.images` convenience
property, which decodes images and therefore requires Pillow. Counting
`/Subtype /Image` entries needs no image decoding at all — this keeps
Pillow entirely out of the Worker's production dependency footprint; it
remains a fixture-generation-only, test-time dependency (ADR 0010).
