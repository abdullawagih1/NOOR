import { ForgotPasswordForm } from "./ForgotPasswordForm";
import { Card, PageHeader } from "@noor/ui";

export default function ForgotPasswordPage({
  searchParams,
}: {
  searchParams: { error?: string; sent?: string };
}) {
  return (
    <main className="mx-auto flex max-w-md flex-col gap-lg p-xl">
      <PageHeader title="Reset your password" description="Enter the email address on your Noor account." />
      <Card>
        <ForgotPasswordForm error={searchParams.error} sent={searchParams.sent === "1"} />
      </Card>
      <a href="/login" className="text-center text-sm text-primary hover:underline">
        Back to sign in
      </a>
    </main>
  );
}
