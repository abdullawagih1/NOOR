export class OcrReviewError extends Error {
  readonly code: string;

  constructor(message: string, code = "ocr_error") {
    super(message);
    this.name = "OcrReviewError";
    this.code = code;
  }
}

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

/**
 * Maps a Postgres/PostgREST error from an OCR RPC call to a safe, specific
 * message where the cause is well-known — mirrors
 * apps/web/lib/extraction-review/errors.ts's approach one layer deeper.
 */
export function toOcrReviewError(error: PostgrestErrorLike): OcrReviewError {
  const raw = error.message ?? "";

  if (
    error.code === "42501" ||
    raw.includes("permission denied") ||
    raw.includes("cannot review its own OCR output") ||
    raw.includes("assigned to a different reviewer") ||
    raw.includes("only the assigned reviewer") ||
    raw.includes("or an authorized quality/admin override")
  ) {
    return new OcrReviewError("You do not have permission to perform this action.", "permission_denied");
  }
  if (raw.includes("can only be created from an ocr_required extraction review")) {
    return new OcrReviewError("An OCR request can only be created from an extraction review decided ocr_required.", "not_ocr_required");
  }
  if (raw.includes("has been superseded by a later round") || raw.includes("has been superseded and is no longer eligible")) {
    return new OcrReviewError("This extraction review round has been superseded — a newer round exists.", "superseded");
  }
  if (raw.includes("no longer succeeded")) {
    return new OcrReviewError("The underlying extraction is no longer in a succeeded state.", "run_not_succeeded");
  }
  if (raw.includes("no pages were marked ocr_candidate")) {
    return new OcrReviewError("No pages were flagged for OCR in this extraction review.", "no_ocr_candidate_pages");
  }
  if (raw.includes("already terminal") && raw.includes("cannot be cancelled")) {
    return new OcrReviewError("This OCR request has already reached a final state and cannot be cancelled.", "already_terminal");
  }
  if (raw.includes("must reach a terminal execution state before a review can be opened")) {
    return new OcrReviewError("Every OCR page must finish processing before a review can be opened.", "pages_not_terminal");
  }
  if (raw.includes("can only be (re)assigned")) {
    return new OcrReviewError("Only an active OCR review round can be reassigned.", "not_active");
  }
  if (raw.includes("does not hold OCR review permission")) {
    return new OcrReviewError("That person does not hold OCR review permission in this organization.", "reviewer_lacks_permission");
  }
  if (raw.includes("already assigned")) {
    return new OcrReviewError("This OCR review round is already assigned.", "already_assigned");
  }
  if (raw.includes("can only be claimed")) {
    return new OcrReviewError("Only an active OCR review round can be claimed.", "not_claimable");
  }
  if (raw.includes("can only be started from pending_review")) {
    return new OcrReviewError("This OCR review has already been started.", "already_started");
  }
  if (raw.includes("can only be reviewed while the round is in_review") || raw.includes("can only be created while the round is in_review") || raw.includes("can only be updated while the review round is in_review")) {
    return new OcrReviewError("This OCR review round is not currently active.", "not_in_review");
  }
  if (raw.includes("is not part of this OCR request")) {
    return new OcrReviewError("That page does not belong to this OCR request.", "page_mismatch");
  }
  if (raw.includes("invalid OCR page review status") || raw.includes("invalid OCR finding status") || raw.includes("invalid target OCR review status") || raw.includes("violates check constraint")) {
    return new OcrReviewError("One of the provided values is not valid.", "invalid_value");
  }
  if (raw.includes("requires a resolution note")) {
    return new OcrReviewError("Dismissing or accepting the risk of a major or critical finding requires a reason.", "resolution_note_required");
  }
  if (raw.includes("every OCR page must be marked reviewed")) {
    return new OcrReviewError("Every OCR page must be marked reviewed before a decision can be submitted.", "pages_not_reviewed");
  }
  if (raw.includes("accepted requires every requested OCR page to have succeeded")) {
    return new OcrReviewError("Accepted requires every requested OCR page to have succeeded.", "pages_not_succeeded");
  }
  if (raw.includes("accepted requires zero open")) {
    return new OcrReviewError("Accepted requires resolving all open critical and major findings first.", "open_findings_block_accept");
  }
  if (raw.includes("accepted_with_warnings requires zero open critical")) {
    return new OcrReviewError("Accepted with warnings requires resolving all open critical findings first.", "open_critical_findings_block_accept");
  }
  if (raw.includes("accepted_with_warnings requires a warning_summary")) {
    return new OcrReviewError("A warning summary is required for accepted with warnings.", "warning_summary_required");
  }
  if (raw.includes("reprocessing_required requires at least one supporting OCR finding")) {
    return new OcrReviewError("Reprocessing required needs at least one supporting finding.", "reprocessing_finding_required");
  }
  if (raw.includes("requires a decision_reason")) {
    return new OcrReviewError("A reason is required for this decision.", "decision_reason_required");
  }
  if (raw.includes("can only be submitted from in_review")) {
    return new OcrReviewError("This OCR review is not ready to be submitted.", "not_ready_to_submit");
  }
  if (raw.includes("immutable") || raw.includes("illegal OCR review transition") || raw.includes("frozen once the parent review round is submitted") || raw.includes("cannot be deleted")) {
    return new OcrReviewError("This OCR review record cannot be changed.", "immutable");
  }
  if (raw.includes("only a submitted, non-invalidated OCR decision can be reopened")) {
    return new OcrReviewError("Only a submitted OCR decision can be reopened.", "not_reopenable");
  }
  if (raw.includes("only an accepted or accepted_with_warnings OCR review can be invalidated")) {
    return new OcrReviewError("Only an accepted OCR review can be invalidated.", "not_invalidatable");
  }
  if (raw.includes("requires a reason")) {
    return new OcrReviewError("A reason is required.", "reason_required");
  }
  if (raw.includes("not found")) {
    return new OcrReviewError("The requested item could not be found.", "not_found");
  }

  return new OcrReviewError("The action could not be completed. Please try again.", "unknown");
}
