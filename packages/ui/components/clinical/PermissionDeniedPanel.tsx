import { ShieldAlert } from "lucide-react";

export interface PermissionDeniedPanelProps {
  title: string;
  description: string;
  action?: React.ReactNode;
}

/** Shared shell for /403 and /access-denied — a controlled state, never an unhandled error. */
export function PermissionDeniedPanel({ title, description, action }: PermissionDeniedPanelProps) {
  return (
    <div className="flex flex-col items-center gap-md rounded-lg border border-border bg-surface-soft p-xxl text-center">
      <ShieldAlert size={32} className="text-muted" aria-hidden="true" />
      <div className="flex flex-col gap-xxs">
        <h1 className="text-xl font-semibold text-ink">{title}</h1>
        <p className="max-w-md text-sm text-muted">{description}</p>
      </div>
      {action}
    </div>
  );
}
