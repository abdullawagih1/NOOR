import { z } from "zod";
import { QUERY_CATEGORIES, QUERY_DIFFICULTIES, RETRIEVAL_EVALUATION_LANGUAGES, FAILURE_CATEGORIES } from "@/lib/retrieval-evaluation/queries";

export const datasetCreateSchema = z.object({
  logicalName: z.string().trim().min(1, "A logical name is required.").max(200),
  version: z.coerce.number().int().min(1),
  title: z.string().trim().min(1, "A title is required.").max(300),
  description: z.string().trim().max(4000).optional(),
  domainScope: z.string().trim().max(300).optional(),
  languageScope: z.array(z.enum(RETRIEVAL_EVALUATION_LANGUAGES)).optional(),
  purpose: z.string().trim().max(2000).optional(),
  parentDatasetId: z.string().uuid().optional(),
});

export const datasetUpdateSchema = z.object({
  datasetId: z.string().uuid(),
  title: z.string().trim().min(1, "A title is required.").max(300).optional(),
  description: z.string().trim().max(4000).optional(),
  domainScope: z.string().trim().max(300).optional(),
  languageScope: z.array(z.enum(RETRIEVAL_EVALUATION_LANGUAGES)).optional(),
  purpose: z.string().trim().max(2000).optional(),
});

export const datasetIdSchema = z.object({
  datasetId: z.string().uuid(),
});

export const datasetReturnToDraftSchema = z.object({
  datasetId: z.string().uuid(),
  reason: z.string().trim().min(1, "A reason is required.").max(4000),
});

export const corpusItemAddSchema = z.object({
  datasetId: z.string().uuid(),
  chunkId: z.string().uuid(),
});

export const corpusItemRemoveSchema = z.object({
  datasetId: z.string().uuid(),
  corpusItemId: z.string().uuid(),
});

export const queryCreateSchema = z.object({
  datasetId: z.string().uuid(),
  queryKey: z.string().trim().min(1, "A query key is required.").max(120),
  queryText: z.string().trim().min(1, "Query text is required.").max(2000),
  language: z.enum(RETRIEVAL_EVALUATION_LANGUAGES),
  category: z.enum(QUERY_CATEGORIES),
  difficulty: z.enum(QUERY_DIFFICULTIES),
  isNegativeControl: z.coerce.boolean().optional().default(false),
  intentNote: z.string().trim().max(2000).optional(),
  expectedSourceScope: z.string().trim().max(2000).optional(),
});

export const queryUpdateSchema = z.object({
  datasetId: z.string().uuid(),
  queryId: z.string().uuid(),
  queryText: z.string().trim().max(2000).optional(),
  category: z.enum(QUERY_CATEGORIES).optional(),
  difficulty: z.enum(QUERY_DIFFICULTIES).optional(),
  intentNote: z.string().trim().max(2000).optional(),
  expectedSourceScope: z.string().trim().max(2000).optional(),
  active: z.coerce.boolean().optional(),
});

export const judgmentCreateSchema = z.object({
  datasetId: z.string().uuid(),
  queryId: z.string().uuid(),
  corpusItemId: z.string().uuid(),
  relevanceGrade: z.coerce.number().int().min(0).max(3),
  rationale: z.string().trim().max(2000).optional(),
});

export const judgmentUpdateSchema = z.object({
  datasetId: z.string().uuid(),
  judgmentId: z.string().uuid(),
  relevanceGrade: z.coerce.number().int().min(0).max(3).optional(),
  rationale: z.string().trim().max(2000).optional(),
  reviewStatus: z.enum(["pending_review", "confirmed"]).optional(),
});

export const createRunSchema = z.object({
  datasetId: z.string().uuid(),
  topKValues: z.string().trim().max(60).optional(),
  relevanceThreshold: z.coerce.number().int().min(0).max(3).optional(),
});

export const cancelRunSchema = z.object({
  datasetId: z.string().uuid(),
  runId: z.string().uuid(),
  reason: z.string().trim().min(1, "A reason is required.").max(4000),
});

export const failureAnnotationCreateSchema = z.object({
  datasetId: z.string().uuid(),
  runId: z.string().uuid(),
  queryId: z.string().uuid(),
  failureCategory: z.enum(FAILURE_CATEGORIES),
  reviewerNote: z.string().trim().max(4000).optional(),
  recommendedExperiment: z.string().trim().max(4000).optional(),
});

export const failureAnnotationUpdateSchema = z.object({
  datasetId: z.string().uuid(),
  runId: z.string().uuid(),
  failureId: z.string().uuid(),
  status: z.enum(["open", "acknowledged", "resolved"]).optional(),
  reviewerNote: z.string().trim().max(4000).optional(),
  recommendedExperiment: z.string().trim().max(4000).optional(),
});
