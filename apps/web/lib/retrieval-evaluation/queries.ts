import { createClient } from "@/lib/supabase/server";

export type RetrievalEvaluationDatasetStatus = "draft" | "ready_for_review" | "frozen" | "archived";
export type RetrievalEvaluationRunStatus = "running" | "succeeded" | "failed" | "invalidated" | "cancelled" | "reused";
export type RetrievalEvaluationLanguage = "en" | "ar" | "mixed";
export type RetrievalEvaluationRepresentationType = "native" | "ocr" | "unknown";
export type RelevanceJudgmentReviewStatus = "pending_review" | "confirmed";
export type RetrievalEvaluationFailureSource = "system" | "human";
export type RetrievalEvaluationFailureStatus = "open" | "acknowledged" | "resolved";
export type RetrievalEvaluationMetricScopeType = "overall" | "language" | "category" | "difficulty" | "exact_vs_indexed";

/** CHECK-constrained in migration 0014 — encoded here verbatim, never a separate invented list. */
export const QUERY_CATEGORIES = [
  "exact_phrase",
  "keyword_lookup",
  "fact_location",
  "definition",
  "procedure_step",
  "numeric_lookup",
  "abbreviation",
  "heading_lookup",
  "cross_paragraph",
  "arabic_exact",
  "arabic_keyword",
  "english_exact",
  "english_keyword",
  "mixed_language",
  "negative_control",
  "ambiguous",
  "hard_lexical",
] as const;
export type QueryCategory = (typeof QUERY_CATEGORIES)[number];

export const QUERY_DIFFICULTIES = ["basic", "moderate", "challenging"] as const;
export type QueryDifficulty = (typeof QUERY_DIFFICULTIES)[number];

export const RETRIEVAL_EVALUATION_LANGUAGES = ["en", "ar", "mixed"] as const;

/**
 * CHECK-constrained in migration 0015, extended by migration 0017 with the
 * vector-specific failure taxonomy (mission §42) — encoded here verbatim,
 * never a separate invented list.
 */
export const FAILURE_CATEGORIES = [
  "missed_relevant_item",
  "relevant_below_k",
  "non_relevant_ranked_high",
  "exact_phrase_failure",
  "arabic_normalization_failure",
  "mixed_language_failure",
  "numeric_match_failure",
  "abbreviation_failure",
  "tokenization_failure",
  "tie_break_failure",
  "query_too_broad",
  "query_too_narrow",
  "insufficient_lexical_overlap",
  "negative_control_false_positive",
  "judgment_gap",
  "corpus_gap",
  "semantic_false_positive",
  "semantic_false_negative",
  "lexical_exact_match_lost",
  "arabic_embedding_failure",
  "mixed_language_embedding_failure",
  "numeric_semantics_failure",
  "abbreviation_embedding_failure",
  "short_query_failure",
  "long_chunk_dilution",
  "similar_chunk_confusion",
  "query_passage_mode_mismatch",
  "model_input_limit",
  "vector_dimension_error",
  "vector_norm_anomaly",
  "exact_index_disagreement",
  "index_recall_failure",
  "dataset_embedding_gap",
  "stale_embedding",
  "configuration_mismatch",
  "other",
] as const;
export type FailureCategory = (typeof FAILURE_CATEGORIES)[number];

/**
 * CHECK-constrained in migration 0015, extended by migration 0017 with the
 * exact-vs-indexed correctness metrics and the coverage/system-performance
 * metrics (mission §43-44) — never merged with a retrieval-quality score.
 */
export const METRIC_NAMES = [
  "precision_at_1",
  "precision_at_3",
  "precision_at_5",
  "precision_at_10",
  "recall_at_1",
  "recall_at_3",
  "recall_at_5",
  "recall_at_10",
  "hit_rate_at_1",
  "hit_rate_at_3",
  "hit_rate_at_5",
  "hit_rate_at_10",
  "mrr",
  "ndcg_at_1",
  "ndcg_at_3",
  "ndcg_at_5",
  "ndcg_at_10",
  "exact_vs_indexed_recall_at_1",
  "exact_vs_indexed_recall_at_3",
  "exact_vs_indexed_recall_at_5",
  "exact_vs_indexed_recall_at_10",
  "exact_vs_indexed_rank_agreement",
  "embedding_coverage",
  "query_embedding_coverage",
  "invalid_vector_count",
  "reused_vector_count",
  "provider_latency_ms",
  "exact_search_latency_ms",
  "indexed_search_latency_ms",
] as const;
export type MetricName = (typeof METRIC_NAMES)[number];

