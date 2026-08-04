import { redirect } from "next/navigation";
import { LoginForm } from "./LoginForm";
import { AuthSplitShell } from "../AuthShell";
import { sanitizeNextPath, resolvePostLoginDestination } from "@/lib/auth/redirect";
import { getAuthenticatedContext, toPostLoginAccess } from "@/lib/auth/context";
import { Card, Alert } from "@noor/ui";

// Session-dependent (cookies) — must never be statically prerendered.
export const dynamic = "force-dynamic";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string; notice?: string }>;
}) {
  const params = await searchParams;
  const next = sanitizeNextPath(params.next);

  // LX-1.2 mission §24: an already-authenticated visitor who lands on
  // /login (e.g. a bookmarked link, or clicking "Sign in" again)
  // should never see the credentials form — they already have a
  // session, so send them straight to their resolved destination. A
  // caller with an active `error`/`notice` query param (e.g. mid
  // password-reset) is not skipped, since those states are only ever
  // reached without a session in the first place.
  if (!params.error && !params.notice) {
    const access = await getAuthenticatedContext();
    if (access.kind !== "unauthenticated") {
      redirect(resolvePostLoginDestination(next, toPostLoginAccess(access)));
    }
  }

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
