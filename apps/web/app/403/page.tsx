import Link from "next/link";
import { PermissionDeniedPanel, Button } from "@noor/ui";
import { AuthCardShell } from "../AuthShell";

export default function ForbiddenPage() {
  return (
    <AuthCardShell>
      <PermissionDeniedPanel
        title="You don't have access to this workspace"
        description="Your account is signed in, but your current role doesn't include this permission. Contact your organization administrator if you believe this is incorrect."
        action={
          <Link href="/">
            <Button variant="secondary">Return to home</Button>
          </Link>
        }
      />
    </AuthCardShell>
  );
}