export interface RetrievalEvaluationDatasetRow {
  id: string;
  organization_id: string;
  logical_name: string;
  version: number;
  title: string;
  description: string | null;
  domain_scope: string | null;
  language_scope: string[];
  purpose: string | null;
  status: RetrievalEvaluationDatasetStatus;
  parent_dataset_id: string | null;
  dataset_schema_version: string;
  normalization_version: string;
  no_clinical_use_notice: string;
  corpus_manifest_sha256: string | null;
  query_manifest_sha256: string | null;
  judgment_manifest_sha256: string | null;
  dataset_sha256: string | null;
  created_by: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  return_to_draft_reason: string | null;
  frozen_by: string | null;
  frozen_at: string | null;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface RetrievalEvaluationCorpusItemRow {
  id: string;
  organization_id: string;
  dataset_id: string;
  chunk_id: string;
  chunking_run_id: string;
  chunking_review_id: string | null;
  guideline_id: string;
  guideline_version_id: string;
  source_document_id: string;
  chunk_index: number;
  chunk_checksum: string;
  page_number: number;
  representation_type: RetrievalEvaluationRepresentationType;
  contains_native_text: boolean;
  contains_ocr_text: boolean;
  warning_state: boolean;
  embedding_ready_at_snapshot: boolean;
  display_order: number;
  corpus_item_sha256: string | null;
  added_by: string | null;
  created_at: string;
}

export interface RetrievalEvaluationQueryRow {
  id: string;
  organization_id: string;
  dataset_id: string;
  query_key: string;
  query_text: string;
  normalized_query_text: string;
  language: RetrievalEvaluationLanguage;
  category: QueryCategory;
  difficulty: QueryDifficulty;
  intent_note: string | null;
  expected_source_scope: string | null;
  is_negative_control: boolean;
  synthetic_declaration: string;
  display_order: number;
  active: boolean;
  query_sha256: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface RetrievalRelevanceJudgmentRow {
  id: string;
  organization_id: string;
  dataset_id: string;
  query_id: string;
  corpus_item_id: string;
  relevance_grade: 0 | 1 | 2 | 3;
  rationale: string | null;
  review_status: RelevanceJudgmentReviewStatus;
  judged_by: string | null;
  judged_at: string;
  judgment_sha256: string | null;
  created_at: string;
  updated_at: string;
}

export interface RetrievalEvaluationRunRow {
  id: string;
  organization_id: string;
  dataset_id: string;
  processing_job_id: string;
  processing_attempt_id: string | null;
  retriever_name: string;
  retriever_version: string;
  retrieval_configuration_version: string;
  query_normalization_version: string;
  metric_definition_version: string;
  top_k_values: number[];
  relevance_threshold: number;
  evaluation_runner_version: string;
  /** Non-null only for retriever_name === 'noor-vector-baseline' (migration 0017). */
  embedding_configuration_id: string | null;
  vector_index_configuration_version: string | null;
  run_identity_sha256: string;
  status: RetrievalEvaluationRunStatus;
  started_at: string;
  completed_at: string | null;
  failed_at: string | null;
  invalidated_at: string | null;
  invalidation_reason: string | null;
  query_count: number | null;
  result_count: number | null;
  artifact_bucket: string | null;
  artifact_path: string | null;
  artifact_sha256: string | null;
  artifact_size_bytes: number | null;
  artifact_media_type: string | null;
  created_at: string;
  created_by: string | null;
}

export interface RetrievalEvaluationResultRow {
  id: string;
  organization_id: string;
  evaluation_run_id: string;
  query_id: string;
  corpus_item_id: string;
  rank: number;
  final_score: number;
  score_components: Record<string, unknown>;
  matched_terms: unknown[];
  relevance_grade: number | null;
  reciprocal_rank_contribution: number | null;
  dcg_contribution: number | null;
  is_hit: boolean;
  result_checksum: string;
  created_at: string;
}

export interface RetrievalEvaluationMetricRow {
  id: string;
  organization_id: string;
  evaluation_run_id: string;
  scope_type: RetrievalEvaluationMetricScopeType;
  scope_value: string | null;
  metric_name: MetricName;
  metric_value: number;
  sample_size: number;
  created_at: string;
}

export interface RetrievalEvaluationFailureRow {
  id: string;
  organization_id: string;
  evaluation_run_id: string;
  query_id: string;
  failure_category: FailureCategory;
  source: RetrievalEvaluationFailureSource;
  reviewer_note: string | null;
  recommended_experiment: string | null;
  status: RetrievalEvaluationFailureStatus;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const DATASET_COLUMNS =
  "id, organization_id, logical_name, version, title, description, domain_scope, language_scope, purpose, " +
  "status, parent_dataset_id, dataset_schema_version, normalization_version, no_clinical_use_notice, " +
  "corpus_manifest_sha256, query_manifest_sha256, judgment_manifest_sha256, dataset_sha256, " +
  "created_by, reviewed_by, reviewed_at, return_to_draft_reason, frozen_by, frozen_at, archived_at, created_at, updated_at";

const CORPUS_ITEM_COLUMNS =
  "id, organization_id, dataset_id, chunk_id, chunking_run_id, chunking_review_id, guideline_id, guideline_version_id, " +
  "source_document_id, chunk_index, chunk_checksum, page_number, representation_type, contains_native_text, " +
  "contains_ocr_text, warning_state, embedding_ready_at_snapshot, display_order, corpus_item_sha256, added_by, created_at";

const QUERY_COLUMNS =
  "id, organization_id, dataset_id, query_key, query_text, normalized_query_text, language, category, difficulty, " +
  "intent_note, expected_source_scope, is_negative_control, synthetic_declaration, display_order, active, " +
  "query_sha256, created_by, created_at, updated_at";

const JUDGMENT_COLUMNS =
  "id, organization_id, dataset_id, query_id, corpus_item_id, relevance_grade, rationale, review_status, " +
  "judged_by, judged_at, judgment_sha256, created_at, updated_at";

const RUN_COLUMNS =
  "id, organization_id, dataset_id, processing_job_id, processing_attempt_id, retriever_name, retriever_version, " +
  "retrieval_configuration_version, query_normalization_version, metric_definition_version, top_k_values, " +
  "relevance_threshold, evaluation_runner_version, embedding_configuration_id, vector_index_configuration_version, " +
  "run_identity_sha256, status, started_at, completed_at, " +
  "failed_at, invalidated_at, invalidation_reason, query_count, result_count, artifact_bucket, artifact_path, " +
  "artifact_sha256, artifact_size_bytes, artifact_media_type, created_at, created_by";

const RESULT_COLUMNS =
  "id, organization_id, evaluation_run_id, query_id, corpus_item_id, rank, final_score, score_components, " +
  "matched_terms, relevance_grade, reciprocal_rank_contribution, dcg_contribution, is_hit, result_checksum, created_at";

const METRIC_COLUMNS = "id, organization_id, evaluation_run_id, scope_type, scope_value, metric_name, metric_value, sample_size, created_at";

const FAILURE_COLUMNS =
  "id, organization_id, evaluation_run_id, query_id, failure_category, source, reviewer_note, recommended_experiment, " +
  "status, created_by, created_at, updated_at";

export async function getRetrievalEvaluationDataset(id: string): Promise<RetrievalEvaluationDatasetRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("retrieval_evaluation_datasets").select(DATASET_COLUMNS).eq("id", id).maybeSingle();
  if (error) throw error;
  return data as unknown as RetrievalEvaluationDatasetRow | null;
}

export async function listCorpusItems(datasetId: string): Promise<RetrievalEvaluationCorpusItemRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("retrieval_evaluation_corpus_items")
    .select(CORPUS_ITEM_COLUMNS)
    .eq("dataset_id", datasetId)
    .order("display_order", { ascending: true });
  if (error) throw error;
  return (data as unknown as RetrievalEvaluationCorpusItemRow[]) ?? [];
}

export async function listEvaluationQueries(datasetId: string): Promise<RetrievalEvaluationQueryRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("retrieval_evaluation_queries")
    .select(QUERY_COLUMNS)
    .eq("dataset_id", datasetId)
    .order("display_order", { ascending: true });
  if (error) throw error;
  return (data as unknown as RetrievalEvaluationQueryRow[]) ?? [];
}

