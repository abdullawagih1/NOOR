import { PERMISSIONS, type PermissionKey } from "@/lib/auth/permissions";

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

/**
 * The 4 permission-gated workspace roots (LX-1.2 mission §23), in the
 * priority order used to pick a default workspace when the caller
 * didn't request a specific path. Order only matters in the
 * (currently impossible, but not structurally prevented) case where a
 * single membership's role carried more than one workspace-access
 * permission — today every seeded role maps to exactly one.
 */
const WORKSPACE_ROUTES: ReadonlyArray<{ prefix: string; permission: PermissionKey }> = [
  { prefix: "/admin", permission: PERMISSIONS.WORKSPACE_ADMIN_ACCESS },
  { prefix: "/quality", permission: PERMISSIONS.WORKSPACE_QUALITY_ACCESS },
  { prefix: "/reviewer", permission: PERMISSIONS.WORKSPACE_REVIEWER_ACCESS },
  { prefix: "/clinician", permission: PERMISSIONS.WORKSPACE_CLINICIAN_ACCESS },
];

/**
 * The caller's default workspace root, or null if their permission set
 * doesn't include any of the 4 workspace-access permissions (e.g. a
 * membership whose role only grants `/knowledge`-style permissions —
 * see NOOR_CINEMATIC_AUTH_INTEGRATION.md for why that resolves to
 * /access-denied post-login rather than silently picking a workspace
 * the caller can't open).
 */
export function resolveDefaultWorkspacePath(permissionKeys: readonly string[]): string | null {
  const match = WORKSPACE_ROUTES.find((route) => permissionKeys.includes(route.permission));
  return match ? match.prefix : null;
}

/** The workspace route `path` targets, or null if it isn't one of the
 * 4 gated roots at all (e.g. `/update-password`, `/knowledge/...`). */
function matchWorkspaceRoute(path: string): { prefix: string; permission: PermissionKey } | null {
  return WORKSPACE_ROUTES.find((route) => path === route.prefix || path.startsWith(`${route.prefix}/`)) ?? null;
}

/**
 * The minimal shape `resolvePostLoginDestination` needs from
 * `getAuthenticatedContext()`'s result — kept structural (not imported
 * from lib/auth/context.ts) so this module has no dependency on the
 * Supabase-backed resolver and stays trivially unit-testable.
 */
export interface PostLoginAccess {
  readonly kind: "unauthenticated" | "no_profile" | "no_active_membership" | "authorized";
  readonly permissionKeys?: readonly string[];
}

/**
 * The single canonical post-login/post-visit redirect decision (LX-1.2
 * mission §23) — replaces the previous behavior of redirecting a
 * successful sign-in straight to whatever "next" defaulted to (which
 * defaulted to "/", the reported defect: a successful login bounced
 * the user back to the public landing page instead of their
 * workspace).
 *
 * Priority order (mission §23):
 *   1. A safe, same-origin `requestedPath` the caller is authorized to
 *      open. Skipped entirely when it's empty/missing/exactly "/" —
 *      that's "no specific request", not a request for the landing
 *      page. A requested path that isn't one of the 4 permission-
 *      gated workspace roots (e.g. `/update-password`, a
 *      `/knowledge/...` deep link) is honored regardless of
 *      membership/permission state — its own layout enforces whatever
 *      it needs on arrival, exactly as it does today; this function
 *      only pre-checks the 4 roots it can authoritatively resolve,
 *      so single-purpose flows like password reset are never routed
 *      into an access-denied dead end just because membership
 *      resolution is irrelevant to them.
 *   2. The caller's authorized default workspace, resolved from their
 *      active membership's permission set.
 *   3. `/access-denied` — no active membership, no profile, or (for a
 *      request with no specific path) a membership whose role grants
 *      no workspace-access permission at all.
 *
 * Never returns "/" — an authenticated caller with a real destination
 * is never sent back to the public landing page by this function.
 */
export function resolvePostLoginDestination(
  requestedPath: string | null | undefined,
  access: PostLoginAccess
): string {
  const permissionKeys = access.kind === "authorized" ? access.permissionKeys ?? [] : [];
  const safeNext = sanitizeNextPath(requestedPath);

  if (safeNext !== "/") {
    const gated = matchWorkspaceRoute(safeNext);
    if (!gated || permissionKeys.includes(gated.permission)) {
      return safeNext;
    }
    // Requested a workspace root the caller isn't authorized for —
    // fall through to their own default workspace instead of denying
    // outright, mirroring requirePermission()'s existing "redirect
    // somewhere safe, don't just 403 a redirect" posture.
  }

  if (access.kind === "authorized") {
    const defaultWorkspace = resolveDefaultWorkspacePath(permissionKeys);
    if (defaultWorkspace) return defaultWorkspace;
  }

  return "/access-denied";
}
