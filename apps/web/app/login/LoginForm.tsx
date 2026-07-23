"use client";

import { useFormStatus } from "react-dom";
import { signInWithPassword } from "@/lib/auth/actions";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" className="noor-button" disabled={pending}>
      {pending ? "Signing in…" : "Sign in"}
    </button>
  );
}

export function LoginForm({ next, error }: { next: string; error?: string }) {
  return (
    <form action={signInWithPassword} className="noor-form">
      <input type="hidden" name="next" value={next} />
      <label htmlFor="email">Email</label>
      <input id="email" name="email" type="email" autoComplete="email" required />

      <label htmlFor="password">Password</label>
      <input id="password" name="password" type="password" autoComplete="current-password" required />

      {error ? (
        <p role="alert" className="noor-error">
          {error}
        </p>
      ) : null}

      <SubmitButton />
    </form>
  );
}
