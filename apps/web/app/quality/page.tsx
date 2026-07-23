import { PageHeader, Badge, EmptyState } from "@noor/ui";

export default function QualityPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 0.5 — content stub, real auth"
        title="Quality & Safety Workspace"
        description="Monitor unsupported claims, citation mismatches, and safety incidents."
        actions={<Badge>Requires workspace.quality.access</Badge>}
      />
      <EmptyState
        title="No signals yet"
        description="Session resolution, active-membership checks, and permission enforcement are real — you could not have reached this page without them. Safety-signal monitoring is Sprint 1+ scope. Granted to quality_manager, safety_officer."
      />
    </main>
  );
}
