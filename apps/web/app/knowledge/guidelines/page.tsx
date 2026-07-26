import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { listGuidelines } from "@/lib/guidelines/queries";
import { LifecycleStatusBadge, formatDate } from "@/lib/guidelines/ui";
import type { LifecycleStatus } from "@/lib/guidelines/schemas";
import {
  PageHeader,
  EmptyState,
  Table,
  TableHead,
  TableBody,
  TableRow,
  TableHeaderCell,
  TableCell,
  Button,
  Badge,
} from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function GuidelinesRegistryPage({
  searchParams,
}: {
  searchParams: Promise<{ search?: string; status?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINES_READ_ALL);
  const params = await searchParams;

  const guidelines = await listGuidelines(context.organizationId, {
    search: params.search,
    lifecycleStatus: params.status as LifecycleStatus | undefined,
  });

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1 — Guideline Registry"
        title="Guideline Registry"
        description="The controlled source-of-truth registry for clinical guidelines: domain, authority, version, review, approval, and activation status."
        actions={
          <Link href="/knowledge/guidelines/new">
            <Button>New guideline</Button>
          </Link>
        }
      />

      <form className="flex flex-wrap items-end gap-sm" method="get">
        <div className="flex flex-col gap-xxs">
          <label htmlFor="search" className="text-sm font-medium text-body">
            Search
          </label>
          <input
            id="search"
            name="search"
            defaultValue={params.search ?? ""}
            placeholder="Title…"
            className="rounded-sm border border-border bg-canvas px-md py-xs text-base text-ink focus:border-primary focus:outline focus:outline-2 focus:outline-primary"
          />
        </div>
        <div className="flex flex-col gap-xxs">
          <label htmlFor="status" className="text-sm font-medium text-body">
            Status
          </label>
          <select
            id="status"
            name="status"
            defaultValue={params.status ?? ""}
            className="rounded-sm border border-border bg-canvas px-md py-xs text-base text-ink focus:border-primary focus:outline focus:outline-2 focus:outline-primary"
          >
            <option value="">All statuses</option>
            <option value="draft">Draft</option>
            <option value="ready_for_review">Ready for Review</option>
            <option value="approved">Approved</option>
            <option value="active">Active</option>
            <option value="superseded">Superseded</option>
            <option value="withdrawn">Withdrawn</option>
          </select>
        </div>
        <Button type="submit" variant="secondary" size="sm">
          Apply
        </Button>
      </form>

      {guidelines.length === 0 ? (
        <EmptyState
          title="No guidelines yet"
          description="Create the first guideline to begin the review, approval, and activation workflow. No PDF upload happens in this task — registry metadata only."
          action={
            <Link href="/knowledge/guidelines/new">
              <Button variant="secondary">New guideline</Button>
            </Link>
          }
        />
      ) : (
        <Table>
          <TableHead>
            <TableRow>
              <TableHeaderCell>Title</TableHeaderCell>
              <TableHeaderCell>Domain</TableHeaderCell>
              <TableHeaderCell>Authority</TableHeaderCell>
              <TableHeaderCell>Current version</TableHeaderCell>
              <TableHeaderCell>Status</TableHeaderCell>
              <TableHeaderCell>Effective date</TableHeaderCell>
              <TableHeaderCell>Updated</TableHeaderCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {guidelines.map((g) => (
              <TableRow key={g.id}>
                <TableCell>
                  <Link href={`/knowledge/guidelines/${g.id}`} className="font-medium text-primary hover:underline">
                    {g.canonical_title}
                  </Link>
                  <div className="text-xs text-muted">{g.internal_code}</div>
                </TableCell>
                <TableCell>{g.domain?.name ?? "—"}</TableCell>
                <TableCell>
                  {g.authority?.name ?? "—"}
                  {g.authority && !g.authority.is_verified ? (
                    <Badge className="ml-xs">Unverified authority</Badge>
                  ) : null}
                </TableCell>
                <TableCell>{g.currentActiveVersion?.version_label ?? "—"}</TableCell>
                <TableCell>
                  {g.currentActiveVersion ? <LifecycleStatusBadge status="active" /> : <span className="text-sm text-muted">No active version</span>}
                </TableCell>
                <TableCell>{formatDate(g.currentActiveVersion?.effective_date)}</TableCell>
                <TableCell>{formatDate(g.updated_at)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </main>
  );
}
