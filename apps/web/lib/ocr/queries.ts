import { createClient } from "@/lib/supabase/server";

export type OcrRequestStatus =
  | "created"
  | "queued"
  | "processing"
  | "awaiting_review"
  | "accepted"
  | "accepted_with_warnings"
  | "reprocessing_required"
  | "rejected"
  | "cancelled"
  | "invalidated";

export type OcrRequestPageStatus =
  | "pending"
  | "queued"
  | "processing"
  | "succeeded"
  | "failed"
  | "awaiting_review"
  | "accepted"
  | "accepted_with_warnings"
  | "reprocessing_required"
  | "rejected"
  | "cancelled"
  | "invalidated";

export type OcrRunStatus = "running" | "succeeded" | "failed" | "invalidated" | "reused";

export type OcrReviewStatus =
  | "pending_review"
  | "in_review"
  | "accepted"
  | "accepted_with_warnings"
  | "reprocessing_required"
  | "rejected"
  | "invalidated";

export type OcrPageReviewStatus = "unreviewed" | "accepted" | "accepted_with_warnings" | "reprocessing_required" | "rejected";

export type OcrFindingSeverity = "informational" | "minor" | "major" | "critical";
export type OcrFindingStatus = "open" | "acknowledged" | "resolved" | "accepted_risk" | "dismissed";

export const OCR_FINDING_TYPES = [
  "missing_text",
  "partial_text",
  "incorrect_reading_order",
  "garbled_characters",
  "arabic_recognition_issue",
  "english_recognition_issue",
  "mixed_language_issue",
  "punctuation_loss",
  "number_recognition_issue",
  "table_structure_loss",
  "header_footer_noise",
  "duplicate_text",
  "low_confidence",
  "page_segmentation_issue",
  "rotation_issue",
  "unexpected_content",
  "provider_error",
  "other",
] as const;
export type OcrFindingType = (typeof OCR_FINDING_TYPES)[number];

export interface DocumentOcrRequestRow {
  id: string;
  organization_id: string;
  source_document_id: string;
  extraction_run_id: string;
  extraction_review_id: string;
  review_round: number;
  status: OcrRequestStatus;
  provider_name: string;
  provider_version: string;
  model_identifier: string;
  model_version: string;
  renderer_name: string;
  renderer_version: string;
  render_configuration_version: string;
  ocr_configuration_version: string;
  language_hints: string[];
  requested_by: string | null;
  requested_at: string;
  cancelled_by: string | null;
  cancelled_at: string | null;
  cancellation_reason: string | null;
  completed_at: string | null;
  invalidated_at: string | null;
  invalidation_reason: string | null;
  total_pages: number;
  created_at: string;
  updated_at: string;
}

export interface DocumentOcrRequestPageRow {
  id: string;
  organization_id: string;
  ocr_request_id: string;
  source_document_id: string;
  extraction_run_id: string;
  extraction_page_id: string;
  page_number: number;
  eligibility_source_type: string;
  eligibility_source_id: string;
  eligibility_reason: string | null;
  processing_job_id: string | null;
  status: OcrRequestPageStatus;
  created_at: string;
  updated_at: string;
}

export interface DocumentOcrRunRow {
  id: string;
  organization_id: string;
  ocr_request_id: string;
  ocr_request_page_id: string;
  source_page_number: number;
  status: OcrRunStatus;
  provider_name: string;
  provider_version: string;
  model_identifier: string;
  model_version: string;
  language_hints: string[];
  normalized_text: string | null;
  character_count: number;
  word_count: number;
  text_checksum: string | null;
  confidence_summary: Record<string, unknown>;
  warnings: string[];
  error_code: string | null;
  error_message_safe: string | null;
  artifact_sha256: string | null;
  started_at: string;
  completed_at: string | null;
  failed_at: string | null;
}

export interface DocumentOcrReviewRow {
  id: string;
  organization_id: string;
  ocr_request_id: string;
  review_round: number;
  review_status: OcrReviewStatus;
  assigned_reviewer_id: string | null;
  assigned_at: string | null;
  started_by: string | null;
  started_at: string | null;
  submitted_by: string | null;
  submitted_at: string | null;
  overall_comments: string | null;
  warning_summary: string | null;
  decision_reason: string | null;
  critical_finding_count: number;
  major_finding_count: number;
  minor_finding_count: number;
  informational_finding_count: number;
  pages_reviewed: number;
  total_pages: number;
  all_pages_reviewed: boolean;
  reopened_from_review_id: string | null;
  reopen_reason: string | null;
  created_at: string;
  updated_at: string;
}

