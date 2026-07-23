export default function QualityPage() {
  return (
    <main className="noor-shell">
      <span className="noor-badge">Sprint 0 — content stub, real auth</span>
      <h1>Quality & Safety Workspace</h1>
      <p>Monitor unsupported claims, citation mismatches, and safety incidents.</p>
      <div className="noor-card">
        <strong>Requires workspace.quality.access</strong>
        <p>Granted to quality_manager, safety_officer</p>
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