export async function listRelevanceJudgments(datasetId: string): Promise<RetrievalRelevanceJudgmentRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("retrieval_relevance_judgments")
    .select(JUDGMENT_COLUMNS)
    .eq("dataset_id", datasetId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data as unknown as RetrievalRelevanceJudgmentRow[]) ?? [];
}

export async function listRetrievalEvaluationRuns(datasetId: string): Promise<RetrievalEvaluationRunRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("retrieval_evaluation_runs")
    .select(RUN_COLUMNS)
    .eq("dataset_id", datasetId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data as unknown as RetrievalEvaluationRunRow[]) ?? [];
}

export async function getRetrievalEvaluationRun(runId: string): Promise<RetrievalEvaluationRunRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("retrieval_evaluation_runs").select(RUN_COLUMNS).eq("id", runId).maybeSingle();
  if (error) throw error;
  return data as unknown as RetrievalEvaluationRunRow | null;
}

export async function listEvaluationResults(evaluationRunId: string): Promise<RetrievalEvaluationResultRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("retrieval_evaluation_results")
    .select(RESULT_COLUMNS)
    .eq("evaluation_run_id", evaluationRunId)
    .order("rank", { ascending: true });
  if (error) throw error;
  return (data as unknown as RetrievalEvaluationResultRow[]) ?? [];
}

