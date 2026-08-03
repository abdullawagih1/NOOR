"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { toRetrievalEvaluationError } from "@/lib/retrieval-evaluation/errors";
import {
  datasetCreateSchema,
  datasetUpdateSchema,
  datasetIdSchema,
  datasetReturnToDraftSchema,
  corpusItemAddSchema,
  corpusItemRemoveSchema,
  queryCreateSchema,
  queryUpdateSchema,
  judgmentCreateSchema,
  judgmentUpdateSchema,
  createRunSchema,
  cancelRunSchema,
  failureAnnotationCreateSchema,
  failureAnnotationUpdateSchema,
} from "@/lib/retrieval-evaluation/schemas";

function text(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}
function optionalText(formData: FormData, key: string): string | undefined {
  const value = text(formData, key);
  return value.length > 0 ? value : undefined;
}
function checkbox(formData: FormData, key: string): boolean {
  return formData.get(key) === "on" || formData.get(key) === "true";
}

function withError(path: string, message: string): never {
  redirect(`${path}?error=${encodeURIComponent(message)}`);
}

const QUEUE_PATH = "/quality/retrieval-evaluation";
function datasetDetailPath(datasetId: string): string {
  return `/quality/retrieval-evaluation/${datasetId}`;
}
function judgmentsPath(datasetId: string): string {
  return `/quality/retrieval-evaluation/${datasetId}/judgments`;
}
function runDetailPath(datasetId: string, runId: string): string {
  return `/quality/retrieval-evaluation/${datasetId}/runs/${runId}`;
}
function runFailuresPath(datasetId: string, runId: string): string {
  return `/quality/retrieval-evaluation/${datasetId}/runs/${runId}/failures`;
}

/** Parses a comma-separated "1,3,5,10" input into an int array; falls back to the RPC's own default when blank. */
function parseTopKValues(raw: string | undefined): number[] | undefined {
  if (!raw) return undefined;
  const values = raw
    .split(",")
    .map((v) => Number.parseInt(v.trim(), 10))
    .filter((v) => Number.isFinite(v) && v > 0);
  return values.length > 0 ? values : undefined;
}

