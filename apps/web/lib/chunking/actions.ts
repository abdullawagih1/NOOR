"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { toChunkingReviewError } from "@/lib/chunking/errors";
import {
  chunkingJobCreateSchema,
  chunkingReviewReasonSchema,
  chunkingRunReasonSchema,
  chunkingReviewAssignSchema,
  chunkReviewedSchema,
  chunkFindingCreateSchema,
  chunkFindingStatusUpdateSchema,
  chunkingReviewSubmitSchema,
} from "@/lib/chunking/schemas";

function text(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}
function optionalText(formData: FormData, key: string): string | undefined {
  const value = text(formData, key);
  return value.length > 0 ? value : undefined;
}

function withError(path: string, message: string): never {
  redirect(`${path}?error=${encodeURIComponent(message)}`);
}

const CHUNKING_REVIEW_QUEUE_PATH = "/reviewer/chunking";
function chunkingReviewDetailPath(chunkingReviewId: string): string {
  return `/reviewer/chunking/${chunkingReviewId}`;
}

/**
 * Requests a chunking job for a chunking-eligible document (guideline
 * detail page). Never accepts chunker version/config from the browser —
 * create_document_chunking_job (migration 0012) resolves the current
 * pinned identity itself, unlike OCR's request action which must submit a
 * provider/model identity because OCR calls an external tool.
 */
export async function createChunkingJobAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_CREATE);
  const parsed = chunkingJobCreateSchema.safeParse({ sourceDocumentId: text(formData, "sourceDocumentId") });
  const guidelineId = text(formData, "guidelineId");
  const returnTo = guidelineId ? `/knowledge/guidelines/${guidelineId}` : CHUNKING_REVIEW_QUEUE_PATH;
  if (!parsed.success) withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid request.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_document_chunking_job", {
    p_source_document_id: parsed.data.sourceDocumentId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toChunkingReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

/** Opens the chunk technical review once a chunking run has succeeded. */
export async function createChunkingReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_CREATE);
  const chunkingRunId = text(formData, "chunkingRunId");
  const guidelineId = text(formData, "guidelineId");
  const returnTo = guidelineId ? `/knowledge/guidelines/${guidelineId}` : CHUNKING_REVIEW_QUEUE_PATH;

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_document_chunking_review", { p_chunking_run_id: chunkingRunId, p_correlation_id: randomUUID() });
  if (error) withError(returnTo, toChunkingReviewError(error).message);

  const review = data as { id: string };
  revalidatePath(CHUNKING_REVIEW_QUEUE_PATH);
  redirect(chunkingReviewDetailPath(review.id));
}

