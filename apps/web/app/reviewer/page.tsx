import Link from "next/link";
import { PageHeader, Badge, EmptyState, Button } from "@noor/ui";

export default function ReviewerPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="Clinical Reviewer Workspace"
        description="Review submitted guideline versions and record review decisions."
        actions={<Badge>Requires workspace.reviewer.access</Badge>}
      />
      <EmptyState
        title="Guideline review queue is live"
        description="Real guideline versions awaiting clinical review — approve/reject decisions and safety concerns are recorded and audited. Extraction/document review (post-parsing) remains later Sprint 1 scope."
        action={
          <Link href="/reviewer/guidelines">
            <Button variant="secondary">Open Review Queue</Button>
          </Link>
        }
      />
    </main>
  );
}
