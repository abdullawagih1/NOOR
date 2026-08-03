export class EmbeddingError extends Error {
  readonly code: string;

  constructor(message: string, code = "embedding_error") {
    super(message);
    this.name = "EmbeddingError";
    this.code = code;
  }
}

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

/**
 * Maps a Postgres/PostgREST error from an embedding RPC call to a safe,
 * specific message where the cause is well-known — mirrors
 * apps/web/lib/retrieval-evaluation/errors.ts's toRetrievalEvaluationError
 * one layer over (migration 0016, ADR 0016).
 */
export function toEmbeddingError(error: PostgrestErrorLike): EmbeddingError {
  const raw = error.message ?? "";

  if (error.code === "42501" || raw.includes("permission denied") || raw.includes("authentication required")) {
    return new EmbeddingError("You do not have permission to perform this action.", "permission_denied");
  }
  if (raw.includes("embedding_input_not_ready")) {
    return new EmbeddingError("This document does not have a succeeded, accepted chunking run yet — it is not ready for embedding.", "embedding_input_not_ready");
  }
  if (raw.includes("embedding_configuration_not_approved")) {
    return new EmbeddingError("No approved embedding configuration exists. Contact an administrator.", "embedding_configuration_not_approved");
  }
  if (raw.includes("cancelling an embedding run requires a reason") || raw.includes("requires a reason")) {
    return new EmbeddingError("A reason is required.", "reason_required");
  }
  if (raw.includes("only a created, queued, or processing embedding run can be cancelled")) {
    return new EmbeddingError("Only a created, queued, or processing embedding run can be cancelled.", "not_cancellable");
  }
  if (raw.includes("is already terminal") || raw.includes("is immutable once succeeded") || raw.includes("cannot be modified")) {
    return new EmbeddingError("This record cannot be changed.", "immutable");
  }
  if (raw.includes("invalidating an embedding run requires") || raw.includes("invalidating a chunk embedding requires")) {
    return new EmbeddingError("Invalidating this record requires a reason.", "invalidation_reason_required");
  }
  if (raw.includes("embedding_vector_checksum_failed")) {
    return new EmbeddingError("A conflicting vector was recorded for this identity — this record cannot be trusted and must be re-generated.", "vector_checksum_conflict");
  }
  if (raw.includes("embedding_vector_empty")) {
    return new EmbeddingError("No vector was produced for this item.", "vector_empty");
  }
  if (raw.includes("embedding_dimension_mismatch")) {
    return new EmbeddingError("The produced vector does not match the approved configuration's dimension.", "vector_dimension_mismatch");
  }
  if (raw.includes("embedding_coverage_incomplete")) {
    return new EmbeddingError("Not every chunk in this run has a succeeded embedding yet.", "embedding_coverage_incomplete");
  }
  if (raw.includes("not found")) {
    return new EmbeddingError("The requested item could not be found.", "not_found");
  }

  return new EmbeddingError("The action could not be completed. Please try again.", "unknown");
}
