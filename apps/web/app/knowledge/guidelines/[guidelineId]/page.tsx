import { notFound } from "next/navigation";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import {
  getGuideline,
  listGuidelineVersionReviews,
  listGuidelineVersionLifecycleEvents,
  type GuidelineVersionRow,
} from "@/lib/guidelines/queries";
import { LifecycleStatusBadge, ReviewStatusBadge, formatDate } from "@/lib/guidelines/ui";
import {
  createGuidelineVersionAction,
  submitGuidelineForReviewAction,
  returnGuidelineVersionToDraftAction,
  approveGuidelineVersionAction,
  activateGuidelineVersionAction,
  supersedeGuidelineVersionAction,
  withdrawGuidelineVersionAction,
} from "@/lib/guidelines/actions";
import { PageHeader, Card, Section, Badge, TextInput, Textarea, Select, Button, Alert } from "@noor/ui";

export const dynamic = "force-dynamic";

function LifecycleActions({
  version,
  guidelineId,
  permissionKeys,
  currentUserId,
}: {
  version: GuidelineVersionRow;
  guidelineId: string;
  permissionKeys: string[];
  currentUserId: string;
}) {
  const has = (p: string) => permissionKeys.includes(p);
  const isOwnVersion = version.created_by === currentUserId;
  const hidden = (
    <>
      <input type="hidden" name="versionId" value={version.id} />
      <input type="hidden" name="guidelineId" value={guidelineId} />
    </>
  );

  const actions: React.ReactNode[] = [];

  if (version.lifecycle_status === "draft" && has("guidelines.submit_for_review")) {
    actions.push(
      <form key="submit" action={submitGuidelineForReviewAction}>
        {hidden}
        <Button type="submit" size="sm" variant="secondary">
          Submit for review
        </Button>
      </form>
    );
  }

  if (version.lifecycle_status === "ready_for_review" && (has("guidelines.review") || has("guidelines.submit_for_review"))) {
    actions.push(
      <form key="return-draft" action={returnGuidelineVersionToDraftAction} className="flex items-end gap-xs">
        {hidden}
        <TextInput label="Reason" name="reason" required hint="Required" />
        <Button type="submit" size="sm" variant="secondary">
          Return to draft
        </Button>
      </form>
    );
  }

  if (version.lifecycle_status === "ready_for_review" && has("guidelines.approve") && !isOwnVersion) {
    actions.push(
      <form key="approve" action={approveGuidelineVersionAction}>
        {hidden}
        <Button type="submit" size="sm">
          Approve
        </Button>
      </form>
    );
  }
  if (version.lifecycle_status === "ready_for_review" && has("guidelines.approve") && isOwnVersion) {
    actions.push(
      <p key="approve-blocked" className="text-xs text-muted">
        You authored this version — another approver is required (self-approval is blocked).
      </p>
    );
  }

  if (version.lifecycle_status === "approved" && has("guidelines.activate")) {
    actions.push(
      <form key="activate" action={activateGuidelineVersionAction}>
        {hidden}
        <Button type="submit" size="sm">
          Activate
        </Button>
      </form>
    );
  }

  if (version.lifecycle_status === "approved" && has("guidelines.approve")) {
    actions.push(
      <form key="revoke" action={returnGuidelineVersionToDraftAction} className="flex items-end gap-xs">
        {hidden}
        <TextInput label="Revocation reason" name="reason" required hint="Required" />
        <Button type="submit" size="sm" variant="danger">
          Revoke approval
        </Button>
      </form>
    );
  }

  if (version.lifecycle_status === "active" && has("guidelines.supersede")) {
    actions.push(
      <form key="supersede" action={supersedeGuidelineVersionAction}>
        {hidden}
        <Button type="submit" size="sm" variant="secondary">
          Supersede
        </Button>
      </form>
    );
  }

  if ((version.lifecycle_status === "active" || version.lifecycle_status === "superseded") && has("guidelines.withdraw")) {
    actions.push(
      <form key="withdraw" action={withdrawGuidelineVersionAction} className="flex items-end gap-xs">
        {hidden}
        <TextInput label="Withdrawal reason" name="reason" required hint="Required" />
        <Button type="submit" size="sm" variant="danger">
          Withdraw
        </Button>
      </form>
    );
  }

  if (actions.length === 0) {
    return <p className="text-sm text-muted">No actions available for your role at this status.</p>;
  }

  return <div className="flex flex-wrap items-end gap-md">{actions}</div>;
}

