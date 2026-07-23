"use client";

import { useFormStatus } from "react-dom";
import { updatePassword } from "@/lib/auth/actions";
import { Button, PasswordInput, Alert } from "@noor/ui";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending} className="w-full">
      {pending ? "Updating…" : "Update password"}
    </Button>
  );
}

export function UpdatePasswordForm({ error }: { error?: string }) {
  return (
    <form action={updatePassword} className="flex flex-col gap-md">
      <PasswordInput
        label="New password"
        id="password"
        name="password"
        autoComplete="new-password"
        minLength={8}
        hint="At least 8 characters."
        required
      />
      <PasswordInput
        label="Confirm new password"
        id="confirmPassword"
        name="confirmPassword"
        autoComplete="new-password"
        minLength={8}
        required
      />
      {error ? <Alert tone="critical" title={error} /> : null}
      <SubmitButton />
    </form>
  );
}
