"""
Canonical OCR identity constants (Sprint 1-D2, ADR 0012). One layer
deeper than app/pdf_extraction/config.py's extraction identity — it
additionally pins the *rendering* step, since OCR input is a rendered
page image, not the PDF bytes directly.

Provider: Tesseract 5.5.0, self-hosted (ADR 0012) — no cloud OCR API has
received the architectural/privacy approval the mission requires before
one could be considered.
Renderer: pypdfium2 (ADR 0012) — wraps PDFium directly, no separate
system Poppler dependency to pin.
Language models: tessdata_fast, pinned to one specific upstream commit
and verified by SHA-256 (see scripts/fetch_tessdata_models.py), never
"whatever tesseract happens to find on this machine."

Bumping any of these is a deliberate, reviewed action — see ADR 0012's
upgrade policy and docs/operations/ocr-model-upgrade.md.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

OCR_PIPELINE_VERSION = "controlled-page-ocr-v1"

RENDERER_NAME = "pypdfium2"
RENDERER_VERSION = "5.12.1"
RENDER_CONFIGURATION_VERSION = "1"
RENDER_DPI = 300
RENDER_COLOR_MODE = "rgb"
RENDER_IMAGE_FORMAT = "png"

OCR_PROVIDER_NAME = "tesseract"
OCR_PROVIDER_VERSION = "5.5.0"
OCR_MODEL_IDENTIFIER = "tessdata_fast"
# The tessdata_fast commit scripts/fetch_tessdata_models.py pins — see
# that script for the exact URL and per-language checksums.
OCR_MODEL_VERSION = "87416418657359cb625c412a48b6e1d6d41c29bd"
OCR_CONFIGURATION_VERSION = "1"

SUPPORTED_LANGUAGE_HINTS = ("eng", "ara")

ARTIFACT_SCHEMA_VERSION = "1.0"
ARTIFACT_MEDIA_TYPE = "application/json"
ARTIFACT_STORAGE_BUCKET = "guideline-processed"

# Overridable via settings/env for Docker (see app/settings.py); defaults
# to the repo-local directory scripts/fetch_tessdata_models.py populates.
DEFAULT_TESSDATA_DIR = Path(__file__).resolve().parent.parent.parent / "tessdata"

TESSDATA_MODEL_CHECKSUMS: dict[str, str] = {
    "eng": "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
    "ara": "e3206d3dc87fd50c24a0fb9f01838615911d25168f4e64415244b67d2bb3e729",
}
TESSDATA_MODEL_SIZES: dict[str, int] = {
    "eng": 4_113_088,
    "ara": 1_432_056,
}


def assert_pinned_renderer_version() -> None:
    import importlib.metadata

    installed = importlib.metadata.version("pypdfium2")
    if installed != RENDERER_VERSION:
        raise RuntimeError(
            f"Installed pypdfium2 version ({installed}) does not match the pinned "
            f"RENDERER_VERSION ({RENDERER_VERSION}) recorded in app/ocr/config.py. "
            "Update the constant (and consider whether RENDER_CONFIGURATION_VERSION "
            "also needs bumping) before deploying — see ADR 0012."
        )


def assert_pinned_provider_version() -> None:
    import subprocess

    try:
        result = subprocess.run(["tesseract", "--version"], capture_output=True, text=True, timeout=10)
    except FileNotFoundError as exc:
        raise RuntimeError("the tesseract binary is not installed or not on PATH") from exc

    first_line = (result.stdout or result.stderr).splitlines()[0] if (result.stdout or result.stderr) else ""
    if f"tesseract {OCR_PROVIDER_VERSION}" not in first_line and f"tesseract v{OCR_PROVIDER_VERSION}" not in first_line:
        raise RuntimeError(
            f"Installed tesseract version ({first_line!r}) does not match the pinned "
            f"OCR_PROVIDER_VERSION ({OCR_PROVIDER_VERSION}) recorded in app/ocr/config.py. "
            "Update the constant before deploying — see ADR 0012."
        )


def assert_pinned_tessdata_models(tessdata_dir: Path) -> None:
    import hashlib

    for language in SUPPORTED_LANGUAGE_HINTS:
        model_path = tessdata_dir / f"{language}.traineddata"
        if not model_path.is_file():
            raise RuntimeError(
                f"pinned tessdata model missing: {model_path}. Run "
                "apps/worker/scripts/fetch_tessdata_models.py before starting the Worker."
            )
        content = model_path.read_bytes()
        if len(content) != TESSDATA_MODEL_SIZES[language]:
            raise RuntimeError(f"{model_path} size does not match the pinned OCR_MODEL_VERSION — re-run fetch_tessdata_models.py")
        if hashlib.sha256(content).hexdigest() != TESSDATA_MODEL_CHECKSUMS[language]:
            raise RuntimeError(f"{model_path} checksum does not match the pinned OCR_MODEL_VERSION — re-run fetch_tessdata_models.py")


@dataclass(frozen=True)
class OcrConfiguration:
    """Deterministic OCR settings — see docs/domain/ocr-page-representations.md."""

    version: str = OCR_CONFIGURATION_VERSION
    # Tesseract OCR Engine Mode: 3 = default, based on what is available (LSTM + legacy).
    oem: int = 3
    # Tesseract Page Segmentation Mode: 3 = fully automatic page segmentation, no OSD.
    psm: int = 3
