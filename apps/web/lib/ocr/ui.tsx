import { SemanticStatusBadge, type SemanticStateKey } from "@noor/ui";
import type { OcrRequestStatus, OcrRunStatus, OcrReviewStatus, OcrPageReviewStatus, OcrFindingSeverity, OcrFindingStatus, OcrFindingType } from "@/lib/ocr/queries";

const REQUEST_STATUS_DISPLAY: Record<OcrRequestStatus, { state: SemanticStateKey; label: string }> = {
  created: { state: "inactive", label: "Created" },
  queued: { state: "queued", label: "Queued" },
  processing: { state: "processing", label: "Processing" },
  awaiting_review: { state: "underReview", label: "Awaiting Review" },
  accepted: { state: "verified", label: "Accepted" },
  accepted_with_warnings: { state: "warning", label: "Accepted With Warnings" },
  reprocessing_required: { state: "reprocessingRequired", label: "Reprocessing Required" },
  rejected: { state: "critical", label: "Rejected" },
  cancelled: { state: "withdrawn", label: "Cancelled" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
};

export function OcrRequestStatusBadge({ status, className }: { status: OcrRequestStatus; className?: string }) {
  const display = REQUEST_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const RUN_STATUS_DISPLAY: Record<OcrRunStatus, { state: SemanticStateKey; label: string }> = {
  running: { state: "processing", label: "Running" },
  succeeded: { state: "verified", label: "Succeeded" },
  failed: { state: "critical", label: "Failed" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
  reused: { state: "informational", label: "Reused" },
};

export function OcrRunStatusBadge({ status, className }: { status: OcrRunStatus; className?: string }) {
  const display = RUN_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const REVIEW_STATUS_DISPLAY: Record<OcrReviewStatus, { state: SemanticStateKey; label: string }> = {
  pending_review: { state: "inactive", label: "Pending Review" },
  in_review: { state: "processing", label: "In Review" },
  accepted: { state: "verified", label: "Accepted" },
  accepted_with_warnings: { state: "warning", label: "Accepted With Warnings" },
  reprocessing_required: { state: "reprocessingRequired", label: "Reprocessing Required" },
  rejected: { state: "critical", label: "Rejected" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
};

export function OcrReviewStatusBadge({ status, className }: { status: OcrReviewStatus; className?: string }) {
  const display = REVIEW_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const PAGE_REVIEW_STATUS_DISPLAY: Record<OcrPageReviewStatus, { state: SemanticStateKey; label: string }> = {
  unreviewed: { state: "inactive", label: "Unreviewed" },
  accepted: { state: "verified", label: "Accepted" },
  accepted_with_warnings: { state: "warning", label: "Accepted With Warnings" },
  reprocessing_required: { state: "reprocessingRequired", label: "Reprocessing Required" },
  rejected: { state: "critical", label: "Rejected" },
};

export function OcrPageReviewStatusBadge({ status, className }: { status: OcrPageReviewStatus; className?: string }) {
  const display = PAGE_REVIEW_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const FINDING_SEVERITY_DISPLAY: Record<OcrFindingSeverity, { state: SemanticStateKey; label: string }> = {
  informational: { state: "informational", label: "Informational" },
  minor: { state: "underReview", label: "Minor" },
  major: { state: "warning", label: "Major" },
  critical: { state: "critical", label: "Critical" },
};

export function OcrFindingSeverityBadge({ severity, className }: { severity: OcrFindingSeverity; className?: string }) {
  const display = FINDING_SEVERITY_DISPLAY[severity];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const FINDING_STATUS_DISPLAY: Record<OcrFindingStatus, { state: SemanticStateKey; label: string }> = {
  open: { state: "warning", label: "Open" },
  acknowledged: { state: "underReview", label: "Acknowledged" },
  resolved: { state: "verified", label: "Resolved" },
  accepted_risk: { state: "informational", label: "Risk Accepted" },
  dismissed: { state: "inactive", label: "Dismissed" },
};

export function OcrFindingStatusBadge({ status, className }: { status: OcrFindingStatus; className?: string }) {
  const display = FINDING_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

export const OCR_FINDING_TYPE_LABELS: Record<OcrFindingType, string> = {
  missing_text: "Missing text",
  partial_text: "Partial text",
  incorrect_reading_order: "Incorrect reading order",
  garbled_characters: "Garbled characters",
  arabic_recognition_issue: "Arabic recognition issue",
  english_recognition_issue: "English recognition issue",
  mixed_language_issue: "Mixed-language issue",
  punctuation_loss: "Punctuation loss",
  number_recognition_issue: "Number recognition issue",
  table_structure_loss: "Table structure loss",
  header_footer_noise: "Header/footer noise",
  duplicate_text: "Duplicate text",
  low_confidence: "Low confidence",
  page_segmentation_issue: "Page segmentation issue",
  rotation_issue: "Rotation issue",
  unexpected_content: "Unexpected content",
  provider_error: "Provider error",
  other: "Other",
};

export const OCR_TECHNICAL_REVIEW_CHECKLIST = [
  "Recognized text is present where expected",
  "Arabic text is readable and correctly shaped",
  "English text is readable",
  "Mixed-language direction is acceptable",
  "Reading order matches the original page",
  "No garbled or nonsensical characters",
  "Numbers and punctuation are preserved",
  "Tables are not materially misrepresented as running text",
  "Headers/footers do not overwhelm recognized content",
  "Provider confidence, where shown, is technical metadata only — not a clinical or evidence-quality signal",
] as const;
