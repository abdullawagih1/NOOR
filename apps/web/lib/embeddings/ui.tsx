import { SemanticStatusBadge, type SemanticStateKey } from "@noor/ui";
import type { DocumentEmbeddingRunStatus } from "@/lib/embeddings/queries";

const DOCUMENT_EMBEDDING_RUN_STATUS_DISPLAY: Record<DocumentEmbeddingRunStatus, { state: SemanticStateKey; label: string }> = {
  created: { state: "informational", label: "Created" },
  queued: { state: "queued", label: "Queued" },
  processing: { state: "processing", label: "Processing" },
  succeeded: { state: "verified", label: "Succeeded" },
  succeeded_with_reuse: { state: "verified", label: "Succeeded (reused)" },
  failed: { state: "failed", label: "Failed" },
  // No dedicated "cancelled" semantic state exists — "inactive" is the
  // closest existing meaning, same convention as
  // RetrievalEvaluationRunStatusBadge.
  cancelled: { state: "inactive", label: "Cancelled" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
  reused: { state: "informational", label: "Reused" },
};

export function DocumentEmbeddingRunStatusBadge({ status, className }: { status: DocumentEmbeddingRunStatus; className?: string }) {
  const display = DOCUMENT_EMBEDDING_RUN_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}
