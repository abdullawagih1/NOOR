/**
 * Restricts a caller-supplied "next" path to a same-origin, relative path.
 * Rejects absolute URLs and protocol-relative ("//host") strings, which are
 * the two shapes used for open-redirect attacks against a login flow.
 */
export function sanitizeNextPath(next: string | null | undefined): string {
  if (!next) return "/";
  if (!next.startsWith("/")) return "/";
  if (next.startsWith("//")) return "/";
  if (next.includes("://")) return "/";
  return next;
}
