import { createClient } from "@/lib/supabase/server";

export type ExtractionReviewStatus =
  | "pending_review"
  | "in_review"
  | "accepted"
  | "accepted_with_warnings"
  | "ocr_required"
  | "reprocessing_required"
  | "rejected"
  | "invalidated";

export type ExtractionFindingSeverity = "informational" | "minor" | "major" | "critical";
export type ExtractionFindingStatus = "open" | "acknowledged" | "resolved" | "accepted_risk" | "dismissed";
export type ExtractionPageReviewStatus =
  | "unreviewed"
  | "reviewed_clear"
  | "reviewed_with_findings"
  | "ocr_candidate"
  | "reprocessing_candidate";

export const EXTRACTION_FINDING_TYPES = [
  "missing_text",
  "partial_text",
  "incorrect_reading_order",
  "multi_column_order_issue",
  "garbled_characters",
  "unicode_normalization_issue",
  "arabic_shaping_issue",
  "arabic_direction_issue",
  "mixed_language_direction_issue",
  "rotation_issue",
  "unexpected_blank_page",
  "image_only_page",
  "suspected_scanned_page",
  "table_structure_loss",
  "figure_caption_loss",
  "footnote_loss",
  "header_footer_noise",
  "duplicate_text",
  "missing_page",
  "page_number_mismatch",
  "metadata_mismatch",
  "source_integrity_concern",
  "other",
] as const;
export type ExtractionFindingType = (typeof EXTRACTION_FINDING_TYPES)[number];

export interface DocumentExtractionReviewRow {
  id: string;
  organization_id: string;
  extraction_run_id: string;
  review_round: number;
  review_status: ExtractionReviewStatus;
  assigned_reviewer_id: string | null;
  assigned_at: string | null;
  started_by: string | null;
  started_at: string | null;
  submitted_by: string | null;
  submitted_at: string | null;
  overall_comments: string | null;
  technical_summary: string | null;
  warning_summary: string | null;
  critical_finding_count: number;
  major_finding_count: number;
  minor_finding_count: number;
  informational_finding_count: number;
  pages_reviewed: number;
  total_pages: number;
  all_pages_reviewed: boolean;
  requires_ocr: boolean;
  requires_reprocessing: boolean;
  decision_reason: string | null;
  reopened_from_review_id: string | null;
  reopen_reason: string | null;
  created_at: string;
  updated_at: string;
}

export interface DocumentExtractionReviewFindingRow {
  id: string;
  organization_id: string;
  extraction_review_id: string;
  extraction_run_id: string;
  extraction_page_id: string | null;
  page_number: number | null;
  finding_type: ExtractionFindingType;
  severity: ExtractionFindingSeverity;
  status: ExtractionFindingStatus;
  title: string;
  description: string | null;
  suggested_action: string | null;
  created_by: string;
  created_at: string;
  resolved_by: string | null;
  resolved_at: string | null;
  resolution_note: string | null;
}

export interface DocumentExtractionPageReviewRow {
  id: string;
  organization_id: string;
  extraction_review_id: string;
  extraction_page_id: string;
  page_number: number;
  review_status: ExtractionPageReviewStatus;
  reviewed_by: string | null;
  reviewed_at: string | null;
  notes: string | null;
}

const REVIEW_COLUMNS =
  "id, organization_id, extraction_run_id, review_round, review_status, assigned_reviewer_id, assigned_at, " +
  "started_by, started_at, submitted_by, submitted_at, overall_comments, technical_summary, warning_summary, " +
  "critical_finding_count, major_finding_count, minor_finding_count, informational_finding_count, " +
  "pages_reviewed, total_pages, all_pages_reviewed, requires_ocr, requires_reprocessing, decision_reason, " +
  "reopened_from_review_id, reopen_reason, created_at, updated_at";

const FINDING_COLUMNS =
  "id, organization_id, extraction_review_id, extraction_run_id, extraction_page_id, page_number, " +
  "finding_type, severity, status, title, description, suggested_action, created_by, created_at, " +
  "resolved_by, resolved_at, resolution_note";

const PAGE_REVIEW_COLUMNS =
  "id, organization_id, extraction_review_id, extraction_page_id, page_number, review_status, " +
  "reviewed_by, reviewed_at, notes";

export async function listExtractionReviewsForRun(extractionRunId: string): Promise<DocumentExtractionReviewRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_extraction_reviews")
    .select(REVIEW_COLUMNS)
    .eq("extraction_run_id", extractionRunId)
    .order("review_round", { ascending: false });
  if (error) throw error;
  return (data as unknown as DocumentExtractionReviewRow[]) ?? [];
}

export async function getLatestExtractionReviewForRun(extractionRunId: string): Promise<DocumentExtractionReviewRow | null> {
  const rows = await listExtractionReviewsForRun(extractionRunId);
  return rows[0] ?? null;
}