export async function assignChunkingReviewerAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW);
  const parsed = chunkingReviewAssignSchema.safeParse({
    chunkingReviewId: text(formData, "chunkingReviewId"),
    reviewerUserId: text(formData, "reviewerUserId"),
  });
  if (!parsed.success) withError(CHUNKING_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = chunkingReviewDetailPath(parsed.data.chunkingReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("assign_chunking_reviewer", {
    p_review_id: parsed.data.chunkingReviewId,
    p_reviewer_user_id: parsed.data.reviewerUserId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toChunkingReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function claimChunkingReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW);
  const chunkingReviewId = text(formData, "chunkingReviewId");
  const returnTo = chunkingReviewDetailPath(chunkingReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("claim_chunking_review", { p_review_id: chunkingReviewId, p_correlation_id: randomUUID() });
  if (error) withError(returnTo, toChunkingReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function startChunkingReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW);
  const chunkingReviewId = text(formData, "chunkingReviewId");
  const returnTo = chunkingReviewDetailPath(chunkingReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("start_document_chunking_review", { p_review_id: chunkingReviewId, p_correlation_id: randomUUID() });
  if (error) withError(returnTo, toChunkingReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function markChunkReviewedAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW);
  const parsed = chunkReviewedSchema.safeParse({
    chunkingReviewId: text(formData, "chunkingReviewId"),
    chunkIndex: text(formData, "chunkIndex"),
    reviewStatus: text(formData, "reviewStatus"),
    notes: optionalText(formData, "notes"),
  });
  if (!parsed.success) withError(CHUNKING_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = chunkingReviewDetailPath(parsed.data.chunkingReviewId) + `?chunk=${parsed.data.chunkIndex}`;

  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_chunk_reviewed", {
    p_review_id: parsed.data.chunkingReviewId,
    p_chunk_index: parsed.data.chunkIndex,
    p_review_status: parsed.data.reviewStatus,
    p_notes: parsed.data.notes ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(chunkingReviewDetailPath(parsed.data.chunkingReviewId), toChunkingReviewError(error).message);

  revalidatePath(chunkingReviewDetailPath(parsed.data.chunkingReviewId));
  redirect(returnTo);
}

export async function createChunkFindingAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW);
  const parsed = chunkFindingCreateSchema.safeParse({
    chunkingReviewId: text(formData, "chunkingReviewId"),
    chunkIndex: optionalText(formData, "chunkIndex"),
    findingType: text(formData, "findingType"),
    severity: text(formData, "severity"),
    title: text(formData, "title"),
    description: optionalText(formData, "description"),
    suggestedAction: optionalText(formData, "suggestedAction"),
  });
  if (!parsed.success) withError(CHUNKING_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid finding.");
  const returnTo = chunkingReviewDetailPath(parsed.data.chunkingReviewId) + (parsed.data.chunkIndex ? `?chunk=${parsed.data.chunkIndex}` : "");

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_chunk_finding", {
    p_review_id: parsed.data.chunkingReviewId,
    p_chunk_index: parsed.data.chunkIndex ?? null,
    p_finding_type: parsed.data.findingType,
    p_severity: parsed.data.severity,
    p_title: parsed.data.title,
    p_description: parsed.data.description ?? null,
    p_suggested_action: parsed.data.suggestedAction ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(chunkingReviewDetailPath(parsed.data.chunkingReviewId), toChunkingReviewError(error).message);

  revalidatePath(chunkingReviewDetailPath(parsed.data.chunkingReviewId));
  redirect(returnTo);
}

export async function updateChunkFindingStatusAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW);
  const parsed = chunkFindingStatusUpdateSchema.safeParse({
    chunkingReviewId: text(formData, "chunkingReviewId"),
    findingId: text(formData, "findingId"),
    status: text(formData, "status"),
    resolutionNote: optionalText(formData, "resolutionNote"),
  });
  if (!parsed.success) withError(CHUNKING_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = chunkingReviewDetailPath(parsed.data.chunkingReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_chunk_finding_status", {
    p_finding_id: parsed.data.findingId,
    p_status: parsed.data.status,
    p_resolution_note: parsed.data.resolutionNote ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toChunkingReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function submitChunkingReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_SUBMIT_REVIEW);
  const parsed = chunkingReviewSubmitSchema.safeParse({
    chunkingReviewId: text(formData, "chunkingReviewId"),
    targetStatus: text(formData, "targetStatus"),
    decisionReason: optionalText(formData, "decisionReason"),
    warningSummary: optionalText(formData, "warningSummary"),
  });
  if (!parsed.success) withError(CHUNKING_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid decision.");
  const returnTo = chunkingReviewDetailPath(parsed.data.chunkingReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_document_chunking_review", {
    p_review_id: parsed.data.chunkingReviewId,
    p_target_status: parsed.data.targetStatus,
    p_decision_reason: parsed.data.decisionReason ?? null,
    p_warning_summary: parsed.data.warningSummary ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toChunkingReviewError(error).message);

  revalidatePath(returnTo);
  revalidatePath(CHUNKING_REVIEW_QUEUE_PATH);
  redirect(returnTo);
}

export async function reopenChunkingReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_REOPEN_REVIEW);
  const parsed = chunkingReviewReasonSchema.safeParse({
    chunkingReviewId: text(formData, "chunkingReviewId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(CHUNKING_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "A reason is required.");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("reopen_chunking_review", {
    p_review_id: parsed.data.chunkingReviewId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(chunkingReviewDetailPath(parsed.data.chunkingReviewId), toChunkingReviewError(error).message);

  const newReview = data as { id: string };
  revalidatePath(CHUNKING_REVIEW_QUEUE_PATH);
  redirect(chunkingReviewDetailPath(newReview.id));
}

export async function invalidateChunkingRunAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_INVALIDATE);
  const parsed = chunkingRunReasonSchema.safeParse({
    chunkingRunId: text(formData, "chunkingRunId"),
    reason: text(formData, "reason"),
  });
  const guidelineId = text(formData, "guidelineId");
  const returnTo = guidelineId ? `/knowledge/guidelines/${guidelineId}` : CHUNKING_REVIEW_QUEUE_PATH;
  if (!parsed.success) withError(returnTo, parsed.error.issues[0]?.message ?? "A reason is required.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("invalidate_document_chunking_run", {
    p_chunking_run_id: parsed.data.chunkingRunId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toChunkingReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}
