import { createClient } from "@/lib/supabase/server";

export type DocumentStatus = "pending_upload" | "uploaded" | "verified" | "registered" | "rejected" | "quarantined";
export type UploadSessionStatus = "created" | "authorized" | "completed" | "expired" | "rejected" | "cancelled";
export type ProcessingJobStatus =
  | "queued"
  | "claimed"
  | "processing"
  | "retry_scheduled"
  | "succeeded"
  | "failed"
  | "cancelled"
  | "dead_lettered";
export type ProcessingAttemptStatus =
  | "started"
  | "succeeded"
  | "retryable_failure"
  | "terminal_failure"
  | "lease_expired"
  | "cancelled"
  | "abandoned";

export interface GuidelineSourceDocumentRow {
  id: string;
  organization_id: string;
  guideline_version_id: string;
  document_role: string;
  original_filename: string;
  declared_media_type: string;
  detected_media_type: string | null;
  size_bytes: number | null;
  sha256: string | null;
  status: DocumentStatus;
  rejection_reason: string | null;
  uploaded_by: string | null;
  uploaded_at: string | null;
  verified_at: string | null;
  registered_at: string | null;
  created_at: string;
}

export interface DocumentUploadSessionRow {
  id: string;
  organization_id: string;
  guideline_version_id: string;
  source_document_id: string;
  requested_filename: string;
  storage_bucket: string;
  storage_path: string;
  status: UploadSessionStatus;
  expires_at: string;
  created_at: string;
}

export interface DocumentProcessingJobRow {
  id: string;
  organization_id: string;
  source_document_id: string;
  job_type: string;
  status: ProcessingJobStatus;
  attempt_count: number;
  max_attempts: number;
  requested_at: string;
  started_at: string | null;
  completed_at: string | null;
  failed_at: string | null;
  cancelled_at: string | null;
  next_attempt_at: string | null;
  dead_lettered_at: string | null;
  error_code: string | null;
  error_class: string | null;
  error_message_safe: string | null;
  result_summary: Record<string, unknown>;
  created_at: string;
}

export interface DocumentProcessingAttemptRow {
  id: string;
  organization_id: string;
  processing_job_id: string;
  attempt_number: number;
  worker_id: string | null;
  status: ProcessingAttemptStatus;
  started_at: string;
  completed_at: string | null;
  error_code: string | null;
  error_class: string | null;
  error_message_safe: string | null;
  created_at: string;
}

export async function listGuidelineSourceDocuments(guidelineVersionId: string): Promise<GuidelineSourceDocumentRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("guideline_source_documents")
    .select("*")
    .eq("guideline_version_id", guidelineVersionId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function getGuidelineSourceDocument(id: string): Promise<GuidelineSourceDocumentRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("guideline_source_documents").select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  return data;
}

export async function getUploadSession(id: string): Promise<DocumentUploadSessionRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_upload_sessions").select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  return data;
}

// Explicit column lists (not `*`) for the two orchestration tables below —
// unlike the rest of this file, these rows carry internal lease-management
// columns (lease_token_hash, lease_acquired_at, lease_expires_at,
// claimed_by, heartbeat_at). Selecting only what's typed here means that
// data can never reach a Client Component even by accident.
const PROCESSING_JOB_COLUMNS =
  "id, organization_id, source_document_id, job_type, status, attempt_count, max_attempts, " +
  "requested_at, started_at, completed_at, failed_at, cancelled_at, next_attempt_at, " +
  "dead_lettered_at, error_code, error_class, error_message_safe, result_summary, created_at";

const PROCESSING_ATTEMPT_COLUMNS =
  "id, organization_id, processing_job_id, attempt_number, worker_id, status, started_at, " +
  "completed_at, error_code, error_class, error_message_safe, created_at";

export async function listDocumentProcessingJobs(sourceDocumentId: string): Promise<DocumentProcessingJobRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_processing_jobs")
    .select(PROCESSING_JOB_COLUMNS)
    .eq("source_document_id", sourceDocumentId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data as unknown as DocumentProcessingJobRow[]) ?? [];
}

export async function getDocumentProcessingJob(id: string): Promise<DocumentProcessingJobRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_processing_jobs")
    .select(PROCESSING_JOB_COLUMNS)
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as DocumentProcessingJobRow | null;
}

export async function listDocumentProcessingAttempts(processingJobId: string): Promise<DocumentProcessingAttemptRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_processing_attempts")
    .select(PROCESSING_ATTEMPT_COLUMNS)
    .eq("processing_job_id", processingJobId)
    .order("attempt_number", { ascending: true });
  if (error) throw error;
  return (data as unknown as DocumentProcessingAttemptRow[]) ?? [];
}
