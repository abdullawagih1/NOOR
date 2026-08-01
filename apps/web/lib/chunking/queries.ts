import { createClient } from "@/lib/supabase/server";

export type ChunkingRunStatus = "running" | "succeeded" | "failed" | "invalidated" | "reused";

export type ChunkingReviewStatus = "pending_review" | "in_review" | "accepted" | "accepted_with_warnings" | "rechunk_required" | "rejected" | "invalidated";

export type ChunkReviewStatus = "unreviewed" | "reviewed_clear" | "reviewed_with_findings" | "rechunk_candidate" | "rejected";

export type ChunkFindingSeverity = "informational" | "minor" | "major" | "critical";
export type ChunkFindingStatus = "open" | "acknowledged" | "resolved" | "accepted_risk" | "dismissed";

export const CHUNK_FINDING_TYPES = [
  "missing_content",
  "duplicated_content",
  "invalid_source_span",
  "wrong_page_provenance",
  "wrong_representation",
  "boundary_splits_sentence",
  "boundary_splits_list",
  "boundary_splits_table",
  "heading_detached",
  "footnote_detached",
  "merged_unrelated_content",
  "insufficient_context",
  "oversized_chunk",
  "undersized_chunk",
  "hard_split_required",
  "arabic_boundary_issue",
  "mixed_language_boundary_issue",
  "ocr_warning_propagation",
  "header_footer_noise",
  "page_boundary_issue",
  "token_count_issue",
  "artifact_integrity_issue",
  "other",
] as const;
export type ChunkFindingType = (typeof CHUNK_FINDING_TYPES)[number];

export interface DocumentChunkingRunRow {
  id: string;
  organization_id: string;
  source_document_id: string;
  guideline_version_id: string;
  guideline_id: string;
  extraction_run_id: string;
  extraction_review_id: string;
  ocr_request_id: string | null;
  ocr_review_id: string | null;
  processing_job_id: string;
  pipeline_version: string;
  configuration_version: string;
  normalization_version: string;
  tokenizer_name: string;
  tokenizer_version: string;
  status: ChunkingRunStatus;
  started_at: string;
  completed_at: string | null;
  failed_at: string | null;
  invalidated_at: string | null;
  invalidation_reason: string | null;
  chunk_count: number | null;
  page_count: number | null;
  native_page_count: number | null;
  ocr_page_count: number | null;
  total_characters: number | null;
  total_words: number | null;
  total_tokens: number | null;
  minimum_chunk_tokens: number | null;
  maximum_chunk_tokens: number | null;
  average_chunk_tokens: number | null;
  chunks_below_minimum: number | null;
  chunks_above_target: number | null;
  chunks_at_hard_maximum: number | null;
  hard_split_count: number | null;
  heading_boundary_count: number | null;
  list_boundary_count: number | null;
  table_like_chunk_count: number | null;
  warning_chunk_count: number | null;
  coverage_percentage: number | null;
  duplication_percentage: number | null;
  warnings: string[];
  artifact_sha256: string | null;
  created_at: string;
}

export interface DocumentChunkRow {
  id: string;
  organization_id: string;
  chunking_run_id: string;
  chunk_index: number;
  chunk_text: string;
  chunk_checksum: string;
  page_start: number;
  page_end: number;
  source_span_count: number;
  token_count: number;
  character_count: number;
  word_count: number;
  heading_context: string | null;
  block_type_summary: string[];
  boundary_start_reason: string;
  boundary_end_reason: string;
  contains_native_text: boolean;
  contains_ocr_text: boolean;
  warning_state: boolean;
  warnings: string[];
  created_at: string;
}

export interface DocumentChunkingReviewRow {
  id: string;
  organization_id: string;
  chunking_run_id: string;
  review_round: number;
  review_status: ChunkingReviewStatus;
  assigned_reviewer_id: string | null;
  assigned_at: string | null;
  started_by: string | null;
  started_at: string | null;
  submitted_by: string | null;
  submitted_at: string | null;
  decision_reason: string | null;
  warning_summary: string | null;
  chunks_reviewed: number;
  total_chunks: number;
  all_chunks_reviewed: boolean;
  reopened_from_review_id: string | null;
  reopen_reason: string | null;
  created_at: string;
  updated_at: string;
}

