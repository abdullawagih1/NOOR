# ADR 0012: Controlled Page-Scoped OCR

Status: Accepted
Sprint: 1-D2

## Context

Sprint 1-D1's extraction review can flag specific pages as `ocr_required`
when native PDF text extraction is insufficient (scanned pages, missing
text layers). This sprint implements the actual OCR execution — but only
for the exact pages a human reviewer approved, never the whole document,
and never as a silent replacement of the native extraction.

## Decisions

### Why OCR is page-scoped

A review that flags 2 of 40 pages as `ocr_required` means 38 pages
already have usable native text. Re-OCRing them would be wasted
computation, would introduce a second, lower-fidelity representation
where a better one already exists, and would violate the core review
finding: the reviewer explicitly said *these specific pages* need OCR,
not the document. OCR eligibility is derived exclusively from explicit
review evidence (`document_extraction_page_reviews.review_status =
'ocr_candidate'`, or an OCR-relevant open/resolved finding on that page)
— never from the `suspected_scanned` technical flag alone, which only
*suggests* review, per ADR 0011's own review/execution boundary.

### Why one processing job per OCR page

Following S1-C1's proven durable-job model exactly: isolated retries (one
provider timeout doesn't block 9 other pages), exact page-level
provenance, smaller provider calls (lower latency, lower memory), smaller
failure blast radius, and no need to reprocess already-succeeded pages
when a sibling page fails. A single document-wide OCR job would need its
own internal page-retry bookkeeping, essentially reinventing what
`document_processing_jobs` already does correctly.

### Native text is never overwritten

`document_extraction_pages.normalized_text` and its checksum remain
exactly as immutable as Sprint 1.2B left them. OCR output lives in a
wholly separate table (`document_ocr_runs`) with its own provenance
chain. `get_document_page_text_readiness()` (§ below) is the only place
that decides, per page, which representation is canonical — the
underlying rows are never merged or mutated into each other. A future
human-corrected-text workflow gets the same treatment: a third,
independent representation, never a fourth mutation path into either of
the first two.

### OCR request vs. OCR review — the same separation as ADR 0011

`document_ocr_requests`/`document_ocr_request_pages` track *what was
asked for and its execution state* (governance + Worker-tracked
progress). `document_ocr_reviews`/`document_ocr_page_reviews` track *was
the result any good* (human technical judgment). Execution success
(`document_ocr_runs.status = 'succeeded'`) is not review acceptance
(`document_ocr_reviews.review_status = 'accepted'`) — the identical
principle ADR 0011 established for extraction, applied one layer deeper.

### Provider selection: Tesseract, self-hosted, not a cloud API

Evaluated against the mission's own criteria:

| Criterion | Tesseract 5.5 (self-hosted) | A cloud OCR API |
|---|---|---|
| Data residency / privacy | Runs inside the Worker process; guideline pages never leave Noor's own infrastructure | Requires sending page images to a third party — no DPA, no residency review has been done, and the mission explicitly requires that before considering it |
| License | Apache-2.0 (engine), Apache-2.0 (`pytesseract` wrapper) | Varies; typically a paid, ToS-bound API |
| Arabic + English | Both included in the standard `tessdata_fast` language-model set, confirmed working locally (real Arabic and English text recognized correctly against synthetic fixtures before writing any pipeline code) | Would need to be re-verified per provider |
| Determinism / reproducibility | Runs from pinned model files with recorded checksums; same binary + same models + same image = same output | Model version behind the API can change without notice |
| Docker/CPU footprint | Small, CPU-only, no GPU requirement, fits the existing Worker container | N/A |
| Confidence output | Per-word confidence via `image_to_data` (TSV) | Varies |

Self-hosted Tesseract was preferred per the mission's own explicit bias
("prefer a self-hosted provider... unless an externally hosted provider
has already received explicit architectural and privacy approval" — it
had not) and is the only option that lets Noor make an unqualified "no
guideline content leaves this infrastructure" claim.

### Renderer: pypdfium2, not pdf2image/poppler

`pypdfium2` (BSD-3-Clause/Apache-2.0 dual license) wraps Google's PDFium
directly via prebuilt wheels — no system `poppler-utils` dependency to
manage/pin separately, smaller Docker footprint, and PDFium is the same
rendering engine Chrome uses, giving broad real-world PDF compatibility
including rotation and non-Latin text. `pdf2image` was rejected because
it shells out to a separately-versioned system Poppler install, which is
one more untracked version to pin and one more attack surface.

### OCR identity and versioning

The full identity (organization + source checksum + extraction run +
page number + native page checksum + renderer name/version/config +
rendered-image checksum + provider name/version + model
identifier/version + OCR config + language hints) is exactly analogous to
Sprint 1.2B's extraction identity, one layer deeper (it additionally
pins the *rendering* step, since OCR input is a rendered image, not the
PDF bytes directly). A partial unique index guarantees at most one
succeeded run per identity; a change to *any* component of that identity
is, by definition, a new attempt requiring reprocessing — never a silent
overwrite.

### Storage hardening (migration 0010)

Addressed as its own migration, ahead of the OCR schema, per the
mission's explicit ordering. See
`docs/security/ocr-and-storage-authorization.md` for the full account —
organization membership alone no longer authorizes reading original
PDFs or processed artifacts; an explicit permission
(`guideline_documents.read` / `guideline_extractions.read_artifacts` /
`guideline_ocr.read_artifacts`) is now required at the Storage RLS layer
itself, not only enforced by the application layer minting signed URLs.

### Why chunking remains out of scope

Canonical page-text readiness
(`get_document_page_text_readiness()`) is the hand-off point for S1-D3 —
it tells a future chunking pipeline exactly one accepted representation
per page (native or OCR) with a text checksum. This sprint stops there:
no chunk boundaries, no chunk table, no embeddings. Retrieval eligibility
remains hard-coded `false` throughout, exactly as it was in ADR 0011.
