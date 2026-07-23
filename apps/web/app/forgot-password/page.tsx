import { ForgotPasswordForm } from "./ForgotPasswordForm";
import { Card, PageHeader } from "@noor/ui";

export default async function ForgotPasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; sent?: string }>;
}) {
  const params = await searchParams;
  return (
    <main className="mx-auto flex max-w-md flex-col gap-lg p-xl">
      <PageHeader title="Reset your password" description="Enter the email address on your Noor account." />
      <Card>
        <ForgotPasswordForm error={params.error} sent={params.sent === "1"} />
      </Card>
      <a href="/login" className="text-center text-sm text-primary hover:underline">
        Back to sign in
      </a>
    </main>
  );
}
