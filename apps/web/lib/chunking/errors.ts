export class ChunkingReviewError extends Error {
  readonly code: string;

  constructor(message: string, code = "chunking_error") {
    super(message);
    this.name = "ChunkingReviewError";
    this.code = code;
  }
}

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

/**
 * Maps a Postgres/PostgREST error from a chunking RPC call to a safe,
 * specific message where the cause is well-known — mirrors
 * apps/web/lib/ocr/errors.ts's approach one layer deeper.
 */
export function toChunkingReviewError(error: PostgrestErrorLike): ChunkingReviewError {
  const raw = error.message ?? "";

  if (
    error.code === "42501" ||
    raw.includes("permission denied") ||
    raw.includes("cannot review its own chunking output") ||
    raw.includes("assigned to a different reviewer") ||
    raw.includes("only the assigned reviewer")
  ) {
    return new ChunkingReviewError("You do not have permission to perform this action.", "permission_denied");
  }
  if (raw.includes("not chunking-eligible") || raw.includes("is not registered")) {
    return new ChunkingReviewError("This document is not currently eligible for chunking.", "not_eligible");
  }
  if (raw.includes("no succeeded extraction run exists")) {
    return new ChunkingReviewError("No succeeded extraction run exists for this document yet.", "no_extraction_run");
  }
  if (raw.includes("chunking review can only be created for a succeeded run")) {
    return new ChunkingReviewError("A chunk review can only be opened once chunking has succeeded.", "run_not_succeeded");
  }
  if (raw.includes("can only be (re)assigned")) {
    return new ChunkingReviewError("Only an active chunking review round can be reassigned.", "not_active");
  }
  if (raw.includes("does not hold chunking review permission")) {
    return new ChunkingReviewError("That person does not hold chunking review permission in this organization.", "reviewer_lacks_permission");
  }
  if (raw.includes("already assigned")) {
    return new ChunkingReviewError("This chunking review round is already assigned.", "already_assigned");
  }
  if (raw.includes("only a pending_review round can be self-claimed")) {
    return new ChunkingReviewError("Only an active chunking review round can be claimed.", "not_claimable");
  }
  if (raw.includes("can only be started from pending_review")) {
    return new ChunkingReviewError("This chunking review has already been started.", "already_started");
  }
  if (raw.includes("can only be marked while the review is in_review") || raw.includes("findings can only be created while the review is in_review")) {
    return new ChunkingReviewError("This chunking review round is not currently active.", "not_in_review");
  }
  if (raw.includes("chunk index") && raw.includes("not found")) {
    return new ChunkingReviewError("That chunk does not belong to this review.", "chunk_mismatch");
  }
  if (raw.includes("invalid chunk review status") || raw.includes("invalid finding status") || raw.includes("invalid target chunking review status") || raw.includes("violates check constraint")) {
    return new ChunkingReviewError("One of the provided values is not valid.", "invalid_value");
  }
  if (raw.includes("every chunk must be marked reviewed")) {
    return new ChunkingReviewError("Every chunk must be marked reviewed before a decision can be submitted.", "chunks_not_reviewed");
  }
  if (raw.includes("accepted requires zero open critical or major")) {
    return new ChunkingReviewError("Accepted requires resolving all open critical and major findings first.", "open_findings_block_accept");
  }
  if (raw.includes("accepted_with_warnings requires zero open critical")) {
    return new ChunkingReviewError("Accepted with warnings requires resolving all open critical findings first.", "open_critical_findings_block_accept");
  }
  if (raw.includes("accepted_with_warnings requires a warning_summary")) {
    return new ChunkingReviewError("A warning summary is required for accepted with warnings.", "warning_summary_required");
  }
  if (raw.includes("rechunk_required requires at least one supporting finding")) {
    return new ChunkingReviewError("Rechunk required needs at least one supporting finding.", "rechunk_finding_required");
  }
  if (raw.includes("rejected requires at least one major or critical finding")) {
    return new ChunkingReviewError("Rejected requires at least one major or critical finding.", "rejected_finding_required");
  }
  if (raw.includes("requires a decision_reason")) {
    return new ChunkingReviewError("A reason is required for this decision.", "decision_reason_required");
  }
  if (raw.includes("can only be submitted from in_review")) {
    return new ChunkingReviewError("This chunking review is not ready to be submitted.", "not_ready_to_submit");
  }
  if (raw.includes("is already terminal") || raw.includes("immutable") || raw.includes("cannot be modified") || raw.includes("cannot be deleted")) {
    return new ChunkingReviewError("This chunking review record cannot be changed.", "immutable");
  }
  if (raw.includes("only a submitted, non-invalidated chunking decision can be reopened")) {
    return new ChunkingReviewError("Only a submitted chunking decision can be reopened.", "not_reopenable");
  }
  if (raw.includes("only a succeeded or reused chunking run can be invalidated")) {
    return new ChunkingReviewError("Only a succeeded chunking run can be invalidated.", "not_invalidatable");
  }
  if (raw.includes("requires a reason")) {
    return new ChunkingReviewError("A reason is required.", "reason_required");
  }
  if (raw.includes("not found")) {
    return new ChunkingReviewError("The requested item could not be found.", "not_found");
  }

  return new ChunkingReviewError("The action could not be completed. Please try again.", "unknown");
}
