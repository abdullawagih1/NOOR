import { z } from "zod";
import { OCR_FINDING_TYPES } from "@/lib/ocr/queries";

export const ocrRequestCreateSchema = z.object({
  extractionReviewId: z.string().uuid(),
});

export const ocrRequestReasonSchema = z.object({
  ocrRequestId: z.string().uuid(),
  reason: z.string().trim().min(1, "A reason is required.").max(4000),
});

export const ocrReviewReasonSchema = z.object({
  ocrReviewId: z.string().uuid(),
  reason: z.string().trim().min(1, "A reason is required.").max(4000),
});

export const ocrReviewAssignSchema = z.object({
  ocrReviewId: z.string().uuid(),
  reviewerUserId: z.string().uuid(),
});

export const ocrPageReviewedSchema = z.object({
  ocrReviewId: z.string().uuid(),
  pageNumber: z.coerce.number().int().min(1),
  pageReviewStatus: z.enum(["accepted", "accepted_with_warnings", "reprocessing_required", "rejected"]),
  notes: z.string().trim().max(2000).optional(),
});

export const ocrFindingCreateSchema = z.object({
  ocrReviewId: z.string().uuid(),
  pageNumber: z.coerce.number().int().min(1),
  findingType: z.enum(OCR_FINDING_TYPES),
  severity: z.enum(["informational", "minor", "major", "critical"]),
  title: z.string().trim().min(1, "A title is required.").max(200),
  description: z.string().trim().max(4000).optional(),
  suggestedAction: z.string().trim().max(2000).optional(),
});

export const ocrFindingStatusUpdateSchema = z.object({
  ocrReviewId: z.string().uuid(),
  findingId: z.string().uuid(),
  status: z.enum(["open", "acknowledged", "resolved", "accepted_risk", "dismissed"]),
  resolutionNote: z.string().trim().max(2000).optional(),
});

export const ocrReviewSubmitSchema = z.object({
  ocrReviewId: z.string().uuid(),
  targetStatus: z.enum(["accepted", "accepted_with_warnings", "reprocessing_required", "rejected"]),
  decisionReason: z.string().trim().max(4000).optional(),
  warningSummary: z.string().trim().max(4000).optional(),
});
