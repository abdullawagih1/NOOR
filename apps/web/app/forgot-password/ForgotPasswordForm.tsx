"use client";

import { useFormStatus } from "react-dom";
import { requestPasswordReset } from "@/lib/auth/actions";
import { Button, TextInput, Alert } from "@noor/ui";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending} className="w-full">
      {pending ? "Sending…" : "Send reset link"}
    </Button>
  );
}

export function ForgotPasswordForm({ error, sent }: { error?: string; sent?: boolean }) {
  if (sent) {
    return (
      <Alert tone="success" title="Check your email">
        If an account exists for that address, we&apos;ve sent a password reset link. It expires shortly, so use it soon.
      </Alert>
    );
  }

  return (
    <form action={requestPasswordReset} className="flex flex-col gap-md">
      <TextInput label="Email" id="email" name="email" type="email" autoComplete="email" required />
      {error ? <Alert tone="critical" title={error} /> : null}
      <SubmitButton />
    </form>
  );
}