export async function createRetrievalEvaluationDatasetAction(formData: FormData): Promise<void> {
  const context = await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_CREATE_DATASET);
  const parsed = datasetCreateSchema.safeParse({
    logicalName: text(formData, "logicalName"),
    version: text(formData, "version") || "1",
    title: text(formData, "title"),
    description: optionalText(formData, "description"),
    domainScope: optionalText(formData, "domainScope"),
    languageScope: formData.getAll("languageScope").map(String),
    purpose: optionalText(formData, "purpose"),
    parentDatasetId: optionalText(formData, "parentDatasetId"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid dataset.");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_retrieval_evaluation_dataset", {
    p_organization_id: context.organizationId,
    p_logical_name: parsed.data.logicalName,
    p_version: parsed.data.version,
    p_title: parsed.data.title,
    p_description: parsed.data.description ?? null,
    p_domain_scope: parsed.data.domainScope ?? null,
    p_language_scope: parsed.data.languageScope ?? [],
    p_purpose: parsed.data.purpose ?? null,
    p_parent_dataset_id: parsed.data.parentDatasetId ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(QUEUE_PATH, toRetrievalEvaluationError(error).message);

  const dataset = data as { id: string };
  revalidatePath(QUEUE_PATH);
  redirect(datasetDetailPath(dataset.id));
}

export async function updateRetrievalEvaluationDatasetAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const parsed = datasetUpdateSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    title: optionalText(formData, "title"),
    description: optionalText(formData, "description"),
    domainScope: optionalText(formData, "domainScope"),
    languageScope: formData.getAll("languageScope").map(String),
    purpose: optionalText(formData, "purpose"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_retrieval_evaluation_dataset", {
    p_dataset_id: parsed.data.datasetId,
    p_title: parsed.data.title ?? null,
    p_description: parsed.data.description ?? null,
    p_domain_scope: parsed.data.domainScope ?? null,
    p_language_scope: parsed.data.languageScope && parsed.data.languageScope.length > 0 ? parsed.data.languageScope : null,
    p_purpose: parsed.data.purpose ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function submitDatasetForReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const parsed = datasetIdSchema.safeParse({ datasetId: text(formData, "datasetId") });
  if (!parsed.success) withError(QUEUE_PATH, "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_evaluation_dataset_for_review", {
    p_dataset_id: parsed.data.datasetId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  revalidatePath(QUEUE_PATH);
  redirect(returnTo);
}

export async function returnDatasetToDraftAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_REVIEW_DATASET);
  const parsed = datasetReturnToDraftSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "A reason is required.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("return_evaluation_dataset_to_draft", {
    p_dataset_id: parsed.data.datasetId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  revalidatePath(QUEUE_PATH);
  redirect(returnTo);
}

export async function markDatasetReviewedAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_REVIEW_DATASET);
  const parsed = datasetIdSchema.safeParse({ datasetId: text(formData, "datasetId") });
  if (!parsed.success) withError(QUEUE_PATH, "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_evaluation_dataset_reviewed", {
    p_dataset_id: parsed.data.datasetId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function freezeDatasetAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_FREEZE_DATASET);
  const parsed = datasetIdSchema.safeParse({ datasetId: text(formData, "datasetId") });
  if (!parsed.success) withError(QUEUE_PATH, "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("freeze_retrieval_evaluation_dataset", {
    p_dataset_id: parsed.data.datasetId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  revalidatePath(QUEUE_PATH);
  redirect(returnTo);
}

export async function archiveDatasetAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_ARCHIVE_DATASET);
  const parsed = datasetIdSchema.safeParse({ datasetId: text(formData, "datasetId") });
  if (!parsed.success) withError(QUEUE_PATH, "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("archive_retrieval_evaluation_dataset", {
    p_dataset_id: parsed.data.datasetId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  revalidatePath(QUEUE_PATH);
  redirect(returnTo);
}

export async function addCorpusItemAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const parsed = corpusItemAddSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    chunkId: text(formData, "chunkId"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "A valid chunk ID is required.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("add_evaluation_corpus_item", {
    p_dataset_id: parsed.data.datasetId,
    p_chunk_id: parsed.data.chunkId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function removeCorpusItemAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const parsed = corpusItemRemoveSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    corpusItemId: text(formData, "corpusItemId"),
  });
  if (!parsed.success) withError(QUEUE_PATH, "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("remove_evaluation_corpus_item", {
    p_corpus_item_id: parsed.data.corpusItemId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function createEvaluationQueryAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const parsed = queryCreateSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    queryKey: text(formData, "queryKey"),
    queryText: text(formData, "queryText"),
    language: text(formData, "language"),
    category: text(formData, "category"),
    difficulty: text(formData, "difficulty"),
    isNegativeControl: checkbox(formData, "isNegativeControl"),
    intentNote: optionalText(formData, "intentNote"),
    expectedSourceScope: optionalText(formData, "expectedSourceScope"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid query.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_evaluation_query", {
    p_dataset_id: parsed.data.datasetId,
    p_query_key: parsed.data.queryKey,
    p_query_text: parsed.data.queryText,
    p_language: parsed.data.language,
    p_category: parsed.data.category,
    p_difficulty: parsed.data.difficulty,
    p_is_negative_control: parsed.data.isNegativeControl,
    p_intent_note: parsed.data.intentNote ?? null,
    p_expected_source_scope: parsed.data.expectedSourceScope ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function updateEvaluationQueryAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const parsed = queryUpdateSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    queryId: text(formData, "queryId"),
    queryText: optionalText(formData, "queryText"),
    category: optionalText(formData, "category"),
    difficulty: optionalText(formData, "difficulty"),
    intentNote: optionalText(formData, "intentNote"),
    expectedSourceScope: optionalText(formData, "expectedSourceScope"),
    active: formData.has("active") ? checkbox(formData, "active") : undefined,
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_evaluation_query", {
    p_query_id: parsed.data.queryId,
    p_query_text: parsed.data.queryText ?? null,
    p_category: parsed.data.category ?? null,
    p_difficulty: parsed.data.difficulty ?? null,
    p_intent_note: parsed.data.intentNote ?? null,
    p_expected_source_scope: parsed.data.expectedSourceScope ?? null,
    p_active: parsed.data.active ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function createRelevanceJudgmentAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const parsed = judgmentCreateSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    queryId: text(formData, "queryId"),
    corpusItemId: text(formData, "corpusItemId"),
    relevanceGrade: text(formData, "relevanceGrade"),
    rationale: optionalText(formData, "rationale"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid judgment.");
  const returnTo = judgmentsPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_relevance_judgment", {
    p_query_id: parsed.data.queryId,
    p_corpus_item_id: parsed.data.corpusItemId,
    p_relevance_grade: parsed.data.relevanceGrade,
    p_rationale: parsed.data.rationale ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function updateRelevanceJudgmentAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const parsed = judgmentUpdateSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    judgmentId: text(formData, "judgmentId"),
    relevanceGrade: optionalText(formData, "relevanceGrade"),
    rationale: optionalText(formData, "rationale"),
    reviewStatus: optionalText(formData, "reviewStatus"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = judgmentsPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_relevance_judgment", {
    p_judgment_id: parsed.data.judgmentId,
    p_relevance_grade: parsed.data.relevanceGrade ?? null,
    p_rationale: parsed.data.rationale ?? null,
    p_review_status: parsed.data.reviewStatus ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function createEvaluationRunAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_RUN);
  const parsed = createRunSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    topKValues: optionalText(formData, "topKValues"),
    relevanceThreshold: optionalText(formData, "relevanceThreshold"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const topKValues = parseTopKValues(parsed.data.topKValues);

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_retrieval_evaluation_run", {
    p_dataset_id: parsed.data.datasetId,
    p_top_k_values: topKValues ?? [1, 3, 5, 10],
    p_relevance_threshold: parsed.data.relevanceThreshold ?? 2,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  const rows = data as { out_run_id: string; out_job_id: string; out_status: string; out_reused: boolean }[];
  const run = rows[0];
  revalidatePath(returnTo);
  if (run) {
    redirect(runDetailPath(parsed.data.datasetId, run.out_run_id));
  }
  redirect(returnTo);
}

export async function createQueryEmbeddingsForDatasetAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_RUN);
  const parsed = datasetIdSchema.safeParse({ datasetId: text(formData, "datasetId") });
  if (!parsed.success) withError(QUEUE_PATH, "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_query_embeddings_for_dataset", {
    p_dataset_id: parsed.data.datasetId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function createVectorEvaluationRunAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_RUN);
  const parsed = createRunSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    topKValues: optionalText(formData, "topKValues"),
    relevanceThreshold: optionalText(formData, "relevanceThreshold"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = datasetDetailPath(parsed.data.datasetId);

  const topKValues = parseTopKValues(parsed.data.topKValues);

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_vector_evaluation_run", {
    p_dataset_id: parsed.data.datasetId,
    p_top_k_values: topKValues ?? [1, 3, 5, 10],
    p_relevance_threshold: parsed.data.relevanceThreshold ?? 2,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  const rows = data as { out_run_id: string; out_job_id: string; out_status: string; out_reused: boolean }[];
  const run = rows[0];
  revalidatePath(returnTo);
  if (run) {
    redirect(runDetailPath(parsed.data.datasetId, run.out_run_id));
  }
  redirect(returnTo);
}

export async function cancelEvaluationRunAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_CANCEL_RUN);
  const parsed = cancelRunSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    runId: text(formData, "runId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "A reason is required.");
  const returnTo = runDetailPath(parsed.data.datasetId, parsed.data.runId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_evaluation_run", {
    p_run_id: parsed.data.runId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function createFailureAnnotationAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_ANNOTATE_FAILURES);
  const parsed = failureAnnotationCreateSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    runId: text(formData, "runId"),
    queryId: text(formData, "queryId"),
    failureCategory: text(formData, "failureCategory"),
    reviewerNote: optionalText(formData, "reviewerNote"),
    recommendedExperiment: optionalText(formData, "recommendedExperiment"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid annotation.");
  const returnTo = runFailuresPath(parsed.data.datasetId, parsed.data.runId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_failure_annotation", {
    p_evaluation_run_id: parsed.data.runId,
    p_query_id: parsed.data.queryId,
    p_failure_category: parsed.data.failureCategory,
    p_reviewer_note: parsed.data.reviewerNote ?? null,
    p_recommended_experiment: parsed.data.recommendedExperiment ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function updateFailureAnnotationAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_ANNOTATE_FAILURES);
  const parsed = failureAnnotationUpdateSchema.safeParse({
    datasetId: text(formData, "datasetId"),
    runId: text(formData, "runId"),
    failureId: text(formData, "failureId"),
    status: optionalText(formData, "status"),
    reviewerNote: optionalText(formData, "reviewerNote"),
    recommendedExperiment: optionalText(formData, "recommendedExperiment"),
  });
  if (!parsed.success) withError(QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = runFailuresPath(parsed.data.datasetId, parsed.data.runId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_failure_annotation", {
    p_failure_id: parsed.data.failureId,
    p_status: parsed.data.status ?? null,
    p_reviewer_note: parsed.data.reviewerNote ?? null,
    p_recommended_experiment: parsed.data.recommendedExperiment ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toRetrievalEvaluationError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}