export async function getExtractionReview(id: string): Promise<DocumentExtractionReviewRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_extraction_reviews")
    .select(REVIEW_COLUMNS)
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentExtractionReviewRow | null;
}

export async function listExtractionReviewFindings(reviewId: string): Promise<DocumentExtractionReviewFindingRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_extraction_review_findings")
    .select(FINDING_COLUMNS)
    .eq("extraction_review_id", reviewId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentExtractionReviewFindingRow[]) ?? [];
}

export async function listExtractionPageReviews(reviewId: string): Promise<DocumentExtractionPageReviewRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_extraction_page_reviews")
    .select(PAGE_REVIEW_COLUMNS)
    .eq("extraction_review_id", reviewId)
    .order("page_number", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentExtractionPageReviewRow[]) ?? [];
}

export interface ExtractionReviewEligibility {
  out_extraction_run_id: string;
  out_extraction_status: string;
  out_latest_review_id: string | null;
  out_review_status: ExtractionReviewStatus | null;
  out_eligible_for_ocr: boolean;
  out_eligible_for_chunking: boolean;
  out_eligible_for_retrieval: boolean;
}

export async function getExtractionReviewEligibility(extractionRunId: string): Promise<ExtractionReviewEligibility | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .rpc("get_document_extraction_review_eligibility", { p_extraction_run_id: extractionRunId })
    .single();
  if (error) throw error;
  return data as unknown as ExtractionReviewEligibility | null;
}

export interface ExtractionReviewQueueItem {
  review: DocumentExtractionReviewRow;
  extractionRunId: string;
  sourceDocumentId: string;
  guidelineId: string;
  guidelineTitle: string;
  guidelineVersionLabel: string;
  sourceFilename: string;
  pageCount: number | null;
  suspectedScannedPageCount: number | null;
}

/**
 * The review queue joins across extraction runs, source documents,
 * guideline versions, and guidelines — done as separate typed queries
 * (not a single wide join) to keep every explicit column list intact per
 * table, matching the rest of this codebase's "never select(*)" convention
 * for tables carrying internal-only columns.
 */
export async function listExtractionReviewQueue(organizationId: string): Promise<ExtractionReviewQueueItem[]> {
  const supabase = await createClient();

  const { data: reviews, error: reviewsError } = await supabase
    .from("document_extraction_reviews")
    .select(REVIEW_COLUMNS)
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });
  if (reviewsError) throw reviewsError;
  if (!reviews || reviews.length === 0) return [];

  const runIds = Array.from(new Set(reviews.map((r) => (r as unknown as DocumentExtractionReviewRow).extraction_run_id)));

  const { data: runs, error: runsError } = await supabase
    .from("document_extraction_runs")
    .select("id, source_document_id, page_count, suspected_scanned_page_count")
    .in("id", runIds);
  if (runsError) throw runsError;

  const sourceDocIds = Array.from(new Set((runs ?? []).map((r) => r.source_document_id as string)));
  const { data: docs, error: docsError } = await supabase
    .from("guideline_source_documents")
    .select("id, guideline_version_id, original_filename")
    .in("id", sourceDocIds);
  if (docsError) throw docsError;

  const versionIds = Array.from(new Set((docs ?? []).map((d) => d.guideline_version_id as string)));
  const { data: versions, error: versionsError } = await supabase
    .from("guideline_versions")
    .select("id, guideline_id, version_label")
    .in("id", versionIds);
  if (versionsError) throw versionsError;

  const guidelineIds = Array.from(new Set((versions ?? []).map((v) => v.guideline_id as string)));
  const { data: guidelines, error: guidelinesError } = await supabase
    .from("guidelines")
    .select("id, canonical_title")
    .in("id", guidelineIds);
  if (guidelinesError) throw guidelinesError;

  const runById = new Map((runs ?? []).map((r) => [r.id as string, r]));
  const docById = new Map((docs ?? []).map((d) => [d.id as string, d]));
  const versionById = new Map((versions ?? []).map((v) => [v.id as string, v]));
  const guidelineById = new Map((guidelines ?? []).map((g) => [g.id as string, g]));

  const items: ExtractionReviewQueueItem[] = [];
  for (const review of reviews as unknown as DocumentExtractionReviewRow[]) {
    const run = runById.get(review.extraction_run_id);
    if (!run) continue;
    const doc = docById.get(run.source_document_id as string);
    if (!doc) continue;
    const version = versionById.get(doc.guideline_version_id as string);
    if (!version) continue;
    const guideline = guidelineById.get(version.guideline_id as string);
    if (!guideline) continue;

    items.push({
      review,
      extractionRunId: review.extraction_run_id,
      sourceDocumentId: doc.id as string,
      guidelineId: guideline.id as string,
      guidelineTitle: guideline.canonical_title as string,
      guidelineVersionLabel: version.version_label as string,
      sourceFilename: doc.original_filename as string,
      pageCount: run.page_count as number | null,
      suspectedScannedPageCount: run.suspected_scanned_page_count as number | null,
    });
  }
  return items;
}
