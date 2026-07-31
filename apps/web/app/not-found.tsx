import Link from "next/link";
import { Button } from "@noor/ui";
import { AuthCardShell } from "./AuthShell";

export default function NotFound() {
  return (
    <AuthCardShell>
      <div className="flex flex-col items-center gap-md rounded-lg border border-border bg-canvas p-xxl text-center">
        <h1 className="text-xl font-semibold text-ink">Page not found</h1>
        <p className="max-w-md text-sm text-muted">
          The page you&apos;re looking for doesn&apos;t exist, or has moved.
        </p>
        <Link href="/">
          <Button variant="secondary">Return to home</Button>
        </Link>
      </div>
    </AuthCardShell>
  );
}
