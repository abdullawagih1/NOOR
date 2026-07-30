"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { toOcrReviewError, OcrReviewError } from "@/lib/ocr/errors";
import {
  ocrRequestCreateSchema,
  ocrRequestReasonSchema,
  ocrReviewReasonSchema,
  ocrReviewAssignSchema,
  ocrPageReviewedSchema,
  ocrFindingCreateSchema,
  ocrFindingStatusUpdateSchema,
  ocrReviewSubmitSchema,
} from "@/lib/ocr/schemas";
import {
  OCR_RENDERER_NAME,
  OCR_RENDERER_VERSION,
  OCR_RENDER_CONFIGURATION_VERSION,
  OCR_PROVIDER_NAME,
  OCR_PROVIDER_VERSION,
  OCR_MODEL_IDENTIFIER,
  OCR_MODEL_VERSION,
  OCR_CONFIGURATION_VERSION,
  OCR_SUPPORTED_LANGUAGE_HINTS,
} from "@/lib/ocr/config";

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

const OCR_REVIEW_QUEUE_PATH = "/reviewer/ocr";
function ocrReviewDetailPath(ocrReviewId: string): string {
  return `/reviewer/ocr/${ocrReviewId}`;
}

/**
 * Step 1 of the OCR flow: creates (or idempotently reuses) a controlled OCR
 * request from an ocr_required extraction review, submitting the current
 * pinned OCR identity (apps/web/lib/ocr/config.ts, mirroring
 * apps/worker/app/ocr/config.py) — never an arbitrary browser-supplied
 * provider/model/renderer value (mission §13/§23). Called from the
 * guideline detail page's extraction summary card.
 */
export async function createOcrRequestAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_CREATE);
  const parsed = ocrRequestCreateSchema.safeParse({ extractionReviewId: text(formData, "extractionReviewId") });
  const guidelineId = text(formData, "guidelineId");
  const returnTo = guidelineId ? `/knowledge/guidelines/${guidelineId}` : OCR_REVIEW_QUEUE_PATH;
  if (!parsed.success) withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid request.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_document_ocr_request", {
    p_extraction_review_id: parsed.data.extractionReviewId,
    p_provider_name: OCR_PROVIDER_NAME,
    p_provider_version: OCR_PROVIDER_VERSION,
    p_model_identifier: OCR_MODEL_IDENTIFIER,
    p_model_version: OCR_MODEL_VERSION,
    p_renderer_name: OCR_RENDERER_NAME,
    p_renderer_version: OCR_RENDERER_VERSION,
    p_render_configuration_version: OCR_RENDER_CONFIGURATION_VERSION,
    p_ocr_configuration_version: OCR_CONFIGURATION_VERSION,
    p_language_hints: [...OCR_SUPPORTED_LANGUAGE_HINTS],
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function cancelOcrRequestAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_CANCEL);
  const parsed = ocrRequestReasonSchema.safeParse({
    ocrRequestId: text(formData, "ocrRequestId"),
    reason: text(formData, "reason"),
  });
  const guidelineId = text(formData, "guidelineId");
  const returnTo = guidelineId ? `/knowledge/guidelines/${guidelineId}` : OCR_REVIEW_QUEUE_PATH;
  if (!parsed.success) withError(returnTo, parsed.error.issues[0]?.message ?? "A reason is required.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_document_ocr_request", {
    p_ocr_request_id: parsed.data.ocrRequestId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

/** Step 2: opens the OCR technical review once every page job has reached a terminal state. */
export async function createOcrReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_CREATE);
  const ocrRequestId = text(formData, "ocrRequestId");
  const guidelineId = text(formData, "guidelineId");
  const returnTo = guidelineId ? `/knowledge/guidelines/${guidelineId}` : OCR_REVIEW_QUEUE_PATH;

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_document_ocr_review", { p_ocr_request_id: ocrRequestId, p_correlation_id: randomUUID() });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  const review = data as { id: string };
  revalidatePath(OCR_REVIEW_QUEUE_PATH);
  redirect(ocrReviewDetailPath(review.id));
}

