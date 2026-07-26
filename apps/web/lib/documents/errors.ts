export class DocumentIntakeError extends Error {
  readonly code: string;

  constructor(message: string, code = "document_intake_error") {
    super(message);
    this.name = "DocumentIntakeError";
    this.code = code;
  }
}

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

/**
 * Maps a Postgres/PostgREST error (from a failed `supabase.rpc(...)` call
 * in the document-intake flow) to a safe, specific message where the cause
 * is well-known — mirrors apps/web/lib/guidelines/errors.ts's approach.
 */
export function toDocumentIntakeError(error: PostgrestErrorLike): DocumentIntakeError {
  const raw = error.message ?? "";

  if (error.code === "42501" || raw.includes("permission denied")) {
    return new DocumentIntakeError("You do not have permission to perform this action.", "permission_denied");
  }
  if (raw.includes("not eligible for a new source document upload")) {
    return new DocumentIntakeError("This guideline version cannot receive a new source document in its current status.", "not_eligible");
  }
  if (raw.includes("already has an active primary source document")) {
    return new DocumentIntakeError("This guideline version already has a source document on file.", "already_has_primary");
  }
  if (raw.includes("only application/pdf")) {
    return new DocumentIntakeError("Only PDF files are supported.", "unsupported_file_type");
  }
  if (raw.includes("expected_size_bytes must be")) {
    return new DocumentIntakeError("The file size is outside the allowed range.", "invalid_size");
  }
  if (raw.includes("upload session expired")) {
    return new DocumentIntakeError("This upload session has expired. Start a new upload.", "session_expired");
  }
  if (raw.includes("session can be cancelled")) {
    return new DocumentIntakeError("This upload can no longer be cancelled.", "not_cancellable");
  }
  if (raw.includes("only a queued job can be cancelled")) {
    return new DocumentIntakeError("This job can no longer be cancelled.", "job_not_cancellable");
  }
  if (raw.includes("file identity cannot be changed")) {
    return new DocumentIntakeError("A verified source document cannot be replaced. Create a new guideline version instead.", "immutable");
  }
  if (raw.includes("not found")) {
    return new DocumentIntakeError("The requested item could not be found.", "not_found");
  }
  if (error.code === "23514" || raw.includes("violates check constraint")) {
    return new DocumentIntakeError("One of the provided values is not valid.", "invalid_value");
  }

  return new DocumentIntakeError("The action could not be completed. Please try again.", "unknown");
}
