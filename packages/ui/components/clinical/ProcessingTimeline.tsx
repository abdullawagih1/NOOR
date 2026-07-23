import { Check, Loader2, Circle } from "lucide-react";
import { cn } from "../../src/cn";

export interface TimelineStep {
  label: string;
  state: "done" | "active" | "pending" | "failed";
  timestamp?: string;
}

export function ProcessingTimeline({ steps }: { steps: TimelineStep[] }) {
  return (
    <ol className="flex flex-col gap-md">
      {steps.map((step, index) => (
        <li key={`${step.label}-${index}`} className="flex items-start gap-sm">
          <span
            className={cn(
              "mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-pill",
              step.state === "done" && "bg-[var(--noor-state-verified-bg)] text-[var(--noor-state-verified-fg)]",
              step.state === "active" && "bg-[var(--noor-state-processing-bg)] text-[var(--noor-state-processing-fg)]",
              step.state === "failed" && "bg-[var(--noor-state-failed-bg)] text-[var(--noor-state-failed-fg)]",
              step.state === "pending" && "bg-surface-strong text-muted"
            )}
          >
            {step.state === "done" ? <Check size={14} aria-hidden="true" /> : null}
            {step.state === "active" ? <Loader2 size={14} className="animate-spin" aria-hidden="true" /> : null}
            {step.state === "pending" || step.state === "failed" ? <Circle size={10} aria-hidden="true" /> : null}
          </span>
          <div className="flex flex-col">
            <span className="text-sm font-medium text-ink">{step.label}</span>
            {step.timestamp ? <span className="text-xs text-muted">{step.timestamp}</span> : null}
          </div>
        </li>
      ))}
    </ol>
  );
}