export interface DocumentChunkReviewRow {
  id: string;
  organization_id: string;
  chunking_review_id: string;
  chunk_id: string;
  chunk_index: number;
  review_status: ChunkReviewStatus;
  reviewed_by: string | null;
  reviewed_at: string | null;
  notes: string | null;
}

export interface DocumentChunkFindingRow {
  id: string;
  organization_id: string;
  chunking_review_id: string;
  chunk_id: string | null;
  finding_type: ChunkFindingType;
  severity: ChunkFindingSeverity;
  status: ChunkFindingStatus;
  title: string;
  description: string | null;
  suggested_action: string | null;
  created_by: string;
  created_at: string;
  resolution_note: string | null;
}

const RUN_COLUMNS =
  "id, organization_id, source_document_id, guideline_version_id, guideline_id, extraction_run_id, extraction_review_id, " +
  "ocr_request_id, ocr_review_id, processing_job_id, pipeline_version, configuration_version, normalization_version, " +
  "tokenizer_name, tokenizer_version, status, started_at, completed_at, failed_at, invalidated_at, invalidation_reason, " +
  "chunk_count, page_count, native_page_count, ocr_page_count, total_characters, total_words, total_tokens, " +
  "minimum_chunk_tokens, maximum_chunk_tokens, average_chunk_tokens, chunks_below_minimum, chunks_above_target, " +
  "chunks_at_hard_maximum, hard_split_count, heading_boundary_count, list_boundary_count, table_like_chunk_count, " +
  "warning_chunk_count, coverage_percentage, duplication_percentage, warnings, artifact_sha256, created_at";

const CHUNK_COLUMNS =
  "id, organization_id, chunking_run_id, chunk_index, chunk_text, chunk_checksum, page_start, page_end, " +
  "source_span_count, token_count, character_count, word_count, heading_context, block_type_summary, " +
  "boundary_start_reason, boundary_end_reason, contains_native_text, contains_ocr_text, warning_state, warnings, created_at";

const REVIEW_COLUMNS =
  "id, organization_id, chunking_run_id, review_round, review_status, assigned_reviewer_id, assigned_at, started_by, " +
  "started_at, submitted_by, submitted_at, decision_reason, warning_summary, chunks_reviewed, total_chunks, " +
  "all_chunks_reviewed, reopened_from_review_id, reopen_reason, created_at, updated_at";

const CHUNK_REVIEW_COLUMNS = "id, organization_id, chunking_review_id, chunk_id, chunk_index, review_status, reviewed_by, reviewed_at, notes";

const FINDING_COLUMNS =
  "id, organization_id, chunking_review_id, chunk_id, finding_type, severity, status, title, description, " +
  "suggested_action, created_by, created_at, resolution_note";

export async function getLatestChunkingRunForDocument(sourceDocumentId: string): Promise<DocumentChunkingRunRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_chunking_runs")
    .select(RUN_COLUMNS)
    .eq("source_document_id", sourceDocumentId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentChunkingRunRow | null;
}

export async function getChunkingRun(id: string): Promise<DocumentChunkingRunRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_chunking_runs").select(RUN_COLUMNS).eq("id", id).maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentChunkingRunRow | null;
}

export async function listChunksForRun(chunkingRunId: string): Promise<DocumentChunkRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_chunks").select(CHUNK_COLUMNS).eq("chunking_run_id", chunkingRunId).order("chunk_index", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentChunkRow[]) ?? [];
}

export async function getChunkingReview(id: string): Promise<DocumentChunkingReviewRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_chunking_reviews").select(REVIEW_COLUMNS).eq("id", id).maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentChunkingReviewRow | null;
}

export async function getLatestChunkingReviewForRun(chunkingRunId: string): Promise<DocumentChunkingReviewRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_chunking_reviews")
    .select(REVIEW_COLUMNS)
    .eq("chunking_run_id", chunkingRunId)
    .order("review_round", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentChunkingReviewRow | null;
}

export async function listChunkReviews(chunkingReviewId: string): Promise<DocumentChunkReviewRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_chunk_reviews")
    .select(CHUNK_REVIEW_COLUMNS)
    .eq("chunking_review_id", chunkingReviewId)
    .order("chunk_index", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentChunkReviewRow[]) ?? [];
}

