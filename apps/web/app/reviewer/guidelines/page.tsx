import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { listReviewQueue } from "@/lib/guidelines/queries";
import { LifecycleStatusBadge, formatDate } from "@/lib/guidelines/ui";
import { submitGuidelineReviewAction } from "@/lib/guidelines/actions";
import { PageHeader, Card, EmptyState, TextInput, Textarea, Select, Button, Alert } from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function ReviewerGuidelinesPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINES_REVIEW);
  const { error } = await searchParams;

  const queue = await listReviewQueue(context.organizationId);

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="Guideline Review Queue"
        description="Versions submitted for clinical review. Recommending approval, requesting changes, and rejecting are all real, audited decisions — activation happens separately, in Admin, after approval."
      />

      {error ? <Alert tone="critical" title="Could not submit that review">{error}</Alert> : null}

      {queue.length === 0 ? (
        <EmptyState title="Nothing pending review" description="No guideline versions are currently ready_for_review." />
      ) : (
        <div className="flex flex-col gap-md">
          {queue.map((v) => (
            <Card key={v.id}>
              <div className="flex flex-wrap items-center justify-between gap-sm">
                <div>
                  <p className="text-base font-semibold text-ink">
                    {v.guidelineTitle} — {v.version_label}
                  </p>
                  <p className="text-sm text-muted">Submitted {formatDate(v.updated_at)}</p>
                </div>
                <LifecycleStatusBadge status={v.lifecycle_status} />
              </div>

              {v.evidence_scope ? <p className="mt-sm text-sm text-body">{v.evidence_scope}</p> : null}

              <form action={submitGuidelineReviewAction} className="mt-md flex flex-col gap-sm">
                <input type="hidden" name="guidelineVersionId" value={v.id} />
                <Select label="Decision" name="reviewStatus" defaultValue="pending" required>
                  <option value="recommended_for_approval">Recommend for approval</option>
                  <option value="changes_requested">Request changes</option>
                  <option value="rejected">Reject</option>
                </Select>
                <Textarea label="Clinical comments" name="clinicalComments" />
                <Textarea label="Safety concerns" name="safetyConcerns" />
                <Textarea label="Requested changes" name="requestedChanges" />
                <div>
                  <Button type="submit" size="sm">
                    Submit review
                  </Button>
                </div>
              </form>
            </Card>
          ))}
        </div>
      )}
    </main>
  );
}
