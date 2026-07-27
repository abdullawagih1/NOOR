import { SemanticStatusBadge, type SemanticStateKey } from "@noor/ui";
import type {
  ExtractionReviewStatus,
  ExtractionFindingSeverity,
  ExtractionFindingStatus,
  ExtractionPageReviewStatus,
  ExtractionFindingType,
} from "@/lib/extraction-review/queries";

const REVIEW_STATUS_DISPLAY: Record<ExtractionReviewStatus, { state: SemanticStateKey; label: string }> = {
  pending_review: { state: "inactive", label: "Pending Review" },
  in_review: { state: "processing", label: "In Review" },
  accepted: { state: "verified", label: "Accepted" },
  accepted_with_warnings: { state: "warning", label: "Accepted With Warnings" },
  ocr_required: { state: "underReview", label: "OCR Required" },
  reprocessing_required: { state: "underReview", label: "Reprocessing Required" },
  rejected: { state: "critical", label: "Rejected" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
};

export function ExtractionReviewStatusBadge({ status, className }: { status: ExtractionReviewStatus; className?: string }) {
  const display = REVIEW_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const FINDING_SEVERITY_DISPLAY: Record<ExtractionFindingSeverity, { state: SemanticStateKey; label: string }> = {
  informational: { state: "informational", label: "Informational" },
  minor: { state: "underReview", label: "Minor" },
  major: { state: "warning", label: "Major" },
  critical: { state: "critical", label: "Critical" },
};

export function ExtractionFindingSeverityBadge({ severity, className }: { severity: ExtractionFindingSeverity; className?: string }) {
  const display = FINDING_SEVERITY_DISPLAY[severity];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const FINDING_STATUS_DISPLAY: Record<ExtractionFindingStatus, { state: SemanticStateKey; label: string }> = {
  open: { state: "warning", label: "Open" },
  acknowledged: { state: "underReview", label: "Acknowledged" },
  resolved: { state: "verified", label: "Resolved" },
  accepted_risk: { state: "informational", label: "Risk Accepted" },
  dismissed: { state: "inactive", label: "Dismissed" },
};

export function ExtractionFindingStatusBadge({ status, className }: { status: ExtractionFindingStatus; className?: string }) {
  const display = FINDING_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const PAGE_REVIEW_STATUS_DISPLAY: Record<ExtractionPageReviewStatus, { state: SemanticStateKey; label: string }> = {
  unreviewed: { state: "inactive", label: "Unreviewed" },
  reviewed_clear: { state: "verified", label: "Reviewed — Clear" },
  reviewed_with_findings: { state: "warning", label: "Reviewed — Findings" },
  ocr_candidate: { state: "underReview", label: "OCR Candidate" },
  reprocessing_candidate: { state: "underReview", label: "Reprocessing Candidate" },
};

export function ExtractionPageReviewStatusBadge({ status, className }: { status: ExtractionPageReviewStatus; className?: string }) {
  const display = PAGE_REVIEW_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

export const FINDING_TYPE_LABELS: Record<ExtractionFindingType, string> = {
  missing_text: "Missing text",
  partial_text: "Partial text",
  incorrect_reading_order: "Incorrect reading order",
  multi_column_order_issue: "Multi-column order issue",
  garbled_characters: "Garbled characters",
  unicode_normalization_issue: "Unicode normalization issue",
  arabic_shaping_issue: "Arabic shaping issue",
  arabic_direction_issue: "Arabic direction issue",
  mixed_language_direction_issue: "Mixed-language direction issue",
  rotation_issue: "Rotation issue",
  unexpected_blank_page: "Unexpected blank page",
  image_only_page: "Image-only page",
  suspected_scanned_page: "Suspected scanned page",
  table_structure_loss: "Table structure loss",
  figure_caption_loss: "Figure/caption loss",
  footnote_loss: "Footnote loss",
  header_footer_noise: "Header/footer noise",
  duplicate_text: "Duplicate text",
  missing_page: "Missing page",
  page_number_mismatch: "Page number mismatch",
  metadata_mismatch: "Metadata mismatch",
  source_integrity_concern: "Source integrity concern",
  other: "Other",
};

export const TECHNICAL_REVIEW_CHECKLIST = [
  "Source document opens correctly",
  "Page count matches",
  "Page order is correct",
  "Text is present where expected",
  "Arabic text is readable",
  "English text is readable",
  "Mixed-language direction is acceptable",
  "Rotated pages are handled",
  "Multi-column reading order is acceptable",
  "Tables and footnotes are not materially misleading",
  "Headers and footers do not overwhelm content",
  "No unexpected missing pages",
  "No unexpected duplicate text",
] as const;
