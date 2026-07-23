export default function HomePage() {
  return (
    <main className="noor-shell">
      <span className="noor-badge">Noor V1 — Sprint 0 Foundation</span>
      <h1>Noor — Clinical Intelligence OS</h1>
      <p>
        Evidence-grounded clinical evidence assistant. This build establishes
        the Sprint 0 application shell and role-based workspace routing; no
        clinical data or generation pipeline is wired yet.
      </p>
      <div className="noor-card">
        <strong>Workspaces (stubs)</strong>
        <ul>
          <li>
            <a href="/clinician">Clinician Workspace</a>
          </li>
          <li>
            <a href="/admin">Admin Workspace</a>
          </li>
          <li>
            <a href="/reviewer">Clinical Reviewer Workspace</a>
          </li>
          <li>
            <a href="/quality">Quality &amp; Safety Workspace</a>
          </li>
        </ul>
      </div>
    </main>
  );
}