async function VersionHistory({ version }: { version: GuidelineVersionRow }) {
  const [reviews, events] = await Promise.all([
    listGuidelineVersionReviews(version.id),
    listGuidelineVersionLifecycleEvents(version.id),
  ]);

  if (reviews.length === 0 && events.length === 0) return null;

  return (
    <div className="grid gap-md sm:grid-cols-2">
      {reviews.length > 0 ? (
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Reviews</p>
          <ul className="mt-xs flex flex-col gap-xs">
            {reviews.map((r) => (
              <li key={r.id} className="flex items-center gap-xs text-sm">
                <ReviewStatusBadge status={r.review_status} />
                <span className="text-muted">{formatDate(r.created_at)}</span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      {events.length > 0 ? (
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Status history</p>
          <ul className="mt-xs flex flex-col gap-xs">
            {events.map((e) => (
              <li key={e.id} className="text-sm text-body">
                {e.from_status ?? "—"} → {e.to_status}
                <span className="ml-xs text-muted">{formatDate(e.created_at)}</span>
                {e.reason ? <span className="block text-xs text-muted">{e.reason}</span> : null}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}

export default async function GuidelineDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ guidelineId: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINES_READ_ALL);
  const { guidelineId } = await params;
  const { error } = await searchParams;

  const { guideline, versions } = await getGuideline(guidelineId);
  if (!guideline || guideline.organization_id !== context.organizationId) {
    notFound();
  }

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow={guideline.internal_code}
        title={guideline.canonical_title}
        description={guideline.description ?? undefined}
        actions={guideline.currentActiveVersion ? <LifecycleStatusBadge status="active" /> : <Badge>No active version</Badge>}
      />

      {error ? <Alert tone="critical" title="Could not complete that action">{error}</Alert> : null}

      <div className="grid gap-sm sm:grid-cols-3">
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Clinical domain</p>
          <p className="text-base text-ink">{guideline.domain?.name ?? "—"}</p>
        </Card>
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Authority</p>
          <p className="text-base text-ink">
            {guideline.authority?.name ?? "—"}
            {guideline.authority && !guideline.authority.is_verified ? <Badge className="ml-xs">Unverified</Badge> : null}
          </p>
        </Card>
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Jurisdiction</p>
          <p className="text-base text-ink">{guideline.jurisdiction ?? "—"}</p>
        </Card>
      </div>

      {context.permissionKeys.includes(PERMISSIONS.GUIDELINES_CREATE) ? (
        <Card>
          <Section title="New version" description="Creates a new draft version. Content is registry metadata only — no file upload in this task.">
            <form action={createGuidelineVersionAction} className="grid gap-md sm:grid-cols-2">
              <input type="hidden" name="guidelineId" value={guideline.id} />
              <TextInput label="Version label" name="versionLabel" placeholder="e.g. v1.0" required />
              <Select label="Language" name="language" defaultValue={guideline.default_language}>
                <option value="en">English</option>
                <option value="ar">Arabic</option>
              </Select>
              <TextInput label="Edition" name="edition" />
              <TextInput label="Publication date" name="publicationDate" type="date" />
              <TextInput label="Effective date" name="effectiveDate" type="date" />
              <TextInput label="Review due date" name="reviewDueDate" type="date" />
              <TextInput label="Expiry date" name="expiryDate" type="date" />
              <TextInput label="Source URL" name="sourceUrl" />
              <Textarea label="Evidence scope" name="evidenceScope" className="sm:col-span-2" />
              <Textarea label="Notes" name="notes" className="sm:col-span-2" />
              <div className="sm:col-span-2">
                <Button type="submit" variant="secondary">
                  Create draft version
                </Button>
              </div>
            </form>
          </Section>
        </Card>
      ) : null}

      <Section title="Versions" description={`${versions.length} version${versions.length === 1 ? "" : "s"}`}>
        {versions.length === 0 ? (
          <p className="text-sm text-muted">No versions yet.</p>
        ) : (
          <div className="flex flex-col gap-md">
            {versions.map((v) => (
              <Card key={v.id}>
                <div className="flex flex-wrap items-center justify-between gap-sm">
                  <div>
                    <p className="text-base font-semibold text-ink">{v.version_label}</p>
                    <p className="text-sm text-muted">
                      Effective {formatDate(v.effective_date)} · Updated {formatDate(v.updated_at)}
                    </p>
                  </div>
                  <LifecycleStatusBadge status={v.lifecycle_status} />
                </div>

                {v.lifecycle_status === "withdrawn" && v.withdrawal_reason ? (
                  <Alert tone="warning" title="Withdrawn" className="mt-sm">
                    {v.withdrawal_reason}
                  </Alert>
                ) : null}

                <div className="mt-md">
                  <LifecycleActions
                    version={v}
                    guidelineId={guideline.id}
                    permissionKeys={context.permissionKeys}
                    currentUserId={context.userId}
                  />
                </div>

                <div className="mt-md">
                  <VersionHistory version={v} />
                </div>
              </Card>
            ))}
          </div>
        )}
      </Section>
    </main>
  );
}
