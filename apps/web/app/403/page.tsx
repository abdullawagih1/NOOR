export default function ForbiddenPage() {
  return (
    <main className="noor-shell">
      <span className="noor-badge">403</span>
      <h1>You don&apos;t have access to this workspace</h1>
      <p>
        Your account is signed in, but your current role doesn&apos;t include
        this permission. Contact your organization administrator if you
        believe this is incorrect.
      </p>
    </main>
  );
}
