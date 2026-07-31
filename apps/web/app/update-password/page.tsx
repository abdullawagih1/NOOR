import { UpdatePasswordForm } from "./UpdatePasswordForm";
import { AuthCardShell } from "../AuthShell";
import { Card, PageHeader } from "@noor/ui";

// Session-dependent (the recovery session set by /auth/callback) — must
// never be statically prerendered.
export const dynamic = "force-dynamic";

export default async function UpdatePasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const params = await searchParams;
  return (
    <AuthCardShell>
      <div className="flex flex-col gap-lg">
        <PageHeader title="Choose a new password" description="This completes your password reset." />
        <Card>
          <UpdatePasswordForm error={params.error} />
        </Card>
      </div>
    </AuthCardShell>
  );
}
