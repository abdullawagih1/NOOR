import Link from "next/link";
import { PageHeader, EmptyState, Badge, Button } from "@noor/ui";

export default function AdminPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="Admin Workspace"
        description="Manage organization membership, roles, and the guideline registry."
        actions={<Badge>Requires workspace.admin.access</Badge>}
      />
      <EmptyState
        title="Guideline Registry is live"
        description="The controlled guideline registry (domains, authorities, guidelines, versions, review/approval/activation lifecycle) is real — see Guideline Registry in the top nav, or the link below. Organization-membership management is still Sprint 1+ scope."
        action={
          <Link href="/knowledge/guidelines">
            <Button variant="secondary">Open Guideline Registry</Button>
          </Link>
        }
      />
    </main>
  );
}
