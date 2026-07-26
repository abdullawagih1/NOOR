import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { listActiveGuidelinesForClinician } from "@/lib/guidelines/queries";
import { LifecycleStatusBadge, formatDate } from "@/lib/guidelines/ui";
import { PageHeader, Card, EmptyState } from "@noor/ui";

export const dynamic = "force-dynamic";

/**
 * Read-only. Deliberately shows ONLY guidelines with a current active
 * version — drafts, pending reviews, and withdrawn guidance are excluded
 * by construction (listActiveGuidelinesForClinician filters on
 * currentActiveVersion, which RLS additionally guarantees clinicians can
 * see at all: guideline_versions_select_active_for_members only exposes
 * lifecycle_status = 'active' rows to a caller without guidelines.read_all).
 * This is not yet the Ask Noor interface — retrieval/generation are later.
 */
export default async function ClinicianKnowledgePage() {
  const context = await requirePermission(PERMISSIONS.GUIDELINES_READ_ACTIVE);
  const guidelines = await listActiveGuidelinesForClinician(context.organizationId);

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="Active Clinical Knowledge"
        description="Approved, active guideline versions available in your organization. Only clinically active guidance is shown — drafts, pending reviews, and withdrawn versions never appear here."
      />

      {guidelines.length === 0 ? (
        <EmptyState
          title="No active guidelines yet"
          description="Once a guideline version completes review, approval, and activation, it will appear here."
        />
      ) : (
        <div className="flex flex-col gap-md">
          {guidelines.map((g) => (
            <Card key={g.id}>
              <div className="flex flex-wrap items-center justify-between gap-sm">
                <div>
                  <p className="text-base font-semibold text-ink">{g.canonical_title}</p>
                  <p className="text-sm text-muted">
                    {g.domain?.name ?? "—"} · {g.authority?.name ?? "—"}
                  </p>
                </div>
                <LifecycleStatusBadge status="active" />
              </div>
              <p className="mt-sm text-sm text-muted">
                Version {g.currentActiveVersion?.version_label} · Effective {formatDate(g.currentActiveVersion?.effective_date)}
              </p>
            </Card>
          ))}
        </div>
      )}
    </main>
  );
}
