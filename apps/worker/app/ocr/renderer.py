"""
Deterministic PDF page renderer abstraction (ADR 0012) and its one
implementation, pypdfium2. Rendering is the step that turns PDF page
content into the pixel image OCR actually reads — pinning its version,
DPI, color mode, and image format is part of the OCR identity (mission
§12.3), since a different render of the same page is, by definition, a
different OCR input.

The rendered image is never written to disk or persisted anywhere beyond
this process's memory — it is held only as in-memory bytes, handed to
the OCR provider, and discarded once this function's caller is done with
it (mission §17: "the image itself is not persisted by default"). No
temp file is created in the first place, so there is nothing to clean up
in a `finally` block.
"""
from __future__ import annotations

import io
from pathlib import Path
from typing import Protocol

import pypdfium2 as pdfium
from PIL import Image

from app.ocr.checksums import compute_image_checksum
from app.ocr.config import RENDER_COLOR_MODE, RENDER_DPI, RENDER_IMAGE_FORMAT, RENDERER_VERSION
from app.ocr.errors import OcrError
from app.ocr.models import RenderedPage


class PdfPageRenderer(Protocol):
    @property
    def name(self) -> str: ...

    @property
    def version(self) -> str: ...

    def render_page(
        self, pdf_path: Path, page_number: int, *, dpi: int, color_mode: str, image_format: str
    ) -> RenderedPage: ...


class Pypdfium2Renderer:
    """See ADR 0012 for the selection rationale."""

    def __init__(self, version: str = RENDERER_VERSION) -> None:
        self._version = version

    @property
    def name(self) -> str:
        return "pypdfium2"

    @property
    def version(self) -> str:
        return self._version

    def render_page(
        self,
        pdf_path: Path,
        page_number: int,
        *,
        dpi: int = RENDER_DPI,
        color_mode: str = RENDER_COLOR_MODE,
        image_format: str = RENDER_IMAGE_FORMAT,
    ) -> RenderedPage:
        try:
            pdf = pdfium.PdfDocument(str(pdf_path))
        except Exception as exc:
            raise OcrError("corrupt_pdf", "the PDF could not be opened for rendering") from exc

        try:
            if page_number < 1 or page_number > len(pdf):
                raise OcrError("page_render_failed", f"page {page_number} does not exist in this document")

            try:
                page = pdf[page_number - 1]
                bitmap = page.render(scale=dpi / 72)
                pil_image = bitmap.to_pil()
                pil_image = pil_image.convert("L" if color_mode == "grayscale" else "RGB")
            except OcrError:
                raise
            except Exception as exc:
                raise OcrError("page_render_failed", f"page {page_number} could not be rendered") from exc

            buffer = io.BytesIO()
            try:
                pil_image.save(buffer, format=image_format.upper())
            except Exception as exc:
                raise OcrError("page_render_failed", f"page {page_number} could not be encoded as {image_format}") from exc

            image_bytes = buffer.getvalue()
            return RenderedPage(
                image_bytes=image_bytes,
                width_px=pil_image.width,
                height_px=pil_image.height,
                checksum=compute_image_checksum(image_bytes),
            )
        finally:
            pdf.close()
