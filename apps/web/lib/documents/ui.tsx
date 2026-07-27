import { SemanticStatusBadge, type SemanticStateKey } from "@noor/ui";
import type {
  DocumentStatus,
  ProcessingJobStatus,
  ProcessingAttemptStatus,
  ExtractionRunStatus,
  ExtractionPageStatus,
} from "@/lib/documents/queries";

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
  retry_scheduled: { state: "underReview", label: "Retry Scheduled" },
  succeeded: { state: "verified", label: "Succeeded" },
  failed: { state: "critical", label: "Failed" },
  cancelled: { state: "withdrawn", label: "Cancelled" },
  dead_lettered: { state: "critical", label: "Dead-lettered" },
};

export function JobStatusBadge({ status, className }: { status: ProcessingJobStatus; className?: string }) {
  const display = JOB_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const ATTEMPT_STATUS_DISPLAY: Record<ProcessingAttemptStatus, { state: SemanticStateKey; label: string }> = {
  started: { state: "processing", label: "Started" },
  succeeded: { state: "verified", label: "Succeeded" },
  retryable_failure: { state: "underReview", label: "Retryable Failure" },
  terminal_failure: { state: "critical", label: "Terminal Failure" },
  lease_expired: { state: "critical", label: "Lease Expired" },
  cancelled: { state: "withdrawn", label: "Cancelled" },
  abandoned: { state: "withdrawn", label: "Abandoned" },
};

export function AttemptStatusBadge({ status, className }: { status: ProcessingAttemptStatus; className?: string }) {
  const display = ATTEMPT_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

/** Jobs are cancellable only while queued or waiting for their next retry (mirrors the DB-enforced allowed source statuses in cancel_processing_job). */
export function isJobCancellable(status: ProcessingJobStatus): boolean {
  return status === "queued" || status === "retry_scheduled";
}

const EXTRACTION_RUN_STATUS_DISPLAY: Record<ExtractionRunStatus, { state: SemanticStateKey; label: string }> = {
  running: { state: "processing", label: "Extracting" },
  succeeded: { state: "verified", label: "Extracted" },
  failed: { state: "critical", label: "Extraction Failed" },
  invalidated: { state: "withdrawn", label: "Invalidated" },
};

export function ExtractionRunStatusBadge({ status, className }: { status: ExtractionRunStatus; className?: string }) {
  const display = EXTRACTION_RUN_STATUS_DISPLAY[status];
  return <SemanticStatusBadge state={display.state} labelOverride={display.label} className={className} />;
}

const EXTRACTION_PAGE_STATUS_DISPLAY: Record<ExtractionPageStatus, { state: SemanticStateKey; label: string }> = {
  text_extracted: { state: "verified", label: "Text Extracted" },
  blank_page: { state: "inactive", label: "Blank Page" },
  no_text_layer: { state: "underReview", label: "No Text Layer" },
  partial_text: { state: "underReview", label: "Partial Text" },
  extraction_warning: { state: "underReview", label: "Warning" },
  failed: { state: "critical", label: "Failed" },
};

export function ExtractionPageStatusBadge({ status, className }: { status: ExtractionPageStatus; className?: string }) {
  const display = EXTRACTION_PAGE_STATUS_DISPLAY[status];
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
