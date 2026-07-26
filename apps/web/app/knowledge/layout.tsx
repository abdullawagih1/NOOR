import { requireActiveMembership } from "@/lib/auth/context";
import { WorkspaceHeader } from "@/app/WorkspaceHeader";

// Session-dependent (cookies) — must never be statically prerendered.
export const dynamic = "force-dynamic";

/**
 * Deliberately NOT nested under /admin: the guideline registry's mutating
 * actions are split across roles that don't all hold workspace.admin.access
 * (quality_manager holds guidelines.approve/activate/supersede/withdraw but
 * only workspace.quality.access — see migration 0005's role_permissions).
 * Every page under /knowledge gates itself with a specific
 * guidelines.* permission via requirePermission(); this layout only
 * resolves the session (requireActiveMembership) so /login and
 * /access-denied still work for unauthenticated or membership-less callers
 * before any page-specific check runs.
 */
export default async function KnowledgeLayout({ children }: { children: React.ReactNode }) {
  const context = await requireActiveMembership();

  return (
    <div className="mx-auto max-w-4xl p-xl">
      <WorkspaceHeader roleKeys={context.roleKeys} permissionKeys={context.permissionKeys} />
      {children}
    </div>
  );
}
