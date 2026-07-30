import Image from "next/image";
import { LoginForm } from "./LoginForm";
import { sanitizeNextPath } from "@/lib/auth/redirect";
import { Card, Alert } from "@noor/ui";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string; notice?: string }>;
}) {
  const params = await searchParams;
  const next = sanitizeNextPath(params.next);

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-lg p-xl">
      <div className="flex flex-col items-center gap-sm text-center">
        <Image
          src="/brand/noor-logo-primary.png"
          alt="Noor — Clinical Intelligence"
          width={226}
          height={200}
          className="h-32 w-auto sm:h-36"
          priority
        />
        <div className="h-1 w-16 rounded-pill bg-brand-gradient" aria-hidden="true" />
        <h1 className="text-xl font-semibold text-ink">Sign in</h1>
        <p className="text-sm text-muted">Access your organization&apos;s Noor workspace</p>
      </div>
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
