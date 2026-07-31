import Link from "next/link";
import { PermissionDeniedPanel, Button } from "@noor/ui";
import { AuthCardShell } from "../AuthShell";

export default function AccessDeniedPage() {
  return (
    <AuthCardShell>
      <PermissionDeniedPanel
        title="No active organization membership"
        description="Your account doesn't currently have an active membership in any Noor organization. This can happen if your membership was suspended or removed, or if your profile hasn't been provisioned yet. Contact your organization administrator to request access."
        action={
          <Link href="/">
            <Button variant="secondary">Return to home</Button>
          </Link>
        }
      />
    </AuthCardShell>
  );
}
