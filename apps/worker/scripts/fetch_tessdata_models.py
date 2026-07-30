"""
Fetches and checksum-verifies the two pinned tessdata_fast language models
this Worker uses for OCR (Sprint 1-D2, ADR 0012). Run once during local
setup and again during the Docker image build — never at request time.

Deliberately downloads from a specific pinned commit of
github.com/tesseract-ocr/tessdata_fast, not `main` (which moves), and
verifies both the exact byte size and SHA-256 of what was received before
writing it to disk — the same "never trust a download without
independently re-verifying it" discipline already used for source PDFs
(app/pdf_extraction/source_download.py) and extraction artifacts
(app/pdf_extraction/artifact_storage.py).

The resulting files are NOT committed to the repository (see
.gitignore's apps/worker/tessdata/ entry) — the pinned commit + checksums
recorded in app/ocr/config.py are the actual source of truth; this script
is just a reproducible way to materialize them. See
docs/operations/ocr-model-upgrade.md for the upgrade procedure.
"""
from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path

TESSDATA_FAST_COMMIT = "87416418657359cb625c412a48b6e1d6d41c29bd"

MODELS: dict[str, tuple[int, str]] = {
    # language: (expected_size_bytes, expected_sha256)
    "eng": (4_113_088, "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"),
    "ara": (1_432_056, "e3206d3dc87fd50c24a0fb9f01838615911d25168f4e64415244b67d2bb3e729"),
}

DEST_DIR = Path(__file__).resolve().parent.parent / "tessdata"


def _download(language: str, expected_size: int, expected_sha256: str) -> bytes:
    url = f"https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/{TESSDATA_FAST_COMMIT}/{language}.traineddata"
    with urllib.request.urlopen(url, timeout=120) as response:
        content = response.read()

    if len(content) != expected_size:
        raise RuntimeError(
            f"{language}.traineddata: downloaded {len(content)} bytes, expected exactly {expected_size} — "
            "refusing to write a truncated or unexpected file"
        )
    actual_sha256 = hashlib.sha256(content).hexdigest()
    if actual_sha256 != expected_sha256:
        raise RuntimeError(
            f"{language}.traineddata: checksum mismatch (expected {expected_sha256}, got {actual_sha256})"
        )
    return content


def main() -> int:
    DEST_DIR.mkdir(parents=True, exist_ok=True)
    for language, (expected_size, expected_sha256) in MODELS.items():
        dest_path = DEST_DIR / f"{language}.traineddata"
        if dest_path.exists():
            existing = dest_path.read_bytes()
            if len(existing) == expected_size and hashlib.sha256(existing).hexdigest() == expected_sha256:
                print(f"{language}.traineddata already present and verified, skipping download")
                continue
        print(f"fetching {language}.traineddata from pinned commit {TESSDATA_FAST_COMMIT}...")
        content = _download(language, expected_size, expected_sha256)
        dest_path.write_bytes(content)
        print(f"  wrote {dest_path} ({len(content)} bytes, verified)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
