import { LoginForm } from "./LoginForm";
import { AuthSplitShell } from "../AuthShell";
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
    <AuthSplitShell>
      <div className="flex flex-col gap-lg">
        <div className="flex flex-col gap-xxs">
          <h1 className="text-2xl font-semibold text-ink">Sign in to NOOR</h1>
          <p className="text-sm text-muted">Access your organization&apos;s clinical intelligence workspace.</p>
        </div>
        {params.notice ? <Alert tone="success" title={params.notice} /> : null}
        <Card>
          <LoginForm next={next} error={params.error} />
        </Card>
        <p className="text-center text-xs text-muted">
          NOOR currently uses organization-provisioned access. Contact your organization
          administrator if you need an account.
        </p>
      </div>
    </AuthSplitShell>
  );
}
