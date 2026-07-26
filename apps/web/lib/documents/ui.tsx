import { SemanticStatusBadge, type SemanticStateKey } from "@noor/ui";
import type { DocumentStatus, ProcessingJobStatus } from "@/lib/documents/queries";

const DOCUMENT_STATUS_DISPLAY: Record<DocumentStatus, { state: SemanticStateKey; label: string }> = {
  pending_upload: { state: "inactive", label: "Pending Upload" },
  uploaded: { state: "processing", label: "Uploaded" },
  verified: { state: "underReview", label: "Verified" },
  registered: { state: "verified", label: "Registered" },
  rejected: { state: "critical", label: "Rejected" },
  quarantined: { state: "withdrawn", label: "Quarantined" },
};

export function DocumentStatusBadge({ status, className }: { status: DocumentStatus; className?: string }) {
  const display = DOCUMENT_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const JOB_STATUS_DISPLAY: Record<ProcessingJobStatus, { state: SemanticStateKey; label: string }> = {
  queued: { state: "inactive", label: "Queued" },
  claimed: { state: "underReview", label: "Claimed" },
  processing: { state: "processing", label: "Processing" },
  succeeded: { state: "verified", label: "Succeeded" },
  failed: { state: "critical", label: "Failed" },
  cancelled: { state: "withdrawn", label: "Cancelled" },
  dead_lettered: { state: "critical", label: "Dead-lettered" },
};

export function JobStatusBadge({ status, className }: { status: ProcessingJobStatus; className?: string }) {
  const display = JOB_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

export function formatBytes(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/** Short checksum fingerprint for display — never the full value in a permanent UI surface without reason. */
export function shortSha(sha256: string | null | undefined): string {
  if (!sha256) return "—";
  return sha256.slice(0, 12);
}
