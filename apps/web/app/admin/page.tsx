import { PageHeader, EmptyState, Badge } from "@noor/ui";

export default function AdminPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 0.5 — content stub, real auth"
        title="Admin Workspace"
        description="Manage organization membership, roles, and guideline registration."
        actions={<Badge>Requires workspace.admin.access</Badge>}
      />
      <EmptyState
        title="No content yet"
        description="Session resolution, active-membership checks, and permission enforcement are real — you could not have reached this page without them. Real data (membership management, guideline registration) is Sprint 1 scope (MASTER_BACKLOG.md, E-14/E-09/E-21). Granted to organization_admin, knowledge_manager."
      />
    </main>
  );
}
