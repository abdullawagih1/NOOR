import { SemanticStatusBadge, type SemanticStateKey } from "@noor/ui";
import type { LifecycleStatus, ReviewStatus } from "@/lib/guidelines/schemas";

/**
 * Maps the 6 clinical publication states (+ the review-only "changes
 * requested" surface) onto the existing, accessibility-audited 16-state
 * design-system palette (packages/ui/tokens/colors.ts) via labelOverride —
 * no new tokens, no color-only signal (icon + explicit text always render).
 * "approved" reuses the `humanApproved` state and "active" reuses
 * `verified`, since neither of Noor's existing tokens is a literal 1:1
 * match and both accurately convey "clinically signed off"/"currently
 * trustworthy" respectively.
 */
const LIFECYCLE_STATUS_DISPLAY: Record<LifecycleStatus, { state: SemanticStateKey; label: string }> = {
  draft: { state: "inactive", label: "Draft" },
  ready_for_review: { state: "underReview", label: "Ready for Review" },
  approved: { state: "humanApproved", label: "Approved" },
  active: { state: "verified", label: "Active" },
  superseded: { state: "superseded", label: "Superseded" },
  withdrawn: { state: "withdrawn", label: "Withdrawn" },
};

export function LifecycleStatusBadge({ status, className }: { status: LifecycleStatus; className?: string }) {
  const display = LIFECYCLE_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const REVIEW_STATUS_DISPLAY: Record<ReviewStatus, { state: SemanticStateKey; label: string }> = {
  pending: { state: "inactive", label: "Pending" },
  changes_requested: { state: "warning", label: "Changes Requested" },
  recommended_for_approval: { state: "humanApproved", label: "Recommended for Approval" },
  rejected: { state: "critical", label: "Rejected" },
};

export function ReviewStatusBadge({ status, className }: { status: ReviewStatus; className?: string }) {
  const display = REVIEW_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString("en-GB", { year: "numeric", month: "short", day: "numeric" });
}