export async function assignOcrReviewerAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_REVIEW);
  const parsed = ocrReviewAssignSchema.safeParse({
    ocrReviewId: text(formData, "ocrReviewId"),
    reviewerUserId: text(formData, "reviewerUserId"),
  });
  if (!parsed.success) withError(OCR_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = ocrReviewDetailPath(parsed.data.ocrReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("assign_ocr_reviewer", {
    p_ocr_review_id: parsed.data.ocrReviewId,
    p_reviewer_user_id: parsed.data.reviewerUserId,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function claimOcrReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_REVIEW);
  const ocrReviewId = text(formData, "ocrReviewId");
  const returnTo = ocrReviewDetailPath(ocrReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("claim_ocr_review", { p_ocr_review_id: ocrReviewId, p_correlation_id: randomUUID() });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function startOcrReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_REVIEW);
  const ocrReviewId = text(formData, "ocrReviewId");
  const returnTo = ocrReviewDetailPath(ocrReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("start_document_ocr_review", { p_ocr_review_id: ocrReviewId, p_correlation_id: randomUUID() });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function markOcrPageReviewedAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_REVIEW);
  const parsed = ocrPageReviewedSchema.safeParse({
    ocrReviewId: text(formData, "ocrReviewId"),
    pageNumber: text(formData, "pageNumber"),
    pageReviewStatus: text(formData, "pageReviewStatus"),
    notes: optionalText(formData, "notes"),
  });
  if (!parsed.success) withError(OCR_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = ocrReviewDetailPath(parsed.data.ocrReviewId) + `?page=${parsed.data.pageNumber}`;

  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_ocr_page_reviewed", {
    p_ocr_review_id: parsed.data.ocrReviewId,
    p_page_number: parsed.data.pageNumber,
    p_page_review_status: parsed.data.pageReviewStatus,
    p_notes: parsed.data.notes ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(ocrReviewDetailPath(parsed.data.ocrReviewId), toOcrReviewError(error).message);

  revalidatePath(ocrReviewDetailPath(parsed.data.ocrReviewId));
  redirect(returnTo);
}

export async function createOcrFindingAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_REVIEW);
  const parsed = ocrFindingCreateSchema.safeParse({
    ocrReviewId: text(formData, "ocrReviewId"),
    pageNumber: text(formData, "pageNumber"),
    findingType: text(formData, "findingType"),
    severity: text(formData, "severity"),
    title: text(formData, "title"),
    description: optionalText(formData, "description"),
    suggestedAction: optionalText(formData, "suggestedAction"),
  });
  if (!parsed.success) withError(OCR_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid finding.");
  const returnTo = ocrReviewDetailPath(parsed.data.ocrReviewId) + `?page=${parsed.data.pageNumber}`;

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_ocr_finding", {
    p_ocr_review_id: parsed.data.ocrReviewId,
    p_page_number: parsed.data.pageNumber,
    p_finding_type: parsed.data.findingType,
    p_severity: parsed.data.severity,
    p_title: parsed.data.title,
    p_description: parsed.data.description ?? null,
    p_suggested_action: parsed.data.suggestedAction ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(ocrReviewDetailPath(parsed.data.ocrReviewId), toOcrReviewError(error).message);

  revalidatePath(ocrReviewDetailPath(parsed.data.ocrReviewId));
  redirect(returnTo);
}

export async function updateOcrFindingStatusAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_REVIEW);
  const parsed = ocrFindingStatusUpdateSchema.safeParse({
    ocrReviewId: text(formData, "ocrReviewId"),
    findingId: text(formData, "findingId"),
    status: text(formData, "status"),
    resolutionNote: optionalText(formData, "resolutionNote"),
  });
  if (!parsed.success) withError(OCR_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid request.");
  const returnTo = ocrReviewDetailPath(parsed.data.ocrReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_ocr_finding_status", {
    p_finding_id: parsed.data.findingId,
    p_status: parsed.data.status,
    p_resolution_note: parsed.data.resolutionNote ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function submitOcrReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_SUBMIT_REVIEW);
  const parsed = ocrReviewSubmitSchema.safeParse({
    ocrReviewId: text(formData, "ocrReviewId"),
    targetStatus: text(formData, "targetStatus"),
    decisionReason: optionalText(formData, "decisionReason"),
    warningSummary: optionalText(formData, "warningSummary"),
  });
  if (!parsed.success) withError(OCR_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "Invalid decision.");
  const returnTo = ocrReviewDetailPath(parsed.data.ocrReviewId);
  const idempotencyKey = text(formData, "idempotencyKey") || randomUUID();

  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_document_ocr_review", {
    p_ocr_review_id: parsed.data.ocrReviewId,
    p_target_status: parsed.data.targetStatus,
    p_decision_reason: parsed.data.decisionReason ?? null,
    p_warning_summary: parsed.data.warningSummary ?? null,
    p_idempotency_key: idempotencyKey,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  revalidatePath(returnTo);
  revalidatePath(OCR_REVIEW_QUEUE_PATH);
  redirect(returnTo);
}

export async function reopenOcrReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_REOPEN_REVIEW);
  const parsed = ocrReviewReasonSchema.safeParse({
    ocrReviewId: text(formData, "ocrReviewId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(OCR_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "A reason is required.");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("reopen_ocr_review", {
    p_ocr_review_id: parsed.data.ocrReviewId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(ocrReviewDetailPath(parsed.data.ocrReviewId), toOcrReviewError(error).message);

  const newReview = data as { id: string };
  revalidatePath(OCR_REVIEW_QUEUE_PATH);
  redirect(ocrReviewDetailPath(newReview.id));
}

export async function invalidateOcrReviewAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_OCR_REOPEN_REVIEW);
  const parsed = ocrReviewReasonSchema.safeParse({
    ocrReviewId: text(formData, "ocrReviewId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(OCR_REVIEW_QUEUE_PATH, parsed.error.issues[0]?.message ?? "A reason is required.");
  const returnTo = ocrReviewDetailPath(parsed.data.ocrReviewId);

  const supabase = await createClient();
  const { error } = await supabase.rpc("invalidate_ocr_review", {
    p_ocr_review_id: parsed.data.ocrReviewId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toOcrReviewError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export interface SignedOcrSourceAccess {
  signedUrl: string;
  expiresAt: string;
  sourceDocumentId: string;
}

const SIGNED_SOURCE_URL_TTL_SECONDS = 300;

/**
 * Mints a short-lived signed read URL for the original source PDF, for the
 * OCR review workspace's original-page panel — the same pattern as
 * createExtractionReviewSourceAccessAction one layer up
 * (apps/web/lib/extraction-review/actions.ts), gated by the OCR-specific
 * permission (guideline_ocr.read_source) rather than the extraction one,
 * per docs/security/ocr-and-storage-authorization.md. No service-role key
 * anywhere — this session's own client is what Storage RLS (migration
 * 0010, guideline_documents.read) actually authorizes against.
 */
export async function createOcrReviewSourceAccessAction(extractionRunId: string): Promise<SignedOcrSourceAccess> {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_OCR_READ_SOURCE);
  const supabase = await createClient();

  const { data: run, error: runError } = await supabase
    .from("document_extraction_runs")
    .select("id, organization_id, source_document_id")
    .eq("id", extractionRunId)
    .maybeSingle();
  if (runError) throw toOcrReviewError(runError);
  if (!run || run.organization_id !== context.organizationId) {
    throw new OcrReviewError("Extraction run not found.", "not_found");
  }

  const { data: doc, error: docError } = await supabase
    .from("guideline_source_documents")
    .select("id, organization_id, storage_bucket, storage_path")
    .eq("id", run.source_document_id)
    .maybeSingle();
  if (docError) throw toOcrReviewError(docError);
  if (!doc || doc.organization_id !== context.organizationId) {
    throw new OcrReviewError("Source document not found.", "not_found");
  }

  const { data: signed, error: signError } = await supabase.storage.from(doc.storage_bucket).createSignedUrl(doc.storage_path, SIGNED_SOURCE_URL_TTL_SECONDS);
  if (signError || !signed) {
    throw new OcrReviewError("Could not create signed access to the source document.", "signing_failed");
  }

  return {
    signedUrl: signed.signedUrl,
    expiresAt: new Date(Date.now() + SIGNED_SOURCE_URL_TTL_SECONDS * 1000).toISOString(),
    sourceDocumentId: doc.id,
  };
}
