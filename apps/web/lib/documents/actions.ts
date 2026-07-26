"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getPublicEnv } from "@/lib/env/public";
import { toDocumentIntakeError, DocumentIntakeError } from "@/lib/documents/errors";
import {
  uploadSessionRequestSchema,
  uploadCompletionSchema,
  cancelUploadSessionSchema,
  quarantineDocumentSchema,
  jobCancellationSchema,
  type UploadSessionRequest,
} from "@/lib/documents/schemas";
import { MAX_UPLOAD_SIZE_BYTES } from "@/lib/documents/config";
import { computeFileFactsFromStream } from "@/lib/documents/streamVerification";

export interface UploadAuthorization {
  uploadSessionId: string;
  sourceDocumentId: string;
  storageBucket: string;
  storagePath: string;
  signedUploadToken: string;
  expiresAt: string;
}

/**
 * Step 1 of the secure upload flow. Creates the database records (via the
 * SECURITY DEFINER RPC, which enforces permission, eligibility, and
 * one-primary-per-version), then requests a signed upload authorization
 * from Supabase Storage for the exact server-generated path — using this
 * same session-bound client, so the existing `noor_buckets_insert_own_org`
 * RLS policy on storage.objects is what actually authorizes the upload
 * (no service-role key is used anywhere in this flow). Called directly
 * from a Client Component, not via <form action>, since it must return
 * structured data (the signed upload token) back to browser JS that then
 * performs the actual PUT to Storage.
 */
export async function createGuidelineUploadSessionAction(input: UploadSessionRequest): Promise<UploadAuthorization> {
  await requirePermission(PERMISSIONS.GUIDELINE_DOCUMENTS_UPLOAD);
  const parsed = uploadSessionRequestSchema.safeParse(input);
  if (!parsed.success) {
    throw new DocumentIntakeError(parsed.error.issues[0]?.message ?? "Invalid upload request.", "invalid_input");
  }

  const supabase = await createClient();
  const correlationId = randomUUID();

  const { data, error } = await supabase
    .rpc("create_guideline_upload_session", {
      p_guideline_version_id: parsed.data.guidelineVersionId,
      p_filename: parsed.data.filename,
      p_declared_media_type: parsed.data.declaredMediaType,
      p_expected_size_bytes: parsed.data.expectedSizeBytes ?? null,
      p_expected_sha256: parsed.data.expectedSha256 ?? null,
      p_idempotency_key: parsed.data.idempotencyKey ?? null,
      p_correlation_id: correlationId,
    })
    .single();

  if (error) throw toDocumentIntakeError(error);
  const row = data as { upload_session_id: string; source_document_id: string; storage_bucket: string; storage_path: string; expires_at: string };

  const { data: signed, error: storageError } = await supabase.storage
    .from(row.storage_bucket)
    .createSignedUploadUrl(row.storage_path);

  if (storageError || !signed) {
    throw new DocumentIntakeError("Could not authorize the upload. Please try again.", "storage_authorization_failed");
  }

  return {
    uploadSessionId: row.upload_session_id,
    sourceDocumentId: row.source_document_id,
    storageBucket: row.storage_bucket,
    storagePath: row.storage_path,
    signedUploadToken: signed.token,
    expiresAt: row.expires_at,
  };
}

export interface UploadCompletionResult {
  sourceDocumentId: string;
  documentStatus: string;
  sessionStatus: string;
  processingJobId: string | null;
  duplicateOfDocumentId: string | null;
}

/**
 * Step 2 of the secure upload flow. Never trusts the browser's claim that
 * the upload succeeded or what the file contains (Sprint 1.1 mission §13,
 * ADR 0008): independently re-fetches the object from Storage using this
 * same session's own access token (authorized by the same RLS policy that
 * authorized the upload — no service-role key), checks size and the PDF
 * signature, computes SHA-256 over the actual bytes, and only then calls
 * the RPC that atomically records the verification decision, registers
 * the document, and queues a processing job.
 *
 * Streams the object rather than buffering it whole (Sprint 1.2A review):
 * the original implementation used supabase-js's `.download()`, which
 * returns a Blob and forces the entire file — up to
 * MAX_UPLOAD_SIZE_BYTES — into memory before any check runs. This uses a
 * raw `fetch()` against the Storage REST endpoint instead, so
 * `computeFileFactsFromStream` can hash and size-check incrementally and
 * abort the connection the moment the size limit is exceeded, never
 * downloading (or holding in memory) more than a few KB of a truncated
 * oversized file.
 */
