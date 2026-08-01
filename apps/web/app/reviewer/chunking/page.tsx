import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { listChunkingReviewQueue } from "@/lib/chunking/queries";
import { ChunkingReviewStatusBadge, ChunkingRunStatusBadge } from "@/lib/chunking/ui";
import { PageHeader, Card, EmptyState, Alert } from "@noor/ui";

export const dynamic = "force-dynamic";

const ACTIVE_STATUSES = new Set(["pending_review", "in_review"]);

export default async function ChunkingReviewQueuePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; filter?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_READ);
  const { error, filter } = await searchParams;

  const allItems = await listChunkingReviewQueue(context.organizationId);

  let items = allItems;
  if (filter === "unassigned") {
    items = allItems.filter((i) => !i.review.assigned_reviewer_id && ACTIVE_STATUSES.has(i.review.review_status));
  } else if (filter === "mine") {
    items = allItems.filter((i) => i.review.assigned_reviewer_id === context.userId);
  } else if (filter === "active") {
    items = allItems.filter((i) => ACTIVE_STATUSES.has(i.review.review_status));
  } else if (filter === "accepted_with_warnings" || filter === "rechunk_required" || filter === "rejected") {
    items = allItems.filter((i) => i.review.review_status === filter);
  }

  const filters: Array<{ key: string; label: string }> = [
    { key: "", label: "All" },
    { key: "active", label: "Active" },
    { key: "unassigned", label: "Unassigned" },
    { key: "mine", label: "Assigned to me" },
    { key: "accepted_with_warnings", label: "Accepted with warnings" },
    { key: "rechunk_required", label: "Rechunk required" },
    { key: "rejected", label: "Rejected" },
  ];

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-D3 — Deterministic Page-Aware Chunking"
        title="Chunk Technical Review Queue"
        description="A technical review of chunk boundaries, provenance, and sizing — never a clinical review, and it never edits chunk text. A chunking run only becomes eligible for a future embedding step once every chunk here is reviewed and the round is accepted."
      />

      {error ? <Alert tone="critical" title="Could not complete that action">{error}</Alert> : null}

      <nav className="flex flex-wrap gap-xs text-xs" aria-label="Filter chunking reviews">
        {filters.map((f) => (
          <Link
            key={f.key}
            href={f.key ? `/reviewer/chunking?filter=${f.key}` : "/reviewer/chunking"}
            className={`rounded-full border px-sm py-xxs ${filter === f.key || (!filter && !f.key) ? "border-ink bg-ink text-onPrimary" : "border-border text-muted"}`}
          >
            {f.label}
          </Link>
        ))}
      </nav>

      {items.length === 0 ? (
        <EmptyState title="Nothing to review" description="No chunking reviews match this filter." />
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
                    {item.sourceFilename} · {item.run.chunk_count ?? 0} chunk{item.run.chunk_count === 1 ? "" : "s"} across {item.run.page_count ?? 0} page
                    {item.run.page_count === 1 ? "" : "s"}
                  </p>
                  <p className="text-xs text-muted">
                    Round {item.review.review_round} · {item.review.chunks_reviewed}/{item.review.total_chunks} chunks reviewed
                    {item.review.assigned_reviewer_id ? " · Assigned" : " · Unassigned"}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-xxs">
                  <ChunkingReviewStatusBadge status={item.review.review_status} />
                  <ChunkingRunStatusBadge status={item.run.status} />
                </div>
              </div>
              <div className="mt-sm">
                <Link className="text-sm underline" href={`/reviewer/chunking/${item.review.id}`}>
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