export async function listEvaluationMetrics(evaluationRunId: string): Promise<RetrievalEvaluationMetricRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("retrieval_evaluation_metrics")
    .select(METRIC_COLUMNS)
    .eq("evaluation_run_id", evaluationRunId)
    .order("scope_type", { ascending: true });
  if (error) throw error;
  return (data as unknown as RetrievalEvaluationMetricRow[]) ?? [];
}

export async function listEvaluationFailures(evaluationRunId: string): Promise<RetrievalEvaluationFailureRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("retrieval_evaluation_failures")
    .select(FAILURE_COLUMNS)
    .eq("evaluation_run_id", evaluationRunId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data as unknown as RetrievalEvaluationFailureRow[]) ?? [];
}

export interface RetrievalEvaluationDatasetQueueItem {
  dataset: RetrievalEvaluationDatasetRow;
  corpusItemCount: number;
  queryCount: number;
}

/**
 * Same "separate typed queries, never a wide join" convention as
 * apps/web/lib/chunking/queries.ts's listChunkingReviewQueue — counts are
 * computed client-side from separate id-only reads rather than a grouped
 * SQL aggregation, since datasets are a small, internal-tool-scale table.
 */
export async function listRetrievalEvaluationDatasets(organizationId: string): Promise<RetrievalEvaluationDatasetQueueItem[]> {
  const supabase = await createClient();

  const { data: datasets, error: datasetsError } = await supabase
    .from("retrieval_evaluation_datasets")
    .select(DATASET_COLUMNS)
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });
  if (datasetsError) throw datasetsError;
  if (!datasets || datasets.length === 0) return [];

  const datasetIds = (datasets as unknown as RetrievalEvaluationDatasetRow[]).map((d) => d.id);

  const { data: corpusItems, error: corpusError } = await supabase.from("retrieval_evaluation_corpus_items").select("dataset_id").in("dataset_id", datasetIds);
  if (corpusError) throw corpusError;

  const { data: queries, error: queriesError } = await supabase.from("retrieval_evaluation_queries").select("dataset_id").in("dataset_id", datasetIds);
  if (queriesError) throw queriesError;

  const corpusCounts = new Map<string, number>();
  for (const row of (corpusItems as unknown as { dataset_id: string }[]) ?? []) {
    corpusCounts.set(row.dataset_id, (corpusCounts.get(row.dataset_id) ?? 0) + 1);
  }
  const queryCounts = new Map<string, number>();
  for (const row of (queries as unknown as { dataset_id: string }[]) ?? []) {
    queryCounts.set(row.dataset_id, (queryCounts.get(row.dataset_id) ?? 0) + 1);
  }

  return (datasets as unknown as RetrievalEvaluationDatasetRow[]).map((dataset) => ({
    dataset,
    corpusItemCount: corpusCounts.get(dataset.id) ?? 0,
    queryCount: queryCounts.get(dataset.id) ?? 0,
  }));
}

