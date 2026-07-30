import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { listOcrReviewQueue } from "@/lib/ocr/queries";
import { OcrReviewStatusBadge, OcrRequestStatusBadge } from "@/lib/ocr/ui";
import { PageHeader, Card, EmptyState, Alert } from "@noor/ui";

export const dynamic = "force-dynamic";

const ACTIVE_STATUSES = new Set(["pending_review", "in_review"]);

export default async function OcrReviewQueuePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; filter?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_OCR_READ);
  const { error, filter } = await searchParams;

  const allItems = await listOcrReviewQueue(context.organizationId);

  let items = allItems;
  if (filter === "unassigned") {
    items = allItems.filter((i) => !i.review.assigned_reviewer_id && ACTIVE_STATUSES.has(i.review.review_status));
  } else if (filter === "mine") {
    items = allItems.filter((i) => i.review.assigned_reviewer_id === context.userId);
  } else if (filter === "active") {
    items = allItems.filter((i) => ACTIVE_STATUSES.has(i.review.review_status));
  } else if (filter === "accepted_with_warnings" || filter === "reprocessing_required" || filter === "rejected") {
    items = allItems.filter((i) => i.review.review_status === filter);
  }

  const filters: Array<{ key: string; label: string }> = [
    { key: "", label: "All" },
    { key: "active", label: "Active" },
    { key: "unassigned", label: "Unassigned" },
    { key: "mine", label: "Assigned to me" },
    { key: "accepted_with_warnings", label: "Accepted with warnings" },
    { key: "reprocessing_required", label: "Reprocessing required" },
    { key: "rejected", label: "Rejected" },
  ];

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-D2 — Controlled Page-Scoped OCR"
        title="OCR Review Queue"
        description="Every OCR result here came from a page a human reviewer explicitly flagged for OCR — never a whole document. This is a technical review of recognition quality, not a clinical one, and it never edits the recognized text."
      />

      {error ? <Alert tone="critical" title="Could not complete that action">{error}</Alert> : null}

      <nav className="flex flex-wrap gap-xs text-xs" aria-label="Filter OCR reviews">
        {filters.map((f) => (
          <Link
            key={f.key}
            href={f.key ? `/reviewer/ocr?filter=${f.key}` : "/reviewer/ocr"}
            className={`rounded-full border px-sm py-xxs ${filter === f.key || (!filter && !f.key) ? "border-ink bg-ink text-onPrimary" : "border-border text-muted"}`}
          >
            {f.label}
          </Link>
        ))}
      </nav>

      {items.length === 0 ? (
        <EmptyState title="Nothing to review" description="No OCR reviews match this filter." />
      ) : (
        <div className="flex flex-col gap-md">
          {items.map((item) => (
            <Card key={item.review.id}>
              <div className="flex flex-wrap items-center justify-between gap-sm">
                <div>
                  <p className="text-base font-semibold text-ink">
                    {item.guidelineTitle} — {item.guidelineVersionLabel}
                  </p>
                  <p className="text-sm text-muted">
                    {item.sourceFilename} · {item.request.total_pages} OCR page{item.request.total_pages === 1 ? "" : "s"} requested
                  </p>
                  <p className="text-xs text-muted">
                    Round {item.review.review_round} · {item.review.pages_reviewed}/{item.review.total_pages} pages reviewed
                    {item.review.assigned_reviewer_id ? " · Assigned" : " · Unassigned"}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-xxs">
                  <OcrReviewStatusBadge status={item.review.review_status} />
                  <OcrRequestStatusBadge status={item.request.status} />
                </div>
              </div>
              <div className="mt-sm">
                <Link className="text-sm underline" href={`/reviewer/ocr/${item.review.id}`}>
                  Open review
                </Link>
              </div>
            </Card>
          ))}
        </div>
      )}
    </main>
  );
}
