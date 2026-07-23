import { PermissionDeniedPanel } from "@noor/ui";

export default function AccessDeniedPage() {
  return (
    <main className="mx-auto max-w-lg p-xl">
      <PermissionDeniedPanel
        title="No active organization membership"
        description="Your account doesn't currently have an active membership in any Noor organization. This can happen if your membership was suspended or removed, or if your profile hasn't been provisioned yet. Contact your organization administrator to request access."
      />
    </main>
  );
}
