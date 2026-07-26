/**
 * Typed error surface for the guideline registry application layer.
 * Wraps PostgREST/Postgres error shapes (returned by supabase.rpc calls)
 * into a stable, safe-to-display message — never leaks raw SQL error text
 * (which can include internal identifiers) to the client beyond what these
 * known cases produce.
 */
export class GuidelineRegistryError extends Error {
  readonly code: string;

  constructor(message: string, code = "guideline_registry_error") {
    super(message);
    this.name = "GuidelineRegistryError";
    this.code = code;
  }
}

interface PostgrestErrorLike {
  code?: string;
  message?: string;
}

/**
 * Maps a Postgres/PostgREST error (from a failed `supabase.rpc(...)` call)
 * to a GuidelineRegistryError with a safe, specific message where the
 * underlying cause is well-known, falling back to a generic message
 * otherwise. The database is always the authoritative source of these
 * rules (migration 0005) — this only makes the failure legible to a caller.
 */
export function toGuidelineRegistryError(error: PostgrestErrorLike): GuidelineRegistryError {
  const raw = error.message ?? "";

  if (error.code === "42501" || raw.includes("permission denied")) {
    return new GuidelineRegistryError("You do not have permission to perform this action.", "permission_denied");
  }
  if (error.code === "23505" || raw.includes("duplicate key")) {
    return new GuidelineRegistryError("That code or label is already in use.", "duplicate");
  }
  if (raw.includes("illegal lifecycle transition")) {
    return new GuidelineRegistryError("That status change is not allowed from the current state.", "illegal_transition");
  }
  if (raw.includes("approval requires at least one review")) {
    return new GuidelineRegistryError("This version needs a review recommending approval before it can be approved.", "review_required");
  }
  if (raw.includes("self-approval is not permitted") || raw.includes("cannot be reviewed by its own creator")) {
    return new GuidelineRegistryError("You cannot review or approve a version you authored.", "self_action_blocked");
  }
  if (raw.includes("reason is required") || raw.includes("withdrawal reason is required")) {
    return new GuidelineRegistryError("A reason is required for this action.", "reason_required");
  }
  if (raw.includes("not found")) {
    return new GuidelineRegistryError("The requested item could not be found.", "not_found");
  }
  if (error.code === "23514" || raw.includes("violates check constraint")) {
    return new GuidelineRegistryError("One of the provided values is not valid.", "invalid_value");
  }

  return new GuidelineRegistryError("The action could not be completed. Please try again.", "unknown");
}
