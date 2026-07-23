import { AlertTriangle, AlertOctagon, CheckCircle2, Shuffle, UserCheck, Sparkles, Info, Ban, Archive, Loader2, Eye, XCircle, CircleDashed, type LucideIcon } from "lucide-react";
import { semanticStates, semanticStateVarRefs, type SemanticStateKey } from "../tokens";
import { cn } from "../src/cn";

/** Plain neutral tag — no clinical meaning attached. */
export function Badge({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-pill bg-surface-strong px-sm py-xxs text-xs font-medium text-body",
        className
      )}
    >
      {children}
    </span>
  );
}

const iconMap: Record<string, LucideIcon> = {
  "check-circle": CheckCircle2,
  "alert-triangle": AlertTriangle,
  "alert-octagon": AlertOctagon,
  shuffle: Shuffle,
  "user-check": UserCheck,
  sparkles: Sparkles,
  info: Info,
  ban: Ban,
  archive: Archive,
  loader: Loader2,
  eye: Eye,
  "x-circle": XCircle,
  "circle-dashed": CircleDashed,
};

export interface SemanticStatusBadgeProps {
  state: SemanticStateKey;
  /** Override the default label (e.g. a guideline-specific phrasing) — the accessible description never changes. */
  labelOverride?: string;
  className?: string;
}

/**
 * The single component every clinical status surface (evidence, guideline
 * lifecycle, AI/human provenance, processing) renders through. Color is
 * never the only signal: icon + text label are always present, and
 * `accessibleDescription` is exposed to assistive tech via `aria-label`
 * regardless of whether the visible label is overridden.
 */
export function SemanticStatusBadge({ state, labelOverride, className }: SemanticStatusBadgeProps) {
  const token = semanticStates[state];
  const Icon = iconMap[token.icon];
  const vars = semanticStateVarRefs(state);

  return (
    <span
      className={cn(
        "inline-flex items-center gap-xxs rounded-pill border px-sm py-xxs text-xs font-medium",
        token.icon === "loader" && "motion-safe:[&_svg]:animate-spin",
        className
      )}
      style={vars}
      aria-label={token.accessibleDescription}
      title={token.helperText ?? token.accessibleDescription}
    >
      <Icon size={14} aria-hidden="true" />
      {labelOverride ?? token.label}
    </span>
  );
}
