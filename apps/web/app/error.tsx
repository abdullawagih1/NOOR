"use client";

import { Button } from "@noor/ui";
import { AuthCardShell } from "./AuthShell";

/**
 * Next.js App Router error boundary. `error.message`/`error.stack` are
 * never rendered — only Next's own opaque `digest` (safe to show as a
 * correlation reference; it carries no stack trace, database detail, or
 * internal path) — see mission §11: never expose stack traces, database
 * errors, storage paths, tokens, or internal permission keys.
 */
export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <AuthCardShell>
      <div className="flex flex-col items-center gap-md rounded-lg border border-[var(--noor-state-critical-border)] bg-canvas p-xxl text-center">
        <h1 className="text-xl font-semibold text-ink">Something went wrong</h1>
        <p className="max-w-md text-sm text-muted">
          An unexpected error occurred. Try again, and contact your organization administrator if
          this keeps happening.
        </p>
        {error.digest ? <p className="font-mono text-xs text-muted-soft">Reference: {error.digest}</p> : null}
        <Button variant="primary" onClick={() => reset()}>
          Try again
        </Button>
      </div>
    </AuthCardShell>
  );
}
