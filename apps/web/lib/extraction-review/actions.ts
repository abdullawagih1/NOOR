"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { toExtractionReviewError, ExtractionReviewError } from "@/lib/extraction-review/errors";
import {
  findingCreateSchema,
  findingStatusUpdateSchema,
  pageReviewedSchema,
  reviewSubmitSchema,
  reviewReasonSchema,
  reviewAssignSchema,
} from "@/lib/extraction-review/schemas";

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

const REVIEW_QUEUE_PATH = "/reviewer/extractions";
function reviewDetailPath(reviewId: string): string {
  return `/reviewer/extractions/${reviewId}`;
}

/**
 * Step 1 of the review flow: opens (or reuses, idempotently) an extraction
 * review round for a succeeded extraction run, then redirects straight into
 * it. Called from the guideline detail page's Extraction Summary Card.
 */
export async function createExtractionReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_CREATE);
  const extractionRunId = text(formData, "extractionRunId");
  const guidelineId = text(formData, "guidelineId");
  const returnTo = guidelineId ? `/knowledge/guidelines/${guidelineId}` : REVIEW_QUEUE_PATH;

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_document_extraction_review", {
    p_extraction_run_id: extractionRunId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toExtractionReviewError(error).message);

  const review = data as { id: string };
  revalidatePath(REVIEW_QUEUE_PATH);
  redirect(reviewDetailPath(review.id));
}

