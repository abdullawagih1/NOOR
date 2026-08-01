import { SemanticStatusBadge, type SemanticStateKey } from "@noor/ui";
import type { ChunkingRunStatus, ChunkingReviewStatus, ChunkReviewStatus, ChunkFindingSeverity, ChunkFindingStatus, ChunkFindingType } from "@/lib/chunking/queries";

const RUN_STATUS_DISPLAY: Record<ChunkingRunStatus, { state: SemanticStateKey; label: string }> = {
  running: { state: "processing", label: "Running" },
  succeeded: { state: "verified", label: "Succeeded" },
  failed: { state: "critical", label: "Failed" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
  reused: { state: "informational", label: "Reused" },
};

export function ChunkingRunStatusBadge({ status, className }: { status: ChunkingRunStatus; className?: string }) {
  const display = RUN_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const REVIEW_STATUS_DISPLAY: Record<ChunkingReviewStatus, { state: SemanticStateKey; label: string }> = {
  pending_review: { state: "inactive", label: "Pending Review" },
  in_review: { state: "processing", label: "In Review" },
  accepted: { state: "verified", label: "Accepted" },
  accepted_with_warnings: { state: "warning", label: "Accepted With Warnings" },
  // No dedicated "rechunk" semantic state exists — reprocessingRequired
  // is the closest existing meaning (OCR/extraction already reuse it for
  // "this pipeline output needs to be redone"), reused rather than
  // inventing a new token for a one-off label (packages/ui/tokens/colors.ts).
  rechunk_required: { state: "reprocessingRequired", label: "Rechunk Required" },
  rejected: { state: "critical", label: "Rejected" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
};

export function ChunkingReviewStatusBadge({ status, className }: { status: ChunkingReviewStatus; className?: string }) {
  const display = REVIEW_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const CHUNK_REVIEW_STATUS_DISPLAY: Record<ChunkReviewStatus, { state: SemanticStateKey; label: string }> = {
  unreviewed: { state: "inactive", label: "Unreviewed" },
  reviewed_clear: { state: "verified", label: "Reviewed — Clear" },
  reviewed_with_findings: { state: "warning", label: "Reviewed — Findings" },
  rechunk_candidate: { state: "reprocessingRequired", label: "Rechunk Candidate" },
  rejected: { state: "critical", label: "Rejected" },
};

export function ChunkReviewStatusBadge({ status, className }: { status: ChunkReviewStatus; className?: string }) {
  const display = CHUNK_REVIEW_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const FINDING_SEVERITY_DISPLAY: Record<ChunkFindingSeverity, { state: SemanticStateKey; label: string }> = {
  informational: { state: "informational", label: "Informational" },
  minor: { state: "underReview", label: "Minor" },
  major: { state: "warning", label: "Major" },
  critical: { state: "critical", label: "Critical" },
};

export function ChunkFindingSeverityBadge({ severity, className }: { severity: ChunkFindingSeverity; className?: string }) {
  const display = FINDING_SEVERITY_DISPLAY[severity];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const FINDING_STATUS_DISPLAY: Record<ChunkFindingStatus, { state: SemanticStateKey; label: string }> = {
  open: { state: "warning", label: "Open" },
  acknowledged: { state: "underReview", label: "Acknowledged" },
  resolved: { state: "verified", label: "Resolved" },
  accepted_risk: { state: "informational", label: "Risk Accepted" },
  dismissed: { state: "inactive", label: "Dismissed" },
};

export function ChunkFindingStatusBadge({ status, className }: { status: ChunkFindingStatus; className?: string }) {
  const display = FINDING_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

export const CHUNK_FINDING_TYPE_LABELS: Record<ChunkFindingType, string> = {
  missing_content: "Missing content",
  duplicated_content: "Duplicated content",
  invalid_source_span: "Invalid source span",
  wrong_page_provenance: "Wrong page provenance",
  wrong_representation: "Wrong representation",
  boundary_splits_sentence: "Boundary splits a sentence",
  boundary_splits_list: "Boundary splits a list",
  boundary_splits_table: "Boundary splits a table-like block",
  heading_detached: "Heading detached from its content",
  footnote_detached: "Footnote detached from its reference",
  merged_unrelated_content: "Merged unrelated content",
  insufficient_context: "Insufficient context",
  oversized_chunk: "Oversized chunk",
  undersized_chunk: "Undersized chunk",
  hard_split_required: "Hard split required",
  arabic_boundary_issue: "Arabic boundary issue",
  mixed_language_boundary_issue: "Mixed-language boundary issue",
  ocr_warning_propagation: "OCR warning propagation",
  header_footer_noise: "Header/footer noise",
  page_boundary_issue: "Page boundary issue",
  token_count_issue: "Token count issue",
  artifact_integrity_issue: "Artifact integrity issue",
  other: "Other",
};

export const CHUNK_TECHNICAL_REVIEW_CHECKLIST = [
  "The chunk's text is a faithful, unedited excerpt of the source page",
  "Boundaries do not cut a sentence, list item, or table row in a way that loses meaning",
  "Headings and their following content are not detached",
  "Chunk size looks reasonable for a future embedding step (not too small, not too large)",
  "Arabic and mixed-language boundaries read naturally",
  "Any inherited OCR warnings are reflected accurately, not silently dropped",
  "The chunk never crosses a page boundary (V1 policy — verify this was not bypassed)",
  "Token counts are a technical sizing proxy only — never a clinical or evidence-quality signal",
] as const;
