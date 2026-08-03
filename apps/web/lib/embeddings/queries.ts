import { createClient } from "@/lib/supabase/server";

export type EmbeddingConfigurationApprovalStatus = "draft" | "approved" | "retired" | "blocked";
export type EmbeddingConfigurationProviderType = "self_hosted" | "external_api";
export type EmbeddingOutputNormalization = "l2_normalized" | "none";
export type EmbeddingDistanceMetric = "cosine" | "l2" | "inner_product";

export type DocumentEmbeddingRunStatus =
  | "created"
  | "queued"
  | "processing"
  | "succeeded"
  | "succeeded_with_reuse"
  | "failed"
  | "cancelled"
  | "invalidated"
  | "reused";

export type DocumentChunkEmbeddingStatus = "running" | "succeeded" | "failed" | "invalidated" | "reused";

export interface EmbeddingConfigurationRow {
  id: string;
  configuration_key: string;
  provider_name: string;
  provider_type: EmbeddingConfigurationProviderType;
  provider_version: string;
  model_identifier: string;
  model_revision: string;
  model_artifact_sha256: string | null;
  embedding_dimension: number;
  maximum_input_tokens: number;
  tokenizer_name: string;
  tokenizer_version: string;
  passage_input_template_version: string;
  query_input_template_version: string;
  output_normalization: EmbeddingOutputNormalization;
  distance_metric: EmbeddingDistanceMetric;
  configuration_version: string;
  data_region: string | null;
  data_retention_summary: string | null;
  external_processing: boolean;
  approval_status: EmbeddingConfigurationApprovalStatus;
  approved_by: string | null;
  approved_at: string | null;
  retired_at: string | null;
  created_at: string;
}

export interface DocumentEmbeddingRunRow {
  id: string;
  organization_id: string;
  source_document_id: string;
  guideline_version_id: string;
  chunking_run_id: string;
  chunking_review_id: string | null;
  embedding_configuration_id: string;
  chunk_manifest: Record<string, unknown>;
  chunk_manifest_sha256: string;
  run_identity_sha256: string;
  total_chunk_count: number;
  pending_count: number;
  processing_count: number;
  succeeded_count: number;
  failed_count: number;
  reused_count: number;
  invalidated_count: number;
  status: DocumentEmbeddingRunStatus;
  processing_job_id: string | null;
  processing_attempt_id: string | null;
  started_at: string;
  completed_at: string | null;
  failed_at: string | null;
  invalidated_at: string | null;
  invalidation_reason: string | null;
  artifact_bucket: string | null;
  artifact_path: string | null;
  artifact_sha256: string | null;
  artifact_size_bytes: number | null;
  artifact_media_type: string | null;
  created_at: string;
}

/**
 * Every column on document_chunk_embeddings EXCEPT vector_value — the raw
 * pgvector column is never selected anywhere in this module (mission §45:
 * clinicians and quality staff never see raw embedding numbers in the
 * browser). Any future addition to this constant must preserve that
 * omission.
 */
export interface DocumentChunkEmbeddingRow {
  id: string;
  organization_id: string;
  chunk_id: string;
  chunking_run_id: string;
  source_document_id: string;
  guideline_version_id: string;
  embedding_configuration_id: string;
  embedding_run_id: string;
  chunk_checksum: string;
  input_text_checksum: string;
  input_token_count: number;
  embedding_identity_sha256: string;
  embedding_dimension: number;
  vector_checksum: string | null;
  vector_norm: number | null;
  vector_serialization_version: string;
  provider_request_id_safe: string | null;
  provider_metadata_safe: Record<string, unknown>;
  status: DocumentChunkEmbeddingStatus;
  started_at: string;
  completed_at: string | null;
  failed_at: string | null;
  invalidated_at: string | null;
  invalidation_reason: string | null;
  processing_job_id: string;
  processing_attempt_id: string | null;
  created_at: string;
  created_by_worker: string | null;
}

const EMBEDDING_CONFIGURATION_COLUMNS =
  "id, configuration_key, provider_name, provider_type, provider_version, model_identifier, model_revision, " +
  "model_artifact_sha256, embedding_dimension, maximum_input_tokens, tokenizer_name, tokenizer_version, " +
  "passage_input_template_version, query_input_template_version, output_normalization, distance_metric, " +
  "configuration_version, data_region, data_retention_summary, external_processing, approval_status, " +
  "approved_by, approved_at, retired_at, created_at";

const DOCUMENT_EMBEDDING_RUN_COLUMNS =
  "id, organization_id, source_document_id, guideline_version_id, chunking_run_id, chunking_review_id, " +
  "embedding_configuration_id, chunk_manifest, chunk_manifest_sha256, run_identity_sha256, total_chunk_count, " +
  "pending_count, processing_count, succeeded_count, failed_count, reused_count, invalidated_count, status, " +
  "processing_job_id, processing_attempt_id, started_at, completed_at, failed_at, invalidated_at, " +
  "invalidation_reason, artifact_bucket, artifact_path, artifact_sha256, artifact_size_bytes, artifact_media_type, created_at";

