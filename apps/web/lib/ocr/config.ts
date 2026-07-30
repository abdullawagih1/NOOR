/**
 * Mirrors the pinned identity constants in apps/worker/app/ocr/config.py
 * (Sprint 1-D2, ADR 0012). These are the values create_document_ocr_request
 * submits when a request is created from the web UI — they must describe
 * what the Worker is actually pinned to run, not an arbitrary label, since
 * they become part of every OCR run's permanent identity. Bumping any of
 * them here without also bumping the matching Worker constant (and vice
 * versa) would record a misleading identity — see
 * docs/operations/ocr-model-upgrade.md before changing any of these.
 */
export const OCR_RENDERER_NAME = "pypdfium2";
export const OCR_RENDERER_VERSION = "5.12.1";
export const OCR_RENDER_CONFIGURATION_VERSION = "1";

export const OCR_PROVIDER_NAME = "tesseract";
export const OCR_PROVIDER_VERSION = "5.5.0";
export const OCR_MODEL_IDENTIFIER = "tessdata_fast";
export const OCR_MODEL_VERSION = "87416418657359cb625c412a48b6e1d6d41c29bd";
export const OCR_CONFIGURATION_VERSION = "1";

export const OCR_SUPPORTED_LANGUAGE_HINTS = ["eng", "ara"] as const;
export type OcrLanguageHint = (typeof OCR_SUPPORTED_LANGUAGE_HINTS)[number];
