import { LoginForm } from "./LoginForm";
import { sanitizeNextPath } from "@/lib/auth/redirect";
import { Card, PageHeader, Alert } from "@noor/ui";

export default function LoginPage({
  searchParams,
}: {
  searchParams: { next?: string; error?: string; notice?: string };
}) {
  const next = sanitizeNextPath(searchParams.next);

  return (
    <main className="mx-auto flex max-w-md flex-col gap-lg p-xl">
      <PageHeader eyebrow="Noor V1" title="Sign in" description="Access your organization's Noor workspace." />
      {searchParams.notice ? <Alert tone="success" title={searchParams.notice} /> : null}
      <Card>
        <LoginForm next={next} error={searchParams.error} />
      </Card>
      <p className="text-center text-xs text-muted">
        Noor is invite-only during Controlled Beta — accounts are provisioned by your
        organization administrator, not self-service signup.
      </p>
    </main>
  );
}
