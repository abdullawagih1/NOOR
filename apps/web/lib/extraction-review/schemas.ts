import { z } from "zod";
import { EXTRACTION_FINDING_TYPES } from "@/lib/extraction-review/queries";

export const findingCreateSchema = z.object({
  reviewId: z.string().uuid(),
  extractionPageId: z.string().uuid().optional(),
  findingType: z.enum(EXTRACTION_FINDING_TYPES),
  severity: z.enum(["informational", "minor", "major", "critical"]),
  title: z.string().trim().min(1, "A title is required.").max(200),
  description: z.string().trim().max(4000).optional(),
  suggestedAction: z.string().trim().max(2000).optional(),
});

export const findingStatusUpdateSchema = z.object({
  findingId: z.string().uuid(),
  status: z.enum(["open", "acknowledged", "resolved", "accepted_risk", "dismissed"]),
  resolutionNote: z.string().trim().max(2000).optional(),
});

export const pageReviewedSchema = z.object({
  reviewId: z.string().uuid(),
  pageNumber: z.coerce.number().int().min(1),
  pageReviewStatus: z.enum(["reviewed_clear", "reviewed_with_findings", "ocr_candidate", "reprocessing_candidate"]),
  notes: z.string().trim().max(2000).optional(),
});

export const reviewSubmitSchema = z.object({
  reviewId: z.string().uuid(),
  targetStatus: z.enum(["accepted", "accepted_with_warnings", "ocr_required", "reprocessing_required", "rejected"]),
  decisionReason: z.string().trim().max(4000).optional(),
  warningSummary: z.string().trim().max(4000).optional(),
});

export const reviewReasonSchema = z.object({
  reviewId: z.string().uuid(),
  reason: z.string().trim().min(1, "A reason is required.").max(4000),
});

export const reviewAssignSchema = z.object({
  reviewId: z.string().uuid(),
  reviewerUserId: z.string().uuid(),
});
