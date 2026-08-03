import { z } from "zod";

export const createEmbeddingJobSchema = z.object({
  sourceDocumentId: z.string().uuid(),
});

export const cancelEmbeddingRunSchema = z.object({
  embeddingRunId: z.string().uuid(),
  reason: z.string().trim().min(1, "A reason is required.").max(4000),
});