export async function assignExtractionReviewerAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_ASSIGN);
  const parsed = reviewAssignSchema.safeParse({
    reviewId: text(formData, "reviewId"),
    reviewerUserId: text(formData, "reviewerUserId"),
  });
  if (!parsed.success) withError(REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = reviewDetailPath(parsed.data.reviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("assign_extraction_reviewer", {
    p_review_id: parsed.data.reviewId,
    p_reviewer_user_id: parsed.data.reviewerUserId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toExtractionReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function claimExtractionReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_REVIEW);
  const reviewId = text(formData, "reviewId");
  const returnTo = reviewDetailPath(reviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("claim_extraction_review", { p_review_id: reviewId, p_correlation_id: randomUUID() });
  if (error) withError(returnTo, toExtractionReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function startExtractionReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_REVIEW);
  const reviewId = text(formData, "reviewId");
  const returnTo = reviewDetailPath(reviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("start_document_extraction_review", { p_review_id: reviewId, p_correlation_id: randomUUID() });
  if (error) withError(returnTo, toExtractionReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function markExtractionPageReviewedAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_REVIEW);
  const parsed = pageReviewedSchema.safeParse({
    reviewId: text(formData, "reviewId"),
    pageNumber: text(formData, "pageNumber"),
    pageReviewStatus: text(formData, "pageReviewStatus"),
    notes: optionalText(formData, "notes"),
  });
  if (!parsed.success) withError(REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = reviewDetailPath(parsed.data.reviewId) + `?page=${parsed.data.pageNumber}`;

  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_extraction_page_reviewed", {
    p_review_id: parsed.data.reviewId,
    p_page_number: parsed.data.pageNumber,
    p_page_review_status: parsed.data.pageReviewStatus,
    p_notes: parsed.data.notes ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(reviewDetailPath(parsed.data.reviewId), toExtractionReviewError(error).message);

  revalidatePath(reviewDetailPath(parsed.data.reviewId));
  redirect(returnTo);
}

export async function createExtractionFindingAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_FINDINGS_CREATE);
  const pageNumber = optionalText(formData, "pageNumber");
  const parsed = findingCreateSchema.safeParse({
    reviewId: text(formData, "reviewId"),
    extractionPageId: optionalText(formData, "extractionPageId"),
    findingType: text(formData, "findingType"),
    severity: text(formData, "severity"),
    title: text(formData, "title"),
    description: optionalText(formData, "description"),
    suggestedAction: optionalText(formData, "suggestedAction"),
  });
  if (!parsed.success) withError(REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid finding.");
  const returnTo = reviewDetailPath(parsed.data.reviewId) + (pageNumber ? `?page=${pageNumber}` : "");

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_extraction_finding", {
    p_review_id: parsed.data.reviewId,
    p_finding_type: parsed.data.findingType,
    p_severity: parsed.data.severity,
    p_title: parsed.data.title,
    p_extraction_page_id: parsed.data.extractionPageId ?? null,
    p_description: parsed.data.description ?? null,
    p_suggested_action: parsed.data.suggestedAction ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(reviewDetailPath(parsed.data.reviewId), toExtractionReviewError(error).message);

  revalidatePath(reviewDetailPath(parsed.data.reviewId));
  redirect(returnTo);
}

export async function updateExtractionFindingStatusAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_FINDINGS_RESOLVE);
  const reviewId = text(formData, "reviewId");
  const parsed = findingStatusUpdateSchema.safeParse({
    findingId: text(formData, "findingId"),
    status: text(formData, "status"),
    resolutionNote: optionalText(formData, "resolutionNote"),
  });
  if (!parsed.success) withError(reviewDetailPath(reviewId), parsed.error.issues[0]?.message ?? "Invalid request.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_extraction_finding_status", {
    p_finding_id: parsed.data.findingId,
    p_status: parsed.data.status,
    p_resolution_note: parsed.data.resolutionNote ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(reviewDetailPath(reviewId), toExtractionReviewError(error).message);

  revalidatePath(reviewDetailPath(reviewId));
  redirect(reviewDetailPath(reviewId));
}

export async function submitExtractionReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_SUBMIT);
  const parsed = reviewSubmitSchema.safeParse({
    reviewId: text(formData, "reviewId"),
    targetStatus: text(formData, "targetStatus"),
    decisionReason: optionalText(formData, "decisionReason"),
    warningSummary: optionalText(formData, "warningSummary"),
  });
  if (!parsed.success) withError(REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid decision.");
  const returnTo = reviewDetailPath(parsed.data.reviewId);
  const idempotencyKey = text(formData, "idempotencyKey") || randomUUID();

  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_document_extraction_review", {
    p_review_id: parsed.data.reviewId,
    p_target_status: parsed.data.targetStatus,
    p_decision_reason: parsed.data.decisionReason ?? null,
    p_warning_summary: parsed.data.warningSummary ?? null,
    p_idempotency_key: idempotencyKey,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toExtractionReviewError(error).message);

  revalidatePath(returnTo);
  revalidatePath(REVIEW_QUEUE_PATH);
  redirect(returnTo);
}

export async function reopenExtractionReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_REOPEN);
  const parsed = reviewReasonSchema.safeParse({
    reviewId: text(formData, "reviewId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "A reason is required.");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("reopen_extraction_review", {
    p_review_id: parsed.data.reviewId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(reviewDetailPath(parsed.data.reviewId), toExtractionReviewError(error).message);

  const newReview = data as { id: string };
  revalidatePath(REVIEW_QUEUE_PATH);
  redirect(reviewDetailPath(newReview.id));
}

export async function invalidateExtractionReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_REOPEN);
  const parsed = reviewReasonSchema.safeParse({
    reviewId: text(formData, "reviewId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "A reason is required.");
  const returnTo = reviewDetailPath(parsed.data.reviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("invalidate_extraction_review", {
    p_review_id: parsed.data.reviewId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toExtractionReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export interface SignedSourceAccess {
  signedUrl: string;
  expiresAt: string;
  sourceDocumentId: string;
}

const SIGNED_SOURCE_URL_TTL_SECONDS = 300;

/**
 * Mints a short-lived signed read URL for the original source PDF, for the
 * review workspace's PDF panel. No service-role key anywhere — uses this
 * same session's own client, so the existing org-scoped `storage.objects`
 * RLS policy (migration 0003) is what actually authorizes the read, exactly
 * like the rest of this codebase's Storage access. `requirePermission`
 * here is what actually distinguishes a reviewer from a clinician for
 * Noor's own UI; see docs/security/extraction-review-authorization.md for
 * the documented limitation that storage.objects RLS itself remains
 * organization-scoped, not permission-scoped (a pre-existing Sprint 1.1
 * characteristic, not something this Sprint changes).
 */
export async function createExtractionReviewSourceAccessAction(extractionRunId: string): Promise<SignedSourceAccess> {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_SOURCE_READ);
  const supabase = await createClient();

  const { data: run, error: runError } = await supabase
    .from("document_extraction_runs")
    .select("id, organization_id, source_document_id")
    .eq("id", extractionRunId)
    .maybeSingle();
  if (runError) throw toExtractionReviewError(runError);
  if (!run || run.organization_id !== context.organizationId) {
    throw new ExtractionReviewError("Extraction run not found.", "not_found");
  }

  const { data: doc, error: docError } = await supabase
    .from("guideline_source_documents")
    .select("id, organization_id, storage_bucket, storage_path")
    .eq("id", run.source_document_id)
    .maybeSingle();
  if (docError) throw toExtractionReviewError(docError);
  if (!doc || doc.organization_id !== context.organizationId) {
    throw new ExtractionReviewError("Source document not found.", "not_found");
  }

  const { data: signed, error: signError } = await supabase.storage
    .from(doc.storage_bucket)
    .createSignedUrl(doc.storage_path, SIGNED_SOURCE_URL_TTL_SECONDS);
  if (signError || !signed) {
    throw new ExtractionReviewError("Could not create signed access to the source document.", "signing_failed");
  }

  return {
    signedUrl: signed.signedUrl,
    expiresAt: new Date(Date.now() + SIGNED_SOURCE_URL_TTL_SECONDS * 1000).toISOString(),
    sourceDocumentId: doc.id,
  };
}
