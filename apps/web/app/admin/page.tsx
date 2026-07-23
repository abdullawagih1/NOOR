export default function AdminPage() {
  return (
    <main className="noor-shell">
      <span className="noor-badge">Sprint 0 — content stub, real auth</span>
      <h1>Admin Workspace</h1>
      <p>Manage organization membership, roles, and guideline registration.</p>
      <div className="noor-card">
        <strong>Requires workspace.admin.access</strong>
        <p>Granted to organization_admin, knowledge_manager</p>
        <p>
          Session resolution, active-membership checks, and permission
          enforcement are real (see apps/web/lib/auth/context.ts) — you could
          not have reached this page without them. The content below it is
          still a static placeholder; real data is Sprint 1 scope (see
          MASTER_BACKLOG.md, E-14/E-09/E-21).
        </p>
      </div>
    </main>
  );
}
