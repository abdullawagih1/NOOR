import { UpdatePasswordForm } from "./UpdatePasswordForm";
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
    <main className="mx-auto flex max-w-md flex-col gap-lg p-xl">
      <PageHeader title="Choose a new password" description="This completes your password reset." />
      <Card>
        <UpdatePasswordForm error={params.error} />
      </Card>
    </main>
  );
}
