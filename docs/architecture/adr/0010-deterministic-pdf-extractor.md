# ADR 0010: Deterministic PDF Extractor Selection — `pypdf`

**Status:** Accepted
**Source:** Sprint 1.2B mission — Deterministic PDF Page and Text Extraction

## Decision

Noor's first (and, this sprint, only) PDF text-extraction engine is
**`pypdf` 6.14.2**, pure-Python, BSD-3-Clause licensed.

## Candidates considered

| Library | License | Notes |
|---|---|---|
| **PyMuPDF (`fitz`)** | **AGPL-3.0** (or a paid commercial license) since v1.24.1 | The mission names this as "a likely practical default" — rejected specifically because of licensing, not capability. AGPL's network-use clause (a SaaS provider who lets users interact with AGPL-licensed software over a network must offer the corresponding source) is a real, unresolved legal exposure for a commercial clinical SaaS platform. A commercial PyMuPDF license would remove this, but that's a paid-vendor decision this sprint has no mandate to make, and "quietly ship AGPL code into a commercial product" is exactly the kind of blind default this ADR exists to prevent. |
| **pdfminer.six** | MIT | Excellent layout analysis (`LAParams`), but the API is lower-level (character/line/box objects, not a page-level string) — meaningfully more integration work for the same result, and its per-line reconstruction has its own reading-order heuristics that would need to be pinned and documented just as carefully as anything `pypdf` does. No clear win over `pypdf` for this sprint's page-level, non-layout-aware scope. |
| **pdfplumber** | MIT | Built on `pdfminer.six`; nicer table/word-level API, but pulls in the same underlying reading-order behavior and adds dependencies (`Pillow`, `pdfminer.six`) this sprint doesn't need — table reconstruction is explicitly out of scope (§4). |
| **pypdf** (selected) | **BSD-3-Clause** | Pure Python (no compiled extension to build/ship across platforms — matches every existing Worker dependency: `fastapi`/`uvicorn`/`pydantic`/`httpx` are all pure-Python or wheel-only). Page-level `extract_text()`, `page.rotation`, `page.mediabox` (width/height), `reader.is_encrypted`, and a clean `FileNotDecryptedError`/`PdfStreamError` exception taxonomy for encrypted/corrupt input (verified directly — see below). Actively maintained (weekly-cadence releases, the direct successor to `PyPDF2`). |

## Verified directly (not assumed from documentation)

```python
>>> reader = PdfReader(buf)               # a reportlab-generated fixture
>>> len(reader.pages)                     # 1
>>> reader.pages[0].rotation              # 0
>>> float(reader.pages[0].mediabox.width) # 595.2756 (A4 in points)
>>> reader.pages[0].extract_text()        # 'Hello Noor - deterministic extraction test\n'
>>> reader.is_encrypted                   # False

# Encrypted fixture (writer.encrypt(user_password=...)):
>>> reader.is_encrypted                   # True
>>> reader.pages[0].extract_text()        # raises FileNotDecryptedError

# Corrupt input:
>>> PdfReader(io.BytesIO(b'not a real pdf'))  # raises PdfStreamError
```

This gives a clean, distinguishable exception for each of the
`encrypted_pdf`/`password_protected_pdf` and `corrupt_pdf` failure classes
(§16) without any extra probing code.

## Exact version and license

* **Package:** `pypdf==6.14.2` (pinned in `apps/worker/requirements.txt`).
* **License:** BSD-3-Clause — commercially unencumbered, no network-use
  disclosure obligation.
* **`reportlab==4.2.5`** (BSD-style license) is a **test/fixture-generation
  dependency only** — it generates the synthetic PDF fixtures committed
  under `apps/worker/tests/fixtures/pdf/`; it is never imported by
  production extraction code (`app/pdf_extraction/*`).

## Known limitations (documented, not hidden)

* **No layout-aware reading-order correction.** `pypdf`'s `extract_text()`
  reconstructs reading order from the PDF's content-stream operator order
  — usually correct for simple single-column text, not guaranteed for
  complex multi-column layouts, footnotes, or floating text boxes. This
  is an accepted, documented limitation (§41), not a defect — the same
  caveat would apply to `pdfminer.six`/`pdfplumber` output too, just
  expressed differently.
* **No image/table extraction.** Out of scope this sprint regardless of
  library.
* **Unicode/Arabic** text extracts correctly whenever the source PDF's
  font carries a proper `ToUnicode` CMap (true of every fixture this
  sprint generates and of virtually every born-digital, non-scanned
  clinical guideline PDF). A PDF whose fonts lack this mapping — most
  commonly scanned/image-only PDFs — will simply extract no text, which
  is exactly the `no_text_layer`/`suspected_scanned` signal this
  pipeline is designed to surface, not a `pypdf`-specific gap.
* **No OCR fallback.** By design (§2.3, §4) — a scanned page with no
  text layer is reported honestly, never silently reconstructed.

## Determinism expectations

Given the identical source bytes, `pypdf==6.14.2` produces identical
`extract_text()`/`rotation`/`mediabox` output on every call — it performs
no network I/O, no randomization, and no non-deterministic ordering
internally. The one non-deterministic-*looking* surface is
`reader.metadata` (which may include a `/CreationDate`/`/ModDate` baked
into the source file itself at the time it was authored) — this is a
property of the **source PDF bytes**, not of `pypdf`'s processing, and is
therefore still fully deterministic per the actual determinism contract
this sprint tests: *identical source SHA-256 → identical canonical
artifact*, not *regenerating a fixture produces byte-identical fixture
bytes* (fixtures are generated once and committed statically; §31–§32).

## Upgrade policy

`pypdf` is pinned to an exact version
(`EXTRACTION_PIPELINE_VERSION`/`PDF_EXTRACTOR_VERSION` both record it
explicitly — see `apps/worker/app/pdf_extraction/config.py`). Upgrading
the pinned version is a deliberate, reviewed action that must bump
`PDF_EXTRACTOR_VERSION` (and, if extraction behavior could plausibly
change, `EXTRACTION_PIPELINE_VERSION` too) — never a silent
`pip install --upgrade` that would let two extraction runs of the same
source document silently disagree without a version marker to explain
why.

## Not selected this sprint, and why

Only one extractor is implemented (§8: "Do not implement multiple
extractors in this Sprint"). `pdfminer.six`/`pdfplumber` remain a
reasonable fallback candidate if `pypdf`'s text-extraction quality proves
insufficient against real guideline PDFs in a later sprint — nothing in
this sprint's abstraction (`PdfExtractor` protocol,
`apps/worker/app/pdf_extraction/extractor.py`) prevents adding a second
implementation later behind the same interface.