export interface DocumentOcrPageReviewRow {
  id: string;
  organization_id: string;
  ocr_review_id: string;
  ocr_request_page_id: string;
  ocr_run_id: string | null;
  page_number: number;
  review_status: OcrPageReviewStatus;
  reviewed_by: string | null;
  reviewed_at: string | null;
  notes: string | null;
}

export interface DocumentOcrFindingRow {
  id: string;
  organization_id: string;
  ocr_review_id: string;
  ocr_request_page_id: string;
  ocr_run_id: string | null;
  page_number: number;
  finding_type: OcrFindingType;
  severity: OcrFindingSeverity;
  status: OcrFindingStatus;
  title: string;
  description: string | null;
  suggested_action: string | null;
  created_by: string;
  created_at: string;
  resolved_by: string | null;
  resolved_at: string | null;
  resolution_note: string | null;
}

export interface PageTextReadinessRow {
  out_page_number: number;
  out_representation_type: "native" | "ocr" | "none";
  out_representation_id: string | null;
  out_text_checksum: string | null;
  out_ready_for_chunking: boolean;
  out_warning_state: boolean;
  out_reason: string;
}

const REQUEST_COLUMNS =
  "id, organization_id, source_document_id, extraction_run_id, extraction_review_id, review_round, status, " +
  "provider_name, provider_version, model_identifier, model_version, renderer_name, renderer_version, " +
  "render_configuration_version, ocr_configuration_version, language_hints, requested_by, requested_at, " +
  "cancelled_by, cancelled_at, cancellation_reason, completed_at, invalidated_at, invalidation_reason, " +
  "total_pages, created_at, updated_at";

const REQUEST_PAGE_COLUMNS =
  "id, organization_id, ocr_request_id, source_document_id, extraction_run_id, extraction_page_id, page_number, " +
  "eligibility_source_type, eligibility_source_id, eligibility_reason, processing_job_id, status, created_at, updated_at";

const RUN_COLUMNS =
  "id, organization_id, ocr_request_id, ocr_request_page_id, source_page_number, status, provider_name, " +
  "provider_version, model_identifier, model_version, language_hints, normalized_text, character_count, " +
  "word_count, text_checksum, confidence_summary, warnings, error_code, error_message_safe, artifact_sha256, " +
  "started_at, completed_at, failed_at";

const REVIEW_COLUMNS =
  "id, organization_id, ocr_request_id, review_round, review_status, assigned_reviewer_id, assigned_at, " +
  "started_by, started_at, submitted_by, submitted_at, overall_comments, warning_summary, decision_reason, " +
  "critical_finding_count, major_finding_count, minor_finding_count, informational_finding_count, " +
  "pages_reviewed, total_pages, all_pages_reviewed, reopened_from_review_id, reopen_reason, created_at, updated_at";

const PAGE_REVIEW_COLUMNS =
  "id, organization_id, ocr_review_id, ocr_request_page_id, ocr_run_id, page_number, review_status, " +
  "reviewed_by, reviewed_at, notes";

const FINDING_COLUMNS =
  "id, organization_id, ocr_review_id, ocr_request_page_id, ocr_run_id, page_number, finding_type, severity, " +
  "status, title, description, suggested_action, created_by, created_at, resolved_by, resolved_at, resolution_note";

export async function getOcrRequestForReview(extractionReviewId: string): Promise<DocumentOcrRequestRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_ocr_requests")
    .select(REQUEST_COLUMNS)
    .eq("extraction_review_id", extractionReviewId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentOcrRequestRow | null;
}

export async function getOcrRequest(id: string): Promise<DocumentOcrRequestRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_ocr_requests").select(REQUEST_COLUMNS).eq("id", id).maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentOcrRequestRow | null;
}

export async function listOcrRequestPages(ocrRequestId: string): Promise<DocumentOcrRequestPageRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_ocr_request_pages")
    .select(REQUEST_PAGE_COLUMNS)
    .eq("ocr_request_id", ocrRequestId)
    .order("page_number", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentOcrRequestPageRow[]) ?? [];
}

export async function listOcrRunsForRequest(ocrRequestId: string): Promise<DocumentOcrRunRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_ocr_runs")
    .select(RUN_COLUMNS)
    .eq("ocr_request_id", ocrRequestId)
    .order("started_at", { ascending: false });
  if (error) throw error;
  return (data as unknown as DocumentOcrRunRow[]) ?? [];
}

/** The latest run per request page — the one a review should show. */
export async function getLatestOcrRunsByPage(ocrRequestId: string): Promise<Map<string, DocumentOcrRunRow>> {
  const runs = await listOcrRunsForRequest(ocrRequestId);
  const byPage = new Map<string, DocumentOcrRunRow>();
  for (const run of runs) {
    if (!byPage.has(run.ocr_request_page_id)) byPage.set(run.ocr_request_page_id, run);
  }
  return byPage;
}

