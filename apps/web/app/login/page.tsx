import { LoginForm } from "./LoginForm";
import { sanitizeNextPath } from "@/lib/auth/redirect";

export default function LoginPage({
  searchParams,
}: {
  searchParams: { next?: string; error?: string };
}) {
  const next = sanitizeNextPath(searchParams.next);

  return (
    <main className="noor-shell">
      <span className="noor-badge">Noor V1</span>
      <h1>Sign in</h1>
      <p>Access your organization&apos;s Noor workspace.</p>
      <div className="noor-card">
        <LoginForm next={next} error={searchParams.error} />
      </div>
    </main>
  );
}
