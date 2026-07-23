import { PermissionDeniedPanel } from "@noor/ui";

export default function ForbiddenPage() {
  return (
    <main className="mx-auto max-w-lg p-xl">
      <PermissionDeniedPanel
        title="You don't have access to this workspace"
        description="Your account is signed in, but your current role doesn't include this permission. Contact your organization administrator if you believe this is incorrect."
      />
    </main>
  );
}
