import { SemanticStatusBadge, type SemanticStateKey } from "@noor/ui";
import type {
  RetrievalEvaluationDatasetStatus,
  RetrievalEvaluationRunStatus,
  RetrievalEvaluationFailureStatus,
  QueryCategory,
  FailureCategory,
} from "@/lib/retrieval-evaluation/queries";

const DATASET_STATUS_DISPLAY: Record<RetrievalEvaluationDatasetStatus, { state: SemanticStateKey; label: string }> = {
  draft: { state: "inactive", label: "Draft" },
  ready_for_review: { state: "underReview", label: "Ready For Review" },
  frozen: { state: "verified", label: "Frozen" },
  // No dedicated "archived" semantic state exists — "superseded" (icon:
  // archive) is the closest existing meaning, reused rather than inventing
  // a new token, same approach ChunkingReviewStatusBadge takes for
  // "rechunk_required" (packages/ui/tokens/colors.ts).
  archived: { state: "superseded", label: "Archived" },
};

export function RetrievalEvaluationDatasetStatusBadge({ status, className }: { status: RetrievalEvaluationDatasetStatus; className?: string }) {
  const display = DATASET_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const RUN_STATUS_DISPLAY: Record<RetrievalEvaluationRunStatus, { state: SemanticStateKey; label: string }> = {
  running: { state: "processing", label: "Running" },
  succeeded: { state: "verified", label: "Succeeded" },
  failed: { state: "failed", label: "Failed" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
  // No dedicated "cancelled" semantic state exists — "inactive" is the
  // closest existing meaning ("not currently active").
  cancelled: { state: "inactive", label: "Cancelled" },
  reused: { state: "informational", label: "Reused" },
};

export function RetrievalEvaluationRunStatusBadge({ status, className }: { status: RetrievalEvaluationRunStatus; className?: string }) {
  const display = RUN_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const FAILURE_STATUS_DISPLAY: Record<RetrievalEvaluationFailureStatus, { state: SemanticStateKey; label: string }> = {
  open: { state: "warning", label: "Open" },
  acknowledged: { state: "underReview", label: "Acknowledged" },
  resolved: { state: "verified", label: "Resolved" },
};

export function RetrievalEvaluationFailureStatusBadge({ status, className }: { status: RetrievalEvaluationFailureStatus; className?: string }) {
  const display = FAILURE_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

/**
 * 0–3 graded relevance display (mission §15/16, ADR 0015 — a technical
 * lexical-overlap/human-judged relevance grade, never called a "relevance
 * probability"). Reuses existing semantic states rather than inventing a
 * new one per grade: 0 reads as a hard negative (critical), 3 as a
 * confirmed positive (verified), with warning/informational as the two
 * middle grades.
 */
const RELEVANCE_GRADE_DISPLAY: Record<0 | 1 | 2 | 3, { state: SemanticStateKey; label: string }> = {
  0: { state: "critical", label: "0 — Not relevant" },
  1: { state: "warning", label: "1 — Marginally relevant" },
  2: { state: "informational", label: "2 — Relevant" },
  3: { state: "verified", label: "3 — Highly relevant" },
};

export function RelevanceGradeBadge({ grade, className }: { grade: 0 | 1 | 2 | 3; className?: string }) {
  const display = RELEVANCE_GRADE_DISPLAY[grade];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

export function relevanceGradeShortLabel(grade: number): string {
  switch (grade) {
    case 0:
      return "Not relevant";
    case 1:
      return "Marginally relevant";
    case 2:
      return "Relevant";
    case 3:
      return "Highly relevant";
    default:
      return "Unknown";
  }
}

export const QUERY_CATEGORY_LABELS: Record<QueryCategory, string> = {
  exact_phrase: "Exact phrase",
  keyword_lookup: "Keyword lookup",
  fact_location: "Fact location",
  definition: "Definition",
  procedure_step: "Procedure step",
  numeric_lookup: "Numeric lookup",
  abbreviation: "Abbreviation",
  heading_lookup: "Heading lookup",
  cross_paragraph: "Cross-paragraph",
  arabic_exact: "Arabic exact",
  arabic_keyword: "Arabic keyword",
  english_exact: "English exact",
  english_keyword: "English keyword",
  mixed_language: "Mixed language",
  negative_control: "Negative control",
  ambiguous: "Ambiguous",
  hard_lexical: "Hard lexical",
};

export const QUERY_DIFFICULTY_LABELS: Record<string, string> = {
  basic: "Basic",
  moderate: "Moderate",
  challenging: "Challenging",
};

export const RETRIEVAL_EVALUATION_LANGUAGE_LABELS: Record<string, string> = {
  en: "English",
  ar: "Arabic",
  mixed: "Mixed",
};

export const FAILURE_CATEGORY_LABELS: Record<FailureCategory, string> = {
  missed_relevant_item: "Missed relevant item",
  relevant_below_k: "Relevant item ranked below K",
  non_relevant_ranked_high: "Non-relevant item ranked high",
  exact_phrase_failure: "Exact phrase failure",
  arabic_normalization_failure: "Arabic normalization failure",
  mixed_language_failure: "Mixed-language failure",
  numeric_match_failure: "Numeric match failure",
  abbreviation_failure: "Abbreviation failure",
  tokenization_failure: "Tokenization failure",
  tie_break_failure: "Tie-break failure",
  query_too_broad: "Query too broad",
  query_too_narrow: "Query too narrow",
  insufficient_lexical_overlap: "Insufficient lexical overlap",
  negative_control_false_positive: "Negative-control false positive",
  judgment_gap: "Judgment gap",
  corpus_gap: "Corpus gap",
  other: "Other",
};

export const METRIC_BASE_LABELS: Record<string, string> = {
  precision: "Precision",
  recall: "Recall",
  hit_rate: "Hit rate",
  ndcg: "NDCG",
};

/** Splits a metric_name like "precision_at_5" into { base: "precision", k: 5 }; "mrr" has no K. */
export function parseMetricName(metricName: string): { base: string; k: number | null } {
  if (metricName === "mrr") return { base: "mrr", k: null };
  const match = metricName.match(/^(.+)_at_(\d+)$/);
  if (!match) return { base: metricName, k: null };
  return { base: match[1], k: Number.parseInt(match[2], 10) };
}

export const NO_CLINICAL_USE_NOTICE = "Synthetic evaluation content — not for clinical use";

export const LEXICAL_BASELINE_DISCLAIMER =
  "This is a deterministic lexical baseline (PostgreSQL full-text search) — never a proxy for embedding, hybrid, or reranked retrieval quality. No embeddings, no vector search, and no external AI calls are used anywhere in this evaluation.";
