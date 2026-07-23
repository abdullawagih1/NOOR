"use client";

import { usePathname } from "next/navigation";
import { signOut } from "@/lib/auth/actions";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { WorkspaceNav, Button, Badge, type WorkspaceNavItem } from "@noor/ui";

const NAV_DEFINITIONS = [
  { label: "Ask Noor", href: "/clinician", permission: PERMISSIONS.WORKSPACE_CLINICIAN_ACCESS },
  { label: "Administration", href: "/admin", permission: PERMISSIONS.WORKSPACE_ADMIN_ACCESS },
  { label: "Review", href: "/reviewer", permission: PERMISSIONS.WORKSPACE_REVIEWER_ACCESS },
  { label: "Quality", href: "/quality", permission: PERMISSIONS.WORKSPACE_QUALITY_ACCESS },
] as const;

export function WorkspaceHeader({ roleKeys, permissionKeys }: { roleKeys: string[]; permissionKeys: string[] }) {
  const pathname = usePathname();

  // Nav items are derived from the signed-in user's actual permissions, not
  // from which route happens to be rendering this header.
  const items: WorkspaceNavItem[] = NAV_DEFINITIONS.filter((item) => permissionKeys.includes(item.permission)).map(
    (item) => ({ label: item.label, href: item.href, active: pathname?.startsWith(item.href) })
  );

  return (
    <div className="mb-lg flex flex-col gap-md border-b border-border pb-md sm:flex-row sm:items-center sm:justify-between">
      <WorkspaceNav items={items} />
      <div className="flex items-center gap-sm">
        <Badge>{roleKeys.join(", ") || "member"}</Badge>
        <form action={signOut}>
          <Button type="submit" variant="secondary" size="sm">
            Sign out
          </Button>
        </form>
      </div>
    </div>
  );
}
