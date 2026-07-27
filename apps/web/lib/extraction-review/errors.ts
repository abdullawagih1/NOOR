export class ExtractionReviewError extends Error {
  readonly code: string;

  constructor(message: string, code = "extraction_review_error") {
    super(message);
    this.name = "ExtractionReviewError";
    this.code = code;
  }
}

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

/**
 * Maps a Postgres/PostgREST error from an extraction-review RPC call to a
 * safe, specific message where the cause is well-known — mirrors
 * apps/web/lib/documents/errors.ts's approach.
 */
export function toExtractionReviewError(error: PostgrestErrorLike): ExtractionReviewError {
  const raw = error.message ?? "";

  if (error.code === "42501" || raw.includes("permission denied") || raw.includes("cannot review its own extraction") || raw.includes("assigned to a different reviewer") || raw.includes("only the assigned reviewer")) {
    return new ExtractionReviewError("You do not have permission to perform this action.", "permission_denied");
  }
  if (raw.includes("can only be opened for a succeeded extraction run")) {
    return new ExtractionReviewError("A review can only be opened once extraction has succeeded.", "not_succeeded");
  }
  if (raw.includes("does not hold review permission")) {
    return new ExtractionReviewError("That person does not hold reviewer permission in this organization.", "reviewer_lacks_permission");
  }
  if (raw.includes("already assigned")) {
    return new ExtractionReviewError("This review round is already assigned.", "already_assigned");
  }
  if (raw.includes("can only be (re)assigned")) {
    return new ExtractionReviewError("Only an active review round can be reassigned.", "not_active");
  }
  if (raw.includes("can only be started from pending_review")) {
    return new ExtractionReviewError("This review has already been started.", "already_started");
  }
  if (raw.includes("can only be reviewed while the round is in_review") || raw.includes("can only be created while the round is in_review") || raw.includes("can only be updated while the review round is in_review")) {
    return new ExtractionReviewError("This review round is not currently active.", "not_in_review");
  }
  if (raw.includes("does not belong to this review")) {
    return new ExtractionReviewError("That page does not belong to this extraction run.", "page_mismatch");
  }
  if (raw.includes('"other" finding') || raw.includes("violates check constraint")) {
    return new ExtractionReviewError("One of the provided values is not valid.", "invalid_value");
  }
  if (raw.includes("requires a resolution note")) {
    return new ExtractionReviewError("Dismissing or accepting the risk of a major or critical finding requires a reason.", "resolution_note_required");
  }
  if (raw.includes("every page must be marked reviewed")) {
    return new ExtractionReviewError("Every page must be marked reviewed before a decision can be submitted.", "pages_not_reviewed");
  }
  if (raw.includes("accepted requires zero open")) {
    return new ExtractionReviewError("Accepted requires resolving all open critical and major findings first.", "open_findings_block_accept");
  }
  if (raw.includes("accepted_with_warnings requires zero open critical")) {
    return new ExtractionReviewError("Accepted with warnings requires resolving all open critical findings first.", "open_critical_findings_block_accept");
  }
  if (raw.includes("accepted_with_warnings requires a warning_summary")) {
    return new ExtractionReviewError("A warning summary is required for accepted with warnings.", "warning_summary_required");
  }
  if (raw.includes("ocr_required requires at least one supporting finding")) {
    return new ExtractionReviewError("OCR required needs at least one supporting finding (image-only, suspected scanned, missing, or partial text).", "ocr_finding_required");
  }
  if (raw.includes("reprocessing_required requires at least one supporting finding")) {
    return new ExtractionReviewError("Reprocessing required needs at least one supporting finding.", "reprocessing_finding_required");
  }
  if (raw.includes("requires a decision_reason")) {
    return new ExtractionReviewError("A reason is required for this decision.", "decision_reason_required");
  }
  if (raw.includes("rejected requires at least one major or critical finding")) {
    return new ExtractionReviewError("Rejected requires at least one major or critical finding.", "rejected_finding_required");
  }
  if (raw.includes("can only be submitted from in_review")) {
    return new ExtractionReviewError("This review is not ready to be submitted.", "not_ready_to_submit");
  }
  if (raw.includes("no longer succeeded")) {
    return new ExtractionReviewError("The underlying extraction is no longer in a succeeded state.", "run_not_succeeded");
  }
  if (raw.includes("immutable") || raw.includes("illegal extraction review transition") || raw.includes("append-only")) {
    return new ExtractionReviewError("This review record cannot be changed.", "immutable");
  }
  if (raw.includes("only a submitted, non-invalidated decision can be reopened")) {
    return new ExtractionReviewError("Only a submitted decision can be reopened.", "not_reopenable");
  }
  if (raw.includes("only an accepted or accepted_with_warnings review can be invalidated")) {
    return new ExtractionReviewError("Only an accepted review can be invalidated.", "not_invalidatable");
  }
  if (raw.includes("requires a reason")) {
    return new ExtractionReviewError("A reason is required.", "reason_required");
  }
  if (raw.includes("not found")) {
    return new ExtractionReviewError("The requested item could not be found.", "not_found");
  }

  return new ExtractionReviewError("The action could not be completed. Please try again.", "unknown");
}