const DOCUMENT_CHUNK_EMBEDDING_COLUMNS =
  "id, organization_id, chunk_id, chunking_run_id, source_document_id, guideline_version_id, " +
  "embedding_configuration_id, embedding_run_id, chunk_checksum, input_text_checksum, input_token_count, " +
  "embedding_identity_sha256, embedding_dimension, vector_checksum, vector_norm, vector_serialization_version, " +
  "provider_request_id_safe, provider_metadata_safe, status, started_at, completed_at, failed_at, invalidated_at, " +
  "invalidation_reason, processing_job_id, processing_attempt_id, created_at, created_by_worker";

/**
 * The one approved embedding configuration, read through
 * get_approved_embedding_configuration() rather than a plain `.from(...)`
 * select — embedding_configurations is not organization-scoped (a single
 * shared, server-managed row), so this RPC already implements the correct
 * "does the caller hold this permission in ANY of their organizations"
 * check (migration 0016 §10) instead of a per-row organization_id filter
 * this table does not have.
 */
export async function getApprovedEmbeddingConfiguration(): Promise<EmbeddingConfigurationRow> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_approved_embedding_configuration");
  if (error) throw error;
  return data as unknown as EmbeddingConfigurationRow;
}

export async function getEmbeddingConfiguration(id: string): Promise<EmbeddingConfigurationRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("embedding_configurations").select(EMBEDDING_CONFIGURATION_COLUMNS).eq("id", id).maybeSingle();
  if (error) throw error;
  return data as unknown as EmbeddingConfigurationRow | null;
}

export async function listEmbeddingConfigurationsByIds(ids: string[]): Promise<EmbeddingConfigurationRow[]> {
  if (ids.length === 0) return [];
  const supabase = await createClient();
  const { data, error } = await supabase.from("embedding_configurations").select(EMBEDDING_CONFIGURATION_COLUMNS).in("id", ids);
  if (error) throw error;
  return (data as unknown as EmbeddingConfigurationRow[]) ?? [];
}

export async function listDocumentEmbeddingRuns(organizationId: string): Promise<DocumentEmbeddingRunRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_embedding_runs")
    .select(DOCUMENT_EMBEDDING_RUN_COLUMNS)
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data as unknown as DocumentEmbeddingRunRow[]) ?? [];
}

export async function getDocumentEmbeddingRun(runId: string): Promise<DocumentEmbeddingRunRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_embedding_runs").select(DOCUMENT_EMBEDDING_RUN_COLUMNS).eq("id", runId).maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentEmbeddingRunRow | null;
}

export async function listDocumentChunkEmbeddingsBySourceDocument(sourceDocumentId: string): Promise<DocumentChunkEmbeddingRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_chunk_embeddings")
    .select(DOCUMENT_CHUNK_EMBEDDING_COLUMNS)
    .eq("source_document_id", sourceDocumentId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data as unknown as DocumentChunkEmbeddingRow[]) ?? [];
}

export async function listDocumentChunkEmbeddingsByRun(embeddingRunId: string): Promise<DocumentChunkEmbeddingRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_chunk_embeddings")
    .select(DOCUMENT_CHUNK_EMBEDDING_COLUMNS)
    .eq("embedding_run_id", embeddingRunId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentChunkEmbeddingRow[]) ?? [];
}

export interface DocumentEmbeddingRunDetail {
  run: DocumentEmbeddingRunRow;
  configuration: EmbeddingConfigurationRow | null;
  chunkEmbeddingCount: number;
  succeededCount: number;
}

/**
 * Coverage counts are recomputed here from the actual per-chunk rows
 * rather than trusted from document_embedding_runs.succeeded_count/
 * total_chunk_count directly — same "separate typed queries for
 * legibility" convention as computeJudgmentCoverage in
 * apps/web/lib/retrieval-evaluation/queries.ts, so a display bug in the
 * worker-maintained counters can't silently misreport coverage here.
 */
export async function getDocumentEmbeddingRunDetail(runId: string): Promise<DocumentEmbeddingRunDetail | null> {
  const run = await getDocumentEmbeddingRun(runId);
  if (!run) return null;

  const [configuration, chunkEmbeddings] = await Promise.all([getEmbeddingConfiguration(run.embedding_configuration_id), listDocumentChunkEmbeddingsByRun(runId)]);

  return {
    run,
    configuration,
    chunkEmbeddingCount: chunkEmbeddings.length,
    succeededCount: chunkEmbeddings.filter((e) => e.status === "succeeded").length,
  };
}
