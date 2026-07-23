import { Card } from "../Card";
import { EvidenceStatusBadge, type EvidenceStatus } from "./StatusBadges";

export interface EvidenceCardProps {
  status: EvidenceStatus;
  summary: string;
  guidelineTitle: string;
  guidelineVersion?: string;
  className?: string;
}

/** Mocked-data display shell only — no retrieval wiring (Sprint 1 scope). */
export function EvidenceCard({ status, summary, guidelineTitle, guidelineVersion, className }: EvidenceCardProps) {
  return (
    <Card className={className}>
      <div className="flex items-start justify-between gap-md">
        <div className="flex flex-col gap-xxs">
          <p className="text-sm font-semibold text-ink">{guidelineTitle}</p>
          {guidelineVersion ? <p className="text-xs text-muted">Version {guidelineVersion}</p> : null}
        </div>
        <EvidenceStatusBadge status={status} />
      </div>
      <p className="mt-sm text-sm text-body">{summary}</p>
    </Card>
  );
}
