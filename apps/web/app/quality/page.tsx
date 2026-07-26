import Link from "next/link";
import { PageHeader, Badge, EmptyState, Button } from "@noor/ui";

export default function QualityPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="Quality & Safety Workspace"
        description="Approve, activate, supersede, and withdraw guideline versions. Monitor unsupported claims, citation mismatches, and safety incidents."
        actions={<Badge>Requires workspace.quality.access</Badge>}
      />
      <EmptyState
        title="Guideline approval and activation is live"
        description="Approve, activate, supersede, and withdraw actions are real, permissioned, and audited — see Guideline Registry in the top nav. Safety-signal monitoring beyond the guideline lifecycle is later Sprint 1+ scope. Granted to quality_manager, safety_officer."
        action={
          <Link href="/knowledge/guidelines">
            <Button variant="secondary">Open Guideline Registry</Button>
          </Link>
        }
      />
    </main>
  );
}
