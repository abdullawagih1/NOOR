import { PageHeader, Badge, EmptyState } from "@noor/ui";

export default function ReviewerPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 0.5 — content stub, real auth"
        title="Clinical Reviewer Workspace"
        description="Review extracted guideline content and approve knowledge releases."
        actions={<Badge>Requires workspace.reviewer.access</Badge>}
      />
      <EmptyState
        title="Nothing pending review"
        description="Session resolution, active-membership checks, and permission enforcement are real — you could not have reached this page without them. Extraction review queues are Sprint 1 scope. Granted to clinical_reviewer."
      />
    </main>
  );
}
