import { UpdatePasswordForm } from "./UpdatePasswordForm";
import { Card, PageHeader } from "@noor/ui";

// Session-dependent (the recovery session set by /auth/callback) — must
// never be statically prerendered.
export const dynamic = "force-dynamic";

export default function UpdatePasswordPage({
  searchParams,
}: {
  searchParams: { error?: string };
}) {
  return (
    <main className="mx-auto flex max-w-md flex-col gap-lg p-xl">
      <PageHeader title="Choose a new password" description="This completes your password reset." />
      <Card>
        <UpdatePasswordForm error={searchParams.error} />
      </Card>
    </main>
  );
}
