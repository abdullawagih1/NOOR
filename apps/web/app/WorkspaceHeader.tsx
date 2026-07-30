"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { signOut } from "@/lib/auth/actions";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { WorkspaceNav, Button, Badge, type WorkspaceNavItem } from "@noor/ui";

const NAV_DEFINITIONS = [
  { label: "Ask Noor", href: "/clinician", permission: PERMISSIONS.WORKSPACE_CLINICIAN_ACCESS },
  { label: "Clinical Knowledge", href: "/clinician/knowledge", permission: PERMISSIONS.GUIDELINES_READ_ACTIVE },
  { label: "Administration", href: "/admin", permission: PERMISSIONS.WORKSPACE_ADMIN_ACCESS },
  { label: "Guideline Registry", href: "/knowledge/guidelines", permission: PERMISSIONS.GUIDELINES_READ_ALL },
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
    <div className="mb-lg flex flex-col gap-md">
      <div className="flex items-center justify-between">
        <Link href="/" aria-label="Noor home" className="inline-flex items-center rounded-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent">
          <Image src="/brand/noor-logo-navigation.png" alt="Noor — Clinical Intelligence" width={121} height={100} className="h-10 w-auto sm:h-12" priority />
        </Link>
        <div className="flex items-center gap-sm">
          <Badge>{roleKeys.join(", ") || "member"}</Badge>
          <form action={signOut}>
            <Button type="submit" variant="secondary" size="sm">
              Sign out
            </Button>
          </form>
        </div>
      </div>
      <div className="flex flex-col gap-md border-b border-border pb-md sm:flex-row sm:items-center sm:justify-between">
        <WorkspaceNav items={items} />
      </div>
    </div>
  );
}
