import { LoginForm } from "./LoginForm";
import { sanitizeNextPath } from "@/lib/auth/redirect";
import { Card, PageHeader, Alert } from "@noor/ui";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string; notice?: string }>;
}) {
  const params = await searchParams;
  const next = sanitizeNextPath(params.next);

  return (
    <main className="mx-auto flex max-w-md flex-col gap-lg p-xl">
      <PageHeader eyebrow="Noor V1" title="Sign in" description="Access your organization's Noor workspace." />
      {params.notice ? <Alert tone="success" title={params.notice} /> : null}
      <Card>
        <LoginForm next={next} error={params.error} />
      </Card>
      <p className="text-center text-xs text-muted">
        Noor is invite-only during Controlled Beta — accounts are provisioned by your
        organization administrator, not self-service signup.
      </p>
    </main>
  );
}
