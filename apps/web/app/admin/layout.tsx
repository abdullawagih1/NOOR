import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { WorkspaceHeader } from "@/app/WorkspaceHeader";

// Session-dependent (cookies) — must never be statically prerendered.
export const dynamic = "force-dynamic";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const context = await requirePermission(PERMISSIONS.WORKSPACE_ADMIN_ACCESS);

  return (
    <div className="mx-auto max-w-4xl p-xl">
      <WorkspaceHeader roleKeys={context.roleKeys} permissionKeys={context.permissionKeys} />
      {children}
    </div>
  );
}
