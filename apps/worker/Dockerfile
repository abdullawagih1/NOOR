FROM python:3.12-slim

WORKDIR /app

# tesseract-ocr (Sprint 1-D2, ADR 0012): apt's candidate on this base image
# is 5.5.0, matching app/ocr/config.py's pinned OCR_PROVIDER_VERSION exactly
# (verified against this exact image at build-pin time — re-check
# apt-cache policy tesseract-ocr before ever bumping the base image tag).
# --tessdata-dir is always passed explicitly by app/ocr/provider.py, so the
# package's own bundled language data is never relied upon.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY scripts ./scripts
# Materializes the two pinned, checksum-verified tessdata_fast language
# models (app/ocr/config.py) into the image at build time — never
# downloaded at request time, never fetched from `main`.
RUN python scripts/fetch_tessdata_models.py

COPY app ./app

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