export async function getOcrReview(id: string): Promise<DocumentOcrReviewRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_ocr_reviews").select(REVIEW_COLUMNS).eq("id", id).maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentOcrReviewRow | null;
}

export async function getLatestOcrReviewForRequest(ocrRequestId: string): Promise<DocumentOcrReviewRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_ocr_reviews")
    .select(REVIEW_COLUMNS)
    .eq("ocr_request_id", ocrRequestId)
    .order("review_round", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentOcrReviewRow | null;
}

export async function listOcrPageReviews(ocrReviewId: string): Promise<DocumentOcrPageReviewRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_ocr_page_reviews")
    .select(PAGE_REVIEW_COLUMNS)
    .eq("ocr_review_id", ocrReviewId)
    .order("page_number", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentOcrPageReviewRow[]) ?? [];
}

export async function listOcrFindings(ocrReviewId: string): Promise<DocumentOcrFindingRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_ocr_findings")
    .select(FINDING_COLUMNS)
    .eq("ocr_review_id", ocrReviewId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentOcrFindingRow[]) ?? [];
}

export async function getPageTextReadiness(extractionRunId: string): Promise<PageTextReadinessRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_document_page_text_readiness", { p_extraction_run_id: extractionRunId });
  if (error) throw error;
  return (data as unknown as PageTextReadinessRow[]) ?? [];
}

export interface OcrReviewQueueItem {
  review: DocumentOcrReviewRow;
  request: DocumentOcrRequestRow;
  guidelineId: string;
  guidelineTitle: string;
  guidelineVersionLabel: string;
  sourceFilename: string;
}

/**
 * Same "separate typed queries, never a wide join" convention as
 * apps/web/lib/extraction-review/queries.ts's listExtractionReviewQueue.
 */
export async function listOcrReviewQueue(organizationId: string): Promise<OcrReviewQueueItem[]> {
  const supabase = await createClient();

  const { data: reviews, error: reviewsError } = await supabase
    .from("document_ocr_reviews")
    .select(REVIEW_COLUMNS)
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });
  if (reviewsError) throw reviewsError;
  if (!reviews || reviews.length === 0) return [];

  const requestIds = Array.from(new Set(reviews.map((r) => (r as unknown as DocumentOcrReviewRow).ocr_request_id)));
  const { data: requests, error: requestsError } = await supabase.from("document_ocr_requests").select(REQUEST_COLUMNS).in("id", requestIds);
  if (requestsError) throw requestsError;

  const sourceDocIds = Array.from(new Set((requests ?? []).map((r) => (r as unknown as DocumentOcrRequestRow).source_document_id)));
  const { data: docs, error: docsError } = await supabase
    .from("guideline_source_documents")
    .select("id, guideline_version_id, original_filename")
    .in("id", sourceDocIds);
  if (docsError) throw docsError;

  const versionIds = Array.from(new Set((docs ?? []).map((d) => d.guideline_version_id as string)));
  const { data: versions, error: versionsError } = await supabase.from("guideline_versions").select("id, guideline_id, version_label").in("id", versionIds);
  if (versionsError) throw versionsError;

  const guidelineIds = Array.from(new Set((versions ?? []).map((v) => v.guideline_id as string)));
  const { data: guidelines, error: guidelinesError } = await supabase.from("guidelines").select("id, canonical_title").in("id", guidelineIds);
  if (guidelinesError) throw guidelinesError;

  const requestById = new Map((requests ?? []).map((r) => [(r as unknown as DocumentOcrRequestRow).id, r as unknown as DocumentOcrRequestRow]));
  const docById = new Map((docs ?? []).map((d) => [d.id as string, d]));
  const versionById = new Map((versions ?? []).map((v) => [v.id as string, v]));
  const guidelineById = new Map((guidelines ?? []).map((g) => [g.id as string, g]));

  const items: OcrReviewQueueItem[] = [];
  for (const review of reviews as unknown as DocumentOcrReviewRow[]) {
    const request = requestById.get(review.ocr_request_id);
    if (!request) continue;
    const doc = docById.get(request.source_document_id);
    if (!doc) continue;
    const version = versionById.get(doc.guideline_version_id as string);
    if (!version) continue;
    const guideline = guidelineById.get(version.guideline_id as string);
    if (!guideline) continue;

    items.push({
      review,
      request,
      guidelineId: guideline.id as string,
      guidelineTitle: guideline.canonical_title as string,
      guidelineVersionLabel: version.version_label as string,
      sourceFilename: doc.original_filename as string,
    });
  }
  return items;
}
