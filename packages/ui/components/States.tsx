import { AlertOctagon, Inbox, Loader2 } from "lucide-react";
import { cn } from "../src/cn";

export function EmptyState({
  title,
  description,
  action,
  className,
}: {
  title: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col items-center gap-sm rounded-md border border-dashed border-border p-xxl text-center", className)}>
      <Inbox size={28} className="text-muted" aria-hidden="true" />
      <p className="text-base font-semibold text-ink">{title}</p>
      {description ? <p className="max-w-sm text-sm text-muted">{description}</p> : null}
      {action}
    </div>
  );
}

export function ErrorState({
  title = "Something went wrong",
  description,
  action,
  className,
}: {
  title?: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      role="alert"
      className={cn(
        "flex flex-col items-center gap-sm rounded-md border p-xxl text-center",
        className
      )}
      style={{
        color: "var(--noor-state-critical-fg)",
        backgroundColor: "var(--noor-state-critical-bg)",
        borderColor: "var(--noor-state-critical-border)",
      }}
    >
      <AlertOctagon size={28} aria-hidden="true" />
      <p className="text-base font-semibold">{title}</p>
      {description ? <p className="max-w-sm text-sm">{description}</p> : null}
      {action}
    </div>
  );
}

export function LoadingState({ label = "Loading…" }: { label?: string }) {
  return (
    <div role="status" className="flex items-center gap-sm text-sm text-muted">
      <Loader2 size={18} className="animate-spin" aria-hidden="true" />
      <span>{label}</span>
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("animate-pulse rounded-sm bg-surface-strong", className)} aria-hidden="true" />;
}
