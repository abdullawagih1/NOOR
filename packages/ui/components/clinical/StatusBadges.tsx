import { SemanticStatusBadge } from "../Badge";
import type { SemanticStateKey } from "../../tokens";

export type EvidenceStatus = "evidenceSufficient" | "evidencePartial" | "evidenceInsufficient" | "evidenceConflicting";
export type GuidelineStatus = "verified" | "inactive" | "superseded" | "withdrawn" | "underReview" | "processing";

export function EvidenceStatusBadge({ status }: { status: EvidenceStatus }) {
  return <SemanticStatusBadge state={status} />;
}

export function GuidelineStatusBadge({ status }: { status: GuidelineStatus }) {
  return <SemanticStatusBadge state={status} />;
}

/** Always rendered wherever generated content appears — never omitted, never combined visually with HumanApprovedLabel. */
export function AIGeneratedLabel({ className }: { className?: string }) {
  return <SemanticStatusBadge state={"aiGenerated" satisfies SemanticStateKey} className={className} />;
}

export function HumanApprovedLabel({ reviewerName, className }: { reviewerName?: string; className?: string }) {
  return (
    <SemanticStatusBadge
      state={"humanApproved" satisfies SemanticStateKey}
      labelOverride={reviewerName ? `Approved by ${reviewerName}` : undefined}
      className={className}
    />
  );
}
