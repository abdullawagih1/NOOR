# OCR Model/Provider/Renderer Upgrade Procedure (Sprint 1-D2)

Every component of the OCR identity (ADR 0012) is pinned as an explicit
constant in `apps/worker/app/ocr/config.py`, never inferred from whatever
happens to be installed. Bumping any of them is a deliberate, reviewed
action — never an incidental side effect of an unrelated dependency
update.

## What is pinned, and where

| Constant | Current value | Source of truth |
|---|---|---|
| `RENDERER_NAME` / `RENDERER_VERSION` | `pypdfium2` / `5.12.1` | `apps/worker/requirements.txt` pin; verified at Worker startup by `assert_pinned_renderer_version()` against the installed package's `importlib.metadata.version`. |
| `RENDER_CONFIGURATION_VERSION` | `"1"` | Bumped whenever `RENDER_DPI`/`RENDER_COLOR_MODE`/`RENDER_IMAGE_FORMAT` changes — any change affecting page pixels is, by definition, a different OCR input. |
| `OCR_PROVIDER_NAME` / `OCR_PROVIDER_VERSION` | `tesseract` / `5.5.0` | The Dockerfile's `apt-get install tesseract-ocr` on the pinned base image (`python:3.12-slim`, currently Debian 13 "trixie", whose apt candidate is `5.5.0-1+b1` — upstream version `5.5.0`); verified at Worker startup by `assert_pinned_provider_version()` running `tesseract --version`. |
| `OCR_MODEL_IDENTIFIER` / `OCR_MODEL_VERSION` | `tessdata_fast` / commit `87416418...` | Pinned commit of `github.com/tesseract-ocr/tessdata_fast`, fetched and checksum-verified by `apps/worker/scripts/fetch_tessdata_models.py`. |
| `OCR_CONFIGURATION_VERSION` | `"1"` | Bumped whenever the normalization policy (`app/pdf_extraction/normalization.py`, reused by OCR) or Tesseract `oem`/`psm` settings change. |

## Upgrading the renderer (pypdfium2)

1. Bump the version in `apps/worker/requirements.txt`.
2. Update `RENDERER_VERSION` in `app/ocr/config.py` to match exactly.
3. Rebuild the Docker image; `assert_pinned_renderer_version()` will
   crash the process at startup if the two ever drift apart again.
4. If the new version changes pixel output for the same input (rare for
   a rasterizer, but possible with a rendering-engine upgrade), also bump
   `RENDER_CONFIGURATION_VERSION` — this deliberately creates a new OCR
   identity for every page, forcing fresh (not silently reused) OCR
   results under the new renderer.
5. Re-run `pytest apps/worker/tests/test_ocr_renderer_and_provider.py`
   locally and re-verify the Docker-image smoke test (render + OCR
   against the English/Arabic/mixed fixtures) before deploying.

## Upgrading the provider (Tesseract)

1. Confirm the target Debian/Ubuntu base image's `tesseract-ocr` apt
   candidate version with `apt-cache policy tesseract-ocr` against the
   *actual* target base image — do not assume a version without
   checking; `python:3.12-slim`'s underlying Debian release (and
   therefore its apt package version) can and does change over time.
2. Update `OCR_PROVIDER_VERSION` in `app/ocr/config.py` to match exactly.
3. Rebuild the Docker image; `assert_pinned_provider_version()` will
   crash the process at startup if they drift apart.
4. A Tesseract engine-version bump can change recognition output for
   identical input — treat this the same as an `OCR_CONFIGURATION_VERSION`
   bump if you want old results to remain distinguishable from
   re-processed ones under the new engine (the full identity already
   includes `provider_version`, so this happens automatically: a
   different `provider_version` is already, by construction, a different
   OCR identity — no separate config-version bump is required for the
   provider version itself, only for provider-independent
   configuration like `oem`/`psm`).

## Upgrading the language models (tessdata)

1. Choose a new pinned commit of `tesseract-ocr/tessdata_fast` — never
   point at `main` (which moves).
2. Compute the new per-language SHA-256 and byte size, and update
   `TESSDATA_FAST_COMMIT`, `MODELS` in
   `apps/worker/scripts/fetch_tessdata_models.py`, and the matching
   `OCR_MODEL_VERSION`/`TESSDATA_MODEL_CHECKSUMS`/`TESSDATA_MODEL_SIZES`
   constants in `app/ocr/config.py` — these must always agree; a
   mismatch means `assert_pinned_tessdata_models()` will refuse to start
   the Worker (fail closed, not fail open).
3. Delete the local `apps/worker/tessdata/` directory (or run in a clean
   environment) and re-run `python scripts/fetch_tessdata_models.py` to
   materialize and verify the new files.
4. Rebuild the Docker image (the build step runs the same fetch script).
5. A model upgrade is expected to change recognition output — this is
   automatically reflected in the OCR identity via `model_version`, so
   old results remain queryable and distinguishable without any other
   change required.

## Supply-chain discipline

- Never fetch an unpinned/`latest` model at Worker startup or request
  time — `fetch_tessdata_models.py` always targets one specific commit
  and verifies both byte size and SHA-256 before writing to disk.
- Never allow a browser-supplied provider/model/renderer argument —
  every identity component is either a server-pinned constant or derived
  from the extraction review/request row, never client input (mission
  §13/§14).
- `assert_pinned_tessdata_models()` fails closed: a missing or
  checksum-mismatched model file crashes the Worker at startup rather
  than silently falling back to whatever the system happens to have.