export interface JudgmentCoverage {
  /** Active, non-negative-control queries — the population freeze-gating cares about. */
  gatingQueryCount: number;
  /** Of those, how many already have at least one grade >= 2 judgment. */
  judgedQueryCount: number;
  /** query_key values still missing a grade >= 2 judgment — blocks freezing until empty. */
  unjudgedQueryKeys: string[];
  /** Active negative-control queries that have a grade >= 2 judgment — also blocks freezing. */
  negativeControlFalsePositiveKeys: string[];
}

/**
 * Mirrors freeze_retrieval_evaluation_dataset's own two gating checks
 * (migration 0014 §13) purely for legibility in the judgment workspace —
 * the database remains the sole source of truth; this is a read-only
 * preview so reviewers can see readiness before attempting a freeze.
 */
export function computeJudgmentCoverage(queries: RetrievalEvaluationQueryRow[], judgments: RetrievalRelevanceJudgmentRow[]): JudgmentCoverage {
  const relevantJudgmentQueryIds = new Set(judgments.filter((j) => j.relevance_grade >= 2).map((j) => j.query_id));

  const gatingQueries = queries.filter((q) => q.active && !q.is_negative_control);
  const unjudgedQueryKeys = gatingQueries.filter((q) => !relevantJudgmentQueryIds.has(q.id)).map((q) => q.query_key);

  const negativeControlQueries = queries.filter((q) => q.active && q.is_negative_control);
  const negativeControlFalsePositiveKeys = negativeControlQueries.filter((q) => relevantJudgmentQueryIds.has(q.id)).map((q) => q.query_key);

  return {
    gatingQueryCount: gatingQueries.length,
    judgedQueryCount: gatingQueries.length - unjudgedQueryKeys.length,
    unjudgedQueryKeys,
    negativeControlFalsePositiveKeys,
  };
}

export interface RetrievalEvaluationDatasetDetail {
  dataset: RetrievalEvaluationDatasetRow;
  corpusItems: RetrievalEvaluationCorpusItemRow[];
  queries: RetrievalEvaluationQueryRow[];
  judgments: RetrievalRelevanceJudgmentRow[];
  judgmentCoverage: JudgmentCoverage;
}

export async function getRetrievalEvaluationDatasetDetail(datasetId: string): Promise<RetrievalEvaluationDatasetDetail | null> {
  const dataset = await getRetrievalEvaluationDataset(datasetId);
  if (!dataset) return null;

  const [corpusItems, queries, judgments] = await Promise.all([listCorpusItems(datasetId), listEvaluationQueries(datasetId), listRelevanceJudgments(datasetId)]);

  return { dataset, corpusItems, queries, judgments, judgmentCoverage: computeJudgmentCoverage(queries, judgments) };
}

export interface RetrievalEvaluationRunDetail {
  run: RetrievalEvaluationRunRow;
  results: RetrievalEvaluationResultRow[];
  metrics: RetrievalEvaluationMetricRow[];
  failures: RetrievalEvaluationFailureRow[];
}

export async function getRetrievalEvaluationRunDetail(runId: string): Promise<RetrievalEvaluationRunDetail | null> {
  const run = await getRetrievalEvaluationRun(runId);
  if (!run) return null;

  const [results, metrics, failures] = await Promise.all([listEvaluationResults(runId), listEvaluationMetrics(runId), listEvaluationFailures(runId)]);

  return { run, results, metrics, failures };
}
