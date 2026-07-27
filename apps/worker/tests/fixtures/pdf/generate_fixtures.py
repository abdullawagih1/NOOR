"""
Generates the synthetic PDF fixtures used by the extraction test suite
(mission §31). Run once, manually, whenever a fixture needs to change:

    cd apps/worker
    .venv/Scripts/python.exe tests/fixtures/pdf/generate_fixtures.py

The resulting .pdf files are committed as static binary fixtures — tests
never regenerate them at run time, so determinism tests compare against
fixed, known bytes rather than a freshly (and non-reproducibly, given
embedded creation timestamps) regenerated file. No clinical claims, no
patient data — every fixture is synthetic placeholder text.
"""
from __future__ import annotations

import io
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

FIXTURES_DIR = Path(__file__).parent
ARABIC_GREETING = "\u0645\u0631\u062d\u0628\u0627 \u0628\u0643\u0645 \u0641\u064a \u0646\u0648\u0631"  # "Hello, welcome to Noor"

try:
    pdfmetrics.registerFont(TTFont("Arial", "C:/Windows/Fonts/arial.ttf"))
    _HAS_ARIAL = True
except Exception:
    _HAS_ARIAL = False


def _new_canvas(buf: io.BytesIO) -> canvas.Canvas:
    return canvas.Canvas(buf, pagesize=A4)


def make_one_page_english() -> bytes:
    buf = io.BytesIO()
    c = _new_canvas(buf)
    c.drawString(100, 700, "Noor synthetic fixture: one-page English test document.")
    c.drawString(100, 680, "This fixture contains no clinical claims and no patient data.")
    c.showPage()
    c.save()
    return buf.getvalue()


def make_multi_page(num_pages: int = 5) -> bytes:
    buf = io.BytesIO()
    c = _new_canvas(buf)
    for i in range(1, num_pages + 1):
        c.drawString(100, 700, f"Noor synthetic fixture: page {i} of {num_pages}.")
        c.drawString(100, 680, "Synthetic placeholder content, not a real guideline.")
        c.showPage()
    c.save()
    return buf.getvalue()


def make_arabic_and_english() -> bytes:
    buf = io.BytesIO()
    c = _new_canvas(buf)
    if _HAS_ARIAL:
        c.setFont("Arial", 14)
    c.drawString(100, 700, "English: synthetic fixture text.")
    if _HAS_ARIAL:
        c.drawString(100, 670, ARABIC_GREETING)
    c.showPage()
    c.save()
    return buf.getvalue()


def make_empty_page() -> bytes:
    buf = io.BytesIO()
    c = _new_canvas(buf)
    c.showPage()  # a page with nothing drawn on it at all
    c.save()
    return buf.getvalue()


def make_rotated_page() -> bytes:
    buf = io.BytesIO()
    c = _new_canvas(buf)
    c.drawString(100, 700, "Noor synthetic fixture: this page will be rotated 90 degrees.")
    c.showPage()
    c.save()
    buf.seek(0)
    reader = PdfReader(buf)
    writer = PdfWriter()
    page = reader.pages[0]
    page.rotate(90)
    writer.add_page(page)
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


def make_mixed_blank_and_text() -> bytes:
    buf = io.BytesIO()
    c = _new_canvas(buf)
    c.drawString(100, 700, "Page 1: has text.")
    c.showPage()
    c.showPage()  # page 2: blank
    c.drawString(100, 700, "Page 3: has text again.")
    c.showPage()
    c.save()
    return buf.getvalue()


def make_image_only_no_text_layer() -> bytes:
    """A page with an embedded raster image and no text at all — a safe,
    synthetic stand-in for a scanned page (a solid-color PNG, not a real
    scanned document), specifically to exercise the no-text-layer /
    suspected-scanned detection path, which looks for an embedded `/Image`
    XObject (not vector drawing operators — a filled rectangle primitive
    would not and should not trigger this heuristic; see
    app/pdf_extraction/extractor.py::_count_image_xobjects)."""
    from PIL import Image
    from reportlab.lib.utils import ImageReader

    pixel_buf = io.BytesIO()
    Image.new("RGB", (200, 150), color=(200, 200, 220)).save(pixel_buf, format="PNG")
    pixel_buf.seek(0)

    buf = io.BytesIO()
    c = _new_canvas(buf)
    c.drawImage(ImageReader(pixel_buf), 100, 600, width=200, height=150)
    c.showPage()
    c.save()
    return buf.getvalue()


def make_corrupt() -> bytes:
    return b"%PDF-1.4\n this is deliberately truncated and invalid, not a real PDF trailer"


def make_encrypted() -> bytes:
    buf = io.BytesIO()
    c = _new_canvas(buf)
    c.drawString(100, 700, "This content is password-protected.")
    c.showPage()
    c.save()
    buf.seek(0)
    reader = PdfReader(buf)
    writer = PdfWriter()
    for p in reader.pages:
        writer.add_page(p)
    writer.encrypt(user_password="noor-fixture-password")
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


def make_invalid_signature() -> bytes:
    return b"This file has a .pdf extension but is not actually a PDF file at all."


def make_unusual_metadata() -> bytes:
    buf = io.BytesIO()
    c = _new_canvas(buf)
    c.setAuthor("Noor Synthetic Fixture Generator \u2014 \u00e9\u00e8\u00ea\u00eb \u4e2d\u6587")
    c.setTitle("")
    c.setSubject("A" * 500)
    c.drawString(100, 700, "Noor synthetic fixture: unusual metadata test document.")
    c.showPage()
    c.save()
    return buf.getvalue()


FIXTURES = {
    "one_page_english.pdf": make_one_page_english,
    "multi_page.pdf": make_multi_page,
    "arabic_and_english.pdf": make_arabic_and_english,
    "empty_page.pdf": make_empty_page,
    "rotated_page.pdf": make_rotated_page,
    "mixed_blank_and_text.pdf": make_mixed_blank_and_text,
    "image_only_no_text_layer.pdf": make_image_only_no_text_layer,
    "corrupt.pdf": make_corrupt,
    "encrypted.pdf": make_encrypted,
    "invalid_signature.pdf": make_invalid_signature,
    "unusual_metadata.pdf": make_unusual_metadata,
}


def main() -> None:
    for filename, generator in FIXTURES.items():
        content = generator()
        (FIXTURES_DIR / filename).write_bytes(content)
        print(f"wrote {filename} ({len(content)} bytes)")


if __name__ == "__main__":
    main()
