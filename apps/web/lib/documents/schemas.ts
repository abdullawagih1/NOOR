import { z } from "zod";
import { MAX_UPLOAD_SIZE_BYTES, ALLOWED_MEDIA_TYPE } from "@/lib/documents/config";

/**
 * Validation schemas for secure guideline source-document intake. This is
 * the authoritative client/server-shared validation layer — the database
 * (migration 0006) independently re-enforces the rules that matter for
 * security (eligibility, one-primary-per-version, size limit), never
 * trusting this layer alone. See docs/security/document-intake-authorization.md.
 */

const SHA256_HEX = /^[a-f0-9]{64}$/i;

export const uploadSessionRequestSchema = z.object({
  guidelineVersionId: z.string().uuid(),
  filename: z
    .string()
    .trim()
    .min(1, "A filename is required")
    .max(255, "Filename is too long")
    .refine((v) => v.toLowerCase().endsWith(".pdf"), "Only .pdf files are supported"),
  declaredMediaType: z.literal(ALLOWED_MEDIA_TYPE, {
    errorMap: () => ({ message: "Only application/pdf is supported in this release" }),
  }),
  expectedSizeBytes: z
    .number()
    .int()
    .positive("File must not be empty")
    .max(MAX_UPLOAD_SIZE_BYTES, `File exceeds the ${MAX_UPLOAD_SIZE_BYTES / (1024 * 1024)} MB limit`)
    .optional(),
  expectedSha256: z
    .string()
    .regex(SHA256_HEX, "expectedSha256 must be a 64-character hex SHA-256 digest")
    .optional(),
  idempotencyKey: z.string().trim().min(1).max(200).optional(),
});
export type UploadSessionRequest = z.infer<typeof uploadSessionRequestSchema>;

export const uploadCompletionSchema = z.object({
  uploadSessionId: z.string().uuid(),
});
export type UploadCompletionInput = z.infer<typeof uploadCompletionSchema>;

export const documentFiltersSchema = z.object({
  guidelineVersionId: z.string().uuid().optional(),
  status: z.enum(["pending_upload", "uploaded", "verified", "registered", "rejected", "quarantined"]).optional(),
});
export type DocumentFilters = z.infer<typeof documentFiltersSchema>;

export const jobFiltersSchema = z.object({
  sourceDocumentId: z.string().uuid().optional(),
  status: z.enum(["queued", "claimed", "processing", "succeeded", "failed", "cancelled", "dead_lettered"]).optional(),
});
export type JobFilters = z.infer<typeof jobFiltersSchema>;

const nonEmptyReason = z.string().trim().min(1, "A reason is required").max(1000);

export const jobCancellationSchema = z.object({
  processingJobId: z.string().uuid(),
  reason: nonEmptyReason.optional(),
});
export type JobCancellationInput = z.infer<typeof jobCancellationSchema>;

export const quarantineDocumentSchema = z.object({
  sourceDocumentId: z.string().uuid(),
  reason: nonEmptyReason,
});
export type QuarantineDocumentInput = z.infer<typeof quarantineDocumentSchema>;

export const cancelUploadSessionSchema = z.object({
  uploadSessionId: z.string().uuid(),
  reason: nonEmptyReason.optional(),
});
export type CancelUploadSessionInput = z.infer<typeof cancelUploadSessionSchema>;
