import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { WorkspaceHeader } from "@/app/WorkspaceHeader";

// Session-dependent (cookies) — must never be statically prerendered.
export const dynamic = "force-dynamic";

export default async function QualityLayout({ children }: { children: React.ReactNode }) {
  const context = await requirePermission(PERMISSIONS.WORKSPACE_QUALITY_ACCESS);

  return (
    <>
      <WorkspaceHeader roleKeys={context.roleKeys} />
      {children}
    </>
  );
}
