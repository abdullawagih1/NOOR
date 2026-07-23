import { AlertTriangle, AlertOctagon, Info, CheckCircle2, type LucideIcon } from "lucide-react";
import { cn } from "../src/cn";

export type AlertTone = "info" | "warning" | "critical" | "success";

const toneStyles: Record<AlertTone, { vars: React.CSSProperties; icon: LucideIcon }> = {
  info: { vars: { color: "var(--noor-state-informational-fg)", backgroundColor: "var(--noor-state-informational-bg)", borderColor: "var(--noor-state-informational-border)" }, icon: Info },
  warning: { vars: { color: "var(--noor-state-warning-fg)", backgroundColor: "var(--noor-state-warning-bg)", borderColor: "var(--noor-state-warning-border)" }, icon: AlertTriangle },
  critical: { vars: { color: "var(--noor-state-critical-fg)", backgroundColor: "var(--noor-state-critical-bg)", borderColor: "var(--noor-state-critical-border)" }, icon: AlertOctagon },
  success: { vars: { color: "var(--noor-state-verified-fg)", backgroundColor: "var(--noor-state-verified-bg)", borderColor: "var(--noor-state-verified-border)" }, icon: CheckCircle2 },
};

export interface AlertProps {
  tone?: AlertTone;
  title: string;
  children?: React.ReactNode;
  className?: string;
}

export function Alert({ tone = "info", title, children, className }: AlertProps) {
  const { vars, icon: Icon } = toneStyles[tone];
  return (
    <div
      role={tone === "critical" || tone === "warning" ? "alert" : "status"}
      className={cn("flex gap-sm rounded-md border p-md", className)}
      style={vars}
    >
      <Icon size={20} className="mt-0.5 shrink-0" aria-hidden="true" />
      <div className="flex flex-col gap-xxs">
        <p className="text-sm font-semibold">{title}</p>
        {children ? <div className="text-sm">{children}</div> : null}
      </div>
    </div>
  );
}