export async function listChunkFindings(chunkingReviewId: string): Promise<DocumentChunkFindingRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_chunk_findings").select(FINDING_COLUMNS).eq("chunking_review_id", chunkingReviewId).order("created_at", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentChunkFindingRow[]) ?? [];
}

export interface ChunkingEmbeddingReadinessRow {
  out_source_document_id: string;
  out_chunking_run_id: string | null;
  out_chunking_status: ChunkingRunStatus | null;
  out_review_status: ChunkingReviewStatus | null;
  out_eligible_for_embedding: boolean;
  out_eligible_for_retrieval: boolean;
  out_reason: string | null;
}

export async function getEmbeddingReadiness(sourceDocumentId: string): Promise<ChunkingEmbeddingReadinessRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_document_embedding_readiness", { p_source_document_id: sourceDocumentId });
  if (error) throw error;
  const rows = (data as unknown as ChunkingEmbeddingReadinessRow[]) ?? [];
  return rows[0] ?? null;
}

export interface ChunkingReviewQueueItem {
  review: DocumentChunkingReviewRow;
  run: DocumentChunkingRunRow;
  guidelineId: string;
  guidelineTitle: string;
  guidelineVersionLabel: string;
  sourceFilename: string;
}

/**
 * Same "separate typed queries, never a wide join" convention as
 * apps/web/lib/ocr/queries.ts's listOcrReviewQueue — one layer deeper.
 * document_chunking_runs already stores guideline_id/guideline_version_id
 * directly (migration 0012), so this needs one fewer hop than OCR's queue
 * query.
 */
export async function listChunkingReviewQueue(organizationId: string): Promise<ChunkingReviewQueueItem[]> {
  const supabase = await createClient();

  const { data: reviews, error: reviewsError } = await supabase
    .from("document_chunking_reviews")
    .select(REVIEW_COLUMNS)
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });
  if (reviewsError) throw reviewsError;
  if (!reviews || reviews.length === 0) return [];

  const runIds = Array.from(new Set(reviews.map((r) => (r as unknown as DocumentChunkingReviewRow).chunking_run_id)));
  const { data: runs, error: runsError } = await supabase.from("document_chunking_runs").select(RUN_COLUMNS).in("id", runIds);
  if (runsError) throw runsError;

  const sourceDocIds = Array.from(new Set((runs ?? []).map((r) => (r as unknown as DocumentChunkingRunRow).source_document_id)));
  const { data: docs, error: docsError } = await supabase.from("guideline_source_documents").select("id, original_filename").in("id", sourceDocIds);
  if (docsError) throw docsError;

  const versionIds = Array.from(new Set((runs ?? []).map((r) => (r as unknown as DocumentChunkingRunRow).guideline_version_id)));
  const { data: versions, error: versionsError } = await supabase.from("guideline_versions").select("id, version_label").in("id", versionIds);
  if (versionsError) throw versionsError;

  const guidelineIds = Array.from(new Set((runs ?? []).map((r) => (r as unknown as DocumentChunkingRunRow).guideline_id)));
  const { data: guidelines, error: guidelinesError } = await supabase.from("guidelines").select("id, canonical_title").in("id", guidelineIds);
  if (guidelinesError) throw guidelinesError;

  const runById = new Map((runs ?? []).map((r) => [(r as unknown as DocumentChunkingRunRow).id, r as unknown as DocumentChunkingRunRow]));
  const docById = new Map((docs ?? []).map((d) => [d.id as string, d]));
  const versionById = new Map((versions ?? []).map((v) => [v.id as string, v]));
  const guidelineById = new Map((guidelines ?? []).map((g) => [g.id as string, g]));

  const items: ChunkingReviewQueueItem[] = [];
  for (const review of reviews as unknown as DocumentChunkingReviewRow[]) {
    const run = runById.get(review.chunking_run_id);
    if (!run) continue;
    const doc = docById.get(run.source_document_id);
    const version = versionById.get(run.guideline_version_id);
    const guideline = guidelineById.get(run.guideline_id);
    if (!doc || !version || !guideline) continue;

    items.push({
      review,
      run,
      guidelineId: guideline.id as string,
      guidelineTitle: guideline.canonical_title as string,
      guidelineVersionLabel: version.version_label as string,
      sourceFilename: doc.original_filename as string,
    });
  }
  return items;
}
