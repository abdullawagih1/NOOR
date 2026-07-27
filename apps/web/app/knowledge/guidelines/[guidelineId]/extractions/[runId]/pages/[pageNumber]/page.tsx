import { notFound } from "next/navigation";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getDocumentExtractionRun, getDocumentExtractionPage } from "@/lib/documents/queries";
import { ExtractionPageStatusBadge, shortSha } from "@/lib/documents/ui";
import { PageHeader, Card, Badge } from "@noor/ui";

export const dynamic = "force-dynamic";

/**
 * Minimal, read-only page-detail view (mission §30.3). Shows normalized
 * text only — never raw_text (queries.ts's column list excludes it
 * entirely), no editing, no clinical-approval controls. A future
 * reviewer-correction workflow (S1-D) is explicitly out of this sprint's
 * scope.
 */
export default async function ExtractionPageDetail({
  params,
}: {
  params: Promise<{ guidelineId: string; runId: string; pageNumber: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTIONS_READ_PAGES);
  const { runId, pageNumber } = await params;
  const pageNum = Number(pageNumber);
  if (!Number.isInteger(pageNum) || pageNum < 1) {
    notFound();
  }

  const run = await getDocumentExtractionRun(runId);
  if (!run || run.organization_id !== context.organizationId) {
    notFound();
  }

  const page = await getDocumentExtractionPage(runId, pageNum);
  if (!page || page.organization_id !== context.organizationId) {
    notFound();
  }

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow={`Extraction ${shortSha(run.artifact_sha256 ?? run.source_sha256)}`}
        title={`Page ${page.page_number}`}
        description={`${run.extractor_name} ${run.extractor_version} · pipeline ${run.pipeline_version}`}
        actions={<ExtractionPageStatusBadge status={page.extraction_status} />}
      />

      <div className="grid gap-sm sm:grid-cols-4">
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Dimensions</p>
          <p className="text-base text-ink">
            {page.width_points ?? "—"} × {page.height_points ?? "—"} pt
          </p>
        </Card>
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Rotation</p>
          <p className="text-base text-ink">{page.rotation_degrees}°</p>
        </Card>
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Characters / Words</p>
          <p className="text-base text-ink">
            {page.character_count} / {page.word_count}
          </p>
        </Card>
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Page checksum</p>
          <p className="font-mono text-sm text-ink">{shortSha(page.page_checksum)}</p>
        </Card>
      </div>

      {page.suspected_scanned ? (
        <Badge>Suspected scanned — no extractable text layer detected; OCR may be required in a later workflow</Badge>
      ) : null}

      {page.warnings.length > 0 ? (
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Warnings</p>
          <ul className="mt-xs list-disc pl-md text-sm text-body">
            {page.warnings.map((w, i) => (
              <li key={i}>{w}</li>
            ))}
          </ul>
        </Card>
      ) : null}

      <Card>
        <p className="text-xs font-semibold uppercase tracking-wide text-muted">Normalized text (read-only)</p>
        {page.is_blank ? (
          <p className="mt-xs text-sm text-muted">No extractable text on this page.</p>
        ) : (
          <pre className="mt-xs max-h-[70vh] overflow-auto whitespace-pre-wrap break-words text-sm text-body" dir="auto">
            {page.normalized_text}
          </pre>
        )}
      </Card>
    </main>
  );
}
