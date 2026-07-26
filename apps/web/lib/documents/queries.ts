import { createClient } from "@/lib/supabase/server";

export type DocumentStatus = "pending_upload" | "uploaded" | "verified" | "registered" | "rejected" | "quarantined";
export type UploadSessionStatus = "created" | "authorized" | "completed" | "expired" | "rejected" | "cancelled";
export type ProcessingJobStatus = "queued" | "claimed" | "processing" | "succeeded" | "failed" | "cancelled" | "dead_lettered";

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

export async function listDocumentProcessingJobs(sourceDocumentId: string): Promise<DocumentProcessingJobRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("document_processing_jobs")
    .select("*")
    .eq("source_document_id", sourceDocumentId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function getDocumentProcessingJob(id: string): Promise<DocumentProcessingJobRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("document_processing_jobs").select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  return data;
}
