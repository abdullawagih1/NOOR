"use client";

import { useFormStatus } from "react-dom";
import { signInWithPassword } from "@/lib/auth/actions";
import { Button, TextInput, PasswordInput, Alert } from "@noor/ui";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending} className="w-full">
      {pending ? "Signing in…" : "Sign in"}
    </Button>
  );
}

export function LoginForm({ next, error }: { next: string; error?: string }) {
  return (
    <form action={signInWithPassword} className="flex flex-col gap-md">
      <input type="hidden" name="next" value={next} />
      <TextInput label="Email" id="email" name="email" type="email" autoComplete="email" required />
      <PasswordInput label="Password" id="password" name="password" autoComplete="current-password" required />

      {error ? (
        <Alert tone="critical" title={error} />
      ) : null}

      <SubmitButton />

      <a href="/forgot-password" className="text-sm text-primary hover:underline">
        Forgot your password?
      </a>
    </form>
  );
}
