import { z } from "zod";
import { CHUNK_FINDING_TYPES } from "@/lib/chunking/queries";

export const chunkingJobCreateSchema = z.object({
  sourceDocumentId: z.string().uuid(),
});

export const chunkingReviewReasonSchema = z.object({
  chunkingReviewId: z.string().uuid(),
  reason: z.string().trim().min(1, "A reason is required.").max(4000),
});

export const chunkingRunReasonSchema = z.object({
  chunkingRunId: z.string().uuid(),
  reason: z.string().trim().min(1, "A reason is required.").max(4000),
});

export const chunkingReviewAssignSchema = z.object({
  chunkingReviewId: z.string().uuid(),
  reviewerUserId: z.string().uuid(),
});

export const chunkReviewedSchema = z.object({
  chunkingReviewId: z.string().uuid(),
  chunkIndex: z.coerce.number().int().min(1),
  reviewStatus: z.enum(["reviewed_clear", "reviewed_with_findings", "rechunk_candidate", "rejected"]),
  notes: z.string().trim().max(2000).optional(),
});

export const chunkFindingCreateSchema = z.object({
  chunkingReviewId: z.string().uuid(),
  chunkIndex: z.coerce.number().int().min(1).optional(),
  findingType: z.enum(CHUNK_FINDING_TYPES),
  severity: z.enum(["informational", "minor", "major", "critical"]),
  title: z.string().trim().min(1, "A title is required.").max(200),
  description: z.string().trim().max(4000).optional(),
  suggestedAction: z.string().trim().max(2000).optional(),
});

export const chunkFindingStatusUpdateSchema = z.object({
  chunkingReviewId: z.string().uuid(),
  findingId: z.string().uuid(),
  status: z.enum(["open", "acknowledged", "resolved", "accepted_risk", "dismissed"]),
  resolutionNote: z.string().trim().max(2000).optional(),
});

export const chunkingReviewSubmitSchema = z.object({
  chunkingReviewId: z.string().uuid(),
  targetStatus: z.enum(["accepted", "accepted_with_warnings", "rechunk_required", "rejected"]),
  decisionReason: z.string().trim().max(4000).optional(),
  warningSummary: z.string().trim().max(4000).optional(),
});
