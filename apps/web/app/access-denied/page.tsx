export default function AccessDeniedPage() {
  return (
    <main className="noor-shell">
      <span className="noor-badge">Access denied</span>
      <h1>No active organization membership</h1>
      <p>
        Your account doesn&apos;t currently have an active membership in any
        Noor organization. This can happen if your membership was suspended
        or removed, or if your profile hasn&apos;t been provisioned yet.
        Contact your organization administrator to request access.
      </p>
    </main>
  );
}
