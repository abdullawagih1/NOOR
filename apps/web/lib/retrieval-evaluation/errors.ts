export class RetrievalEvaluationError extends Error {
  readonly code: string;

  constructor(message: string, code = "retrieval_evaluation_error") {
    super(message);
    this.name = "RetrievalEvaluationError";
    this.code = code;
  }
}

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

/**
 * Maps a Postgres/PostgREST error from a retrieval-evaluation RPC call to a
 * safe, specific message where the cause is well-known — mirrors
 * apps/web/lib/chunking/errors.ts's toChunkingReviewError one layer over
 * (migrations 0014/0015, ADR 0015).
 */
export function toRetrievalEvaluationError(error: PostgrestErrorLike): RetrievalEvaluationError {
  const raw = error.message ?? "";

  if (error.code === "42501" || raw.includes("permission denied") || raw.includes("authentication required")) {
    return new RetrievalEvaluationError("You do not have permission to perform this action.", "permission_denied");
  }
  if (raw.includes("cannot review their own dataset")) {
    return new RetrievalEvaluationError(
      "You created this dataset, so you cannot also review it for freezing — the two-person rule requires a different reviewer.",
      "self_review_blocked"
    );
  }
  if (raw.includes("must be reviewed by someone other than its creator")) {
    return new RetrievalEvaluationError("This dataset must be reviewed by someone other than its creator before it can be frozen.", "review_required");
  }
  if (raw.includes("at least one corpus item")) {
    return new RetrievalEvaluationError("A dataset needs at least one corpus item before it can be submitted for review.", "corpus_item_required");
  }
  if (raw.includes("at least one active query")) {
    return new RetrievalEvaluationError("A dataset needs at least one active query before it can be submitted for review.", "active_query_required");
  }
  if (raw.includes("no relevant (grade >= 2) judgment")) {
    return new RetrievalEvaluationError("One or more queries have no relevant (grade 2 or 3) judgment yet — every active, non-negative-control query needs one before freezing.", "judgment_coverage_incomplete");
  }
  if (raw.includes("negative-control queries have a positive relevance judgment")) {
    return new RetrievalEvaluationError("A negative-control query has a positive relevance judgment — negative controls must have no relevant judgment before freezing.", "negative_control_false_positive");
  }
  if (raw.includes("requires a frozen dataset") || raw.includes("require a frozen dataset")) {
    return new RetrievalEvaluationError("An evaluation run requires a frozen dataset.", "dataset_not_frozen");
  }
  if (raw.includes("query_embedding_dataset_not_frozen")) {
    return new RetrievalEvaluationError("Query embeddings require a frozen dataset.", "dataset_not_frozen");
  }
  if (raw.includes("embedding_configuration_not_approved")) {
    return new RetrievalEvaluationError("No approved embedding configuration exists. Contact an administrator.", "embedding_configuration_not_approved");
  }
  if (raw.includes("dataset_embedding_gap")) {
    return new RetrievalEvaluationError(
      "One or more corpus items in this dataset do not yet have a succeeded chunk embedding at the approved configuration — generate embeddings for the source documents first.",
      "dataset_embedding_gap"
    );
  }
  if (raw.includes("query_embedding_coverage_incomplete")) {
    return new RetrievalEvaluationError(
      "One or more active queries do not yet have a succeeded query embedding — generate query embeddings for this dataset first.",
      "query_embedding_coverage_incomplete"
    );
  }
  if (raw.includes("no longer embedding-ready")) {
    return new RetrievalEvaluationError("A corpus item is no longer embedding-ready — remove it before submitting for review or freezing.", "not_embedding_ready");
  }
  if (raw.includes("is not currently embedding-ready")) {
    return new RetrievalEvaluationError("That chunk is not currently embedding-ready and cannot be added as a corpus item.", "not_embedding_ready");
  }
  if (raw.includes("no longer frozen")) {
    return new RetrievalEvaluationError("This dataset is no longer frozen — its evaluation runs are no longer valid.", "dataset_no_longer_frozen");
  }
  if (raw.includes("must be 0, 1, 2, or 3")) {
    return new RetrievalEvaluationError("A relevance grade must be 0, 1, 2, or 3.", "invalid_relevance_grade");
  }
  if (raw.includes("can only be edited while draft") || raw.includes("can only be added while the dataset is draft") || raw.includes("can only be removed while the dataset is draft")) {
    return new RetrievalEvaluationError("This can only be changed while the dataset is a draft.", "not_draft");
  }
  if (raw.includes("only a draft dataset can be submitted for review")) {
    return new RetrievalEvaluationError("Only a draft dataset can be submitted for review.", "not_draft");
  }
  if (raw.includes("only a ready_for_review dataset can return to draft")) {
    return new RetrievalEvaluationError("Only a dataset that is ready for review can be returned to draft.", "not_ready_for_review");
  }
  if (raw.includes("only a ready_for_review dataset can be marked reviewed")) {
    return new RetrievalEvaluationError("Only a dataset that is ready for review can be marked reviewed.", "not_ready_for_review");
  }
  if (raw.includes("a dataset can only be frozen from ready_for_review")) {
    return new RetrievalEvaluationError("A dataset can only be frozen once it is ready for review and has been reviewed.", "not_ready_for_review");
  }
  if (raw.includes("only a frozen dataset can be archived")) {
    return new RetrievalEvaluationError("Only a frozen dataset can be archived.", "not_frozen");
  }
  if (raw.includes("queries can only be added while the dataset is draft") || raw.includes("queries can only be edited while the dataset is draft")) {
    return new RetrievalEvaluationError("Queries can only be added or edited while the dataset is a draft.", "not_draft");
  }
  if (raw.includes("judgments can only be added while the dataset is draft") || raw.includes("judgments can only be edited while the dataset is draft")) {
    return new RetrievalEvaluationError("Judgments can only be added or edited while the dataset is a draft.", "not_draft");
  }
  if (raw.includes("query and corpus item belong to different datasets")) {
    return new RetrievalEvaluationError("That query and corpus item do not belong to the same dataset.", "dataset_mismatch");
  }
  if (raw.includes("returning a dataset to draft requires a reason") || raw.includes("cancelling a run requires a reason") || raw.includes("requires a reason")) {
    return new RetrievalEvaluationError("A reason is required.", "reason_required");
  }
  if (raw.includes("only a running evaluation run can be cancelled")) {
    return new RetrievalEvaluationError("Only a running evaluation run can be cancelled.", "not_running");
  }
  if (raw.includes("a failure annotation's core content is immutable") || raw.includes("core content is immutable")) {
    return new RetrievalEvaluationError("A failure annotation's category and source cannot be changed once created — only its status and notes.", "failure_content_immutable");
  }
  if (
    raw.includes("is already terminal") ||
    raw.includes("immutable") ||
    raw.includes("cannot be modified") ||
    raw.includes("cannot be deleted") ||
    raw.includes("a frozen dataset may only transition to archived") ||
    raw.includes("a frozen dataset cannot return to") ||
    raw.includes("an archived dataset is immutable")
  ) {
    return new RetrievalEvaluationError("This record cannot be changed.", "immutable");
  }
  if (raw.includes("invalid status") || raw.includes("invalid review_status") || raw.includes("violates check constraint")) {
    return new RetrievalEvaluationError("One of the provided values is not valid.", "invalid_value");
  }
  if (raw.includes("duplicate key value violates unique constraint")) {
    return new RetrievalEvaluationError("A dataset with this logical name and version already exists.", "duplicate");
  }
  if (raw.includes("logical_name is required") || raw.includes("title is required") || raw.includes("query_text is required")) {
    return new RetrievalEvaluationError("A required field is missing.", "required_field_missing");
  }
  if (raw.includes("not found")) {
    return new RetrievalEvaluationError("The requested item could not be found.", "not_found");
  }

  return new RetrievalEvaluationError("The action could not be completed. Please try again.", "unknown");
}
