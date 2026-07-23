import { Alert } from "../Alert";

export interface ClinicalWarningPanelProps {
  title: string;
  children: React.ReactNode;
  severity?: "warning" | "critical";
}

/**
 * A named, higher-stakes wrapper around Alert for clinical-safety messaging
 * (e.g. "requires_clinician_review", contraindication flags). Kept as its
 * own component rather than reusing Alert directly at call sites so every
 * clinical warning surface can be found/audited in one place later.
 */
export function ClinicalWarningPanel({ title, children, severity = "warning" }: ClinicalWarningPanelProps) {
  return (
    <Alert tone={severity} title={title}>
      {children}
    </Alert>
  );
}
