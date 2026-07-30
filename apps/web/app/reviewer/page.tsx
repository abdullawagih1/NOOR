import Link from "next/link";
import { PageHeader, Badge, EmptyState, Button } from "@noor/ui";

export default function ReviewerPage() {
  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="Clinical Reviewer Workspace"
        description="Review submitted guideline versions and record review decisions."
        actions={<Badge>Requires workspace.reviewer.access</Badge>}
      />
      <EmptyState
        title="Guideline review queue is live"
        description="Real guideline versions awaiting clinical review — approve/reject decisions and safety concerns are recorded and audited."
        action={
          <Link href="/reviewer/guidelines">
            <Button variant="secondary">Open Review Queue</Button>
          </Link>
        }
      />
      <EmptyState
        title="Extraction technical review is live (Sprint 1-D1)"
        description="A technical quality gate over deterministic PDF extraction — page-level findings, OCR/reprocessing/rejection decisions, and downstream chunking eligibility. This is a technical review, not a clinical one."
        action={
          <Link href="/reviewer/extractions">
            <Button variant="secondary">Open Extraction Review Queue</Button>
          </Link>
        }
      />
      <EmptyState
        title="OCR technical review is live (Sprint 1-D2)"
        description="Compares the original page, native extraction, and OCR recognition side by side for pages a reviewer explicitly flagged for OCR. This is a technical review of recognition quality, not a clinical one."
        action={
          <Link href="/reviewer/ocr">
            <Button variant="secondary">Open OCR Review Queue</Button>
          </Link>
        }
      />
    </main>
  );
}