export async function completeGuidelineUploadAction(uploadSessionId: string): Promise<UploadCompletionResult> {
  await requirePermission(PERMISSIONS.GUIDELINE_DOCUMENTS_UPLOAD);
  const parsed = uploadCompletionSchema.safeParse({ uploadSessionId });
  if (!parsed.success) {
    throw new DocumentIntakeError("Invalid upload session.", "invalid_input");
  }

  const supabase = await createClient();
  const correlationId = randomUUID();

  const { data: session, error: sessionError } = await supabase
    .from("document_upload_sessions")
    .select("id, storage_bucket, storage_path, guideline_version_id")
    .eq("id", parsed.data.uploadSessionId)
    .maybeSingle();
  if (sessionError) throw toDocumentIntakeError(sessionError);
  if (!session) throw new DocumentIntakeError("Upload session not found.", "not_found");

  const {
    data: { session: authSession },
  } = await supabase.auth.getSession();
  if (!authSession) throw new DocumentIntakeError("Your session has expired. Sign in again.", "unauthenticated");

  let detectedMediaType: string | null = null;
  let sizeBytes: number | null = null;
  let sha256: string | null = null;
  let rejectionReason: string | null = null;

  const env = getPublicEnv();
  const objectUrl = `${env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/${session.storage_bucket}/${session.storage_path}`;
  const response = await fetch(objectUrl, {
    headers: {
      Authorization: `Bearer ${authSession.access_token}`,
      apikey: env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    },
  });

  if (!response.ok || !response.body) {
    rejectionReason = "the uploaded object could not be found in storage";
  } else {
    const facts = await computeFileFactsFromStream(response.body);
    sizeBytes = facts.sizeBytes;
    sha256 = facts.sha256;
    detectedMediaType = facts.signatureValid ? "application/pdf" : "application/octet-stream";

    if (facts.sizeBytes <= 0) {
      rejectionReason = "the uploaded file is empty";
    } else if (facts.oversized) {
      rejectionReason = `the uploaded file exceeds the ${MAX_UPLOAD_SIZE_BYTES / (1024 * 1024)} MB limit`;
    } else if (!facts.signatureValid) {
      // PDF signature check — confirms supported file type; it does NOT
      // prove the file is safe or clinically valid (see KNOWN_LIMITATIONS.md).
      rejectionReason = "the uploaded file does not have a valid PDF signature";
    }
  }

  const { data, error } = await supabase
    .rpc("complete_guideline_upload", {
      p_upload_session_id: parsed.data.uploadSessionId,
      p_detected_media_type: detectedMediaType,
      p_size_bytes: sizeBytes,
      p_sha256: sha256,
      p_rejection_reason: rejectionReason,
      p_correlation_id: correlationId,
    })
    .single();

  if (error) throw toDocumentIntakeError(error);
  const row = data as {
    source_document_id: string;
    document_status: string;
    session_status: string;
    processing_job_id: string | null;
    duplicate_of_document_id: string | null;
  };

  const { data: version } = await supabase
    .from("guideline_versions")
    .select("guideline_id")
    .eq("id", session.guideline_version_id)
    .maybeSingle();
  if (version) revalidatePath(`/knowledge/guidelines/${version.guideline_id}`);

  return {
    sourceDocumentId: row.source_document_id,
    documentStatus: row.document_status,
    sessionStatus: row.session_status,
    processingJobId: row.processing_job_id,
    duplicateOfDocumentId: row.duplicate_of_document_id,
  };
}

function text(formData: FormData, key: string): string {
  return String(formData.get(key) ?? "").trim();
}
function withError(path: string, message: string): never {
  redirect(`${path}?error=${encodeURIComponent(message)}`);
}

export async function cancelUploadSessionAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_DOCUMENTS_UPLOAD);
  const guidelineId = text(formData, "guidelineId");
  const returnTo = `/knowledge/guidelines/${guidelineId}`;

  const parsed = cancelUploadSessionSchema.safeParse({
    uploadSessionId: text(formData, "uploadSessionId"),
    reason: text(formData, "reason") || undefined,
  });
  if (!parsed.success) withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid request.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_upload_session", {
    p_upload_session_id: parsed.data.uploadSessionId,
    p_reason: parsed.data.reason ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toDocumentIntakeError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function quarantineGuidelineSourceDocumentAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_DOCUMENTS_REJECT);
  const guidelineId = text(formData, "guidelineId");
  const returnTo = `/knowledge/guidelines/${guidelineId}`;

  const parsed = quarantineDocumentSchema.safeParse({
    sourceDocumentId: text(formData, "sourceDocumentId"),
    reason: text(formData, "reason"),
  });
  if (!parsed.success) withError(returnTo, parsed.error.issues[0]?.message ?? "A reason is required.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("quarantine_guideline_source_document", {
    p_source_document_id: parsed.data.sourceDocumentId,
    p_reason: parsed.data.reason,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toDocumentIntakeError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}

export async function cancelProcessingJobAction(formData: FormData): Promise<void> {
  await requirePermission(PERMISSIONS.GUIDELINE_PROCESSING_JOBS_CANCEL);
  const guidelineId = text(formData, "guidelineId");
  const returnTo = `/knowledge/guidelines/${guidelineId}`;

  const parsed = jobCancellationSchema.safeParse({
    processingJobId: text(formData, "processingJobId"),
    reason: text(formData, "reason") || undefined,
  });
  if (!parsed.success) withError(returnTo, parsed.error.issues[0]?.message ?? "Invalid request.");

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_processing_job", {
    p_processing_job_id: parsed.data.processingJobId,
    p_reason: parsed.data.reason ?? null,
    p_correlation_id: randomUUID(),
  });
  if (error) withError(returnTo, toDocumentIntakeError(error).message);

  revalidatePath(returnTo);
  redirect(returnTo);
}
