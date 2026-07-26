/**
 * Canonical guideline source-document upload configuration. Referenced by
 * the Zod schema, the upload UI, and the Server Actions — never
 * re-hardcoded at any of those call sites.
 *
 * The database independently enforces the SAME numeric size limit inside
 * create_guideline_upload_session()
 * (supabase/migrations/0006_secure_guideline_document_intake.sql) as a
 * defense-in-depth guard — Postgres has no way to import this TypeScript
 * constant, so the two must be kept in sync by hand. A test asserts they
 * match: apps/web/tests/documents-config.test.ts.
 */
export const MAX_UPLOAD_SIZE_BYTES = 52_428_800; // 50 MB
export const ALLOWED_MEDIA_TYPE = "application/pdf";
export const ALLOWED_EXTENSION = "pdf";
export const PDF_SIGNATURE = "%PDF-";
export const UPLOAD_SESSION_TTL_MINUTES = 30;
