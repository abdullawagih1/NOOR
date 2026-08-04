import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { PermissionKey } from "@/lib/auth/permissions";
import type { PostLoginAccess } from "@/lib/auth/redirect";

export type AuthenticatedContext = {
  userId: string;
  profileId: string;
  organizationId: string;
  membershipId: string;
  roleKeys: string[];
  permissionKeys: string[];
};

type ResolvedAccess =
  | { kind: "unauthenticated" }
  | { kind: "no_profile"; userId: string }
  | { kind: "no_active_membership"; userId: string }
  | { kind: "authorized"; context: AuthenticatedContext };

interface RolePermissionRow {
  permissions: { key: string } | { key: string }[] | null;
}

interface RoleRow {
  key: string;
  role_permissions: RolePermissionRow[] | null;
}

interface MembershipRow {
  id: string;
  organization_id: string;
  status: string;
  created_at: string;
  roles: RoleRow | RoleRow[] | null;
}

function firstOrSelf<T>(value: T | T[] | null | undefined): T | null {
  if (!value) return null;
  return Array.isArray(value) ? value[0] ?? null : value;
}

/**
 * Resolves the caller's identity, profile, and active-organization
 * membership from the database — never from client-supplied identifiers or
 * editable user metadata (Master Prompt §11). Runs under the request's own
 * session (RLS applies), consistent with ADR 0003.
 *
 * Sprint 0 scope: a user with multiple active memberships resolves to the
 * earliest-created one. Organization switching is Sprint 1+ scope.
 */
export async function getAuthenticatedContext(): Promise<ResolvedAccess> {
  const supabase = await createClient();

  // LX-1.2 perf pass: `getSession()` only decodes the JWT already
  // present in cookies (no network round trip); `getUser()` always
  // revalidates against the Auth server (a real network call, by
  // design — never trusted for the actual authorization decision
  // below). For the overwhelmingly common case on a PUBLIC route —
  // an anonymous visitor with no session cookie at all — skipping
  // straight to the free local check avoids paying that network
  // latency just to learn "no session," which was a measured,
  // real contributor to a mobile Lighthouse LCP regression on "/"
  // once it started resolving an auth-aware CTA on every request.
  // Every actually-authenticated request still goes through the
  // unchanged, network-validated getUser() call below — this only
  // short-circuits the anonymous path.
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) {
    return { kind: "unauthenticated" };
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return { kind: "unauthenticated" };
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", user.id)
    .maybeSingle();

  if (!profile) {
    return { kind: "no_profile", userId: user.id };
  }

  const { data: memberships } = await supabase
    .from("organization_memberships")
    .select(
      "id, organization_id, status, created_at, roles(key, role_permissions(permissions(key)))"
    )
    .eq("user_id", user.id)
    .eq("status", "active")
    .order("created_at", { ascending: true });

  const rows = (memberships ?? []) as unknown as MembershipRow[];

  if (rows.length === 0) {
    return { kind: "no_active_membership", userId: user.id };
  }

  const membership = rows[0];
  const role = firstOrSelf(membership.roles);
  const permissionKeys = new Set<string>();
  const roleKeys = new Set<string>();

  if (role) {
    roleKeys.add(role.key);
    for (const rp of role.role_permissions ?? []) {
      const permission = firstOrSelf(rp.permissions);
      if (permission) permissionKeys.add(permission.key);
    }
  }

  return {
    kind: "authorized",
    context: {
      userId: user.id,
      profileId: profile.id,
      organizationId: membership.organization_id,
      membershipId: membership.id,
      roleKeys: Array.from(roleKeys),
      permissionKeys: Array.from(permissionKeys),
    },
  };
}

/**
 * Requires an authenticated user with an active organization membership.
 * Redirects to a controlled page rather than throwing on every denial path
 * — unauthenticated goes to /login, everything else that isn't a clean
 * "authorized" result goes to /access-denied.
 */
export async function requireActiveMembership(): Promise<AuthenticatedContext> {
  const result = await getAuthenticatedContext();

  if (result.kind === "unauthenticated") {
    redirect("/login");
  }
  if (result.kind !== "authorized") {
    redirect("/access-denied");
  }

  return result.context;
}

export async function requirePermission(permission: PermissionKey): Promise<AuthenticatedContext> {
  const context = await requireActiveMembership();
  if (!context.permissionKeys.includes(permission)) {
    redirect("/403");
  }
  return context;
}

export async function requireRole(roleKey: string): Promise<AuthenticatedContext> {
  const context = await requireActiveMembership();
  if (!context.roleKeys.includes(roleKey)) {
    redirect("/403");
  }
  return context;
}

/**
 * Adapts a `ResolvedAccess` result to the flat, structural shape
 * `resolvePostLoginDestination()` needs — kept as a separate function
 * (not inlined at each call site) so the 3 real call sites (password
 * sign-in, the auth callback route, and the login page's
 * already-authenticated short-circuit) can't drift from each other.
 */
export function toPostLoginAccess(result: ResolvedAccess): PostLoginAccess {
  return {
    kind: result.kind,
    permissionKeys: result.kind === "authorized" ? result.context.permissionKeys : undefined,
  };
}
