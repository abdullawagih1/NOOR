import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getDocumentEmbeddingRunDetail } from "@/lib/embeddings/queries";
import { DocumentEmbeddingRunStatusBadge } from "@/lib/embeddings/ui";
import { cancelEmbeddingRunAction } from "@/lib/embeddings/actions";
import { PageHeader, Card, Section, Alert, EmptyState, Button, TextInput } from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function EmbeddingRunDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ runId: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.DOCUMENT_EMBEDDINGS_READ);
  const { runId } = await params;
  const { error } = await searchParams;

  const detail = await getDocumentEmbeddingRunDetail(runId);
  if (!detail || detail.run.organization_id !== context.organizationId) {
    notFound();
  }
  const { run, configuration, chunkEmbeddingCount, succeededCount } = detail;

  const canCancel = ["created", "queued", "processing"].includes(run.status) && context.permissionKeys.includes(PERMISSIONS.DOCUMENT_EMBEDDINGS_CANCEL);

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E2 — Document Embedding Run"
        title={configuration ? configuration.configuration_key : "Embedding run"}
        description="Chunk-level embedding coverage and identity for one accepted chunking run. No raw vectors are ever shown here."
        actions={<DocumentEmbeddingRunStatusBadge status={run.status} />}
      />

      {error ? (
        <Alert tone="critical" title="Could not complete that action">
          {error}
        </Alert>
      ) : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href="/quality/embeddings">
          ← Back to embedding runs
        </Link>
      </div>

      <Section title="Run identity">
        <Card>
          <dl className="grid gap-sm text-sm sm:grid-cols-2">
            {configuration ? (
              <>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-muted">Model identity</dt>
                  <dd className="text-body">
                    {configuration.model_identifier} @ {configuration.model_revision}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-muted">Embedding dimension</dt>
                  <dd className="text-body">{configuration.embedding_dimension}</dd>
                </div>
              </>
            ) : null}
            <div className="sm:col-span-2">
              <dt className="text-xs uppercase tracking-wide text-muted">Chunk manifest checksum</dt>
              <dd className="break-all font-mono text-xs text-body">{run.chunk_manifest_sha256}</dd>
            </div>
            <div className="sm:col-span-2">
              <dt className="text-xs uppercase tracking-wide text-muted">Run identity checksum</dt>
              <dd className="break-all font-mono text-xs text-body">{run.run_identity_sha256}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Coverage (succeeded / total)</dt>
              <dd className="text-body">
                {succeededCount}/{chunkEmbeddingCount} chunk-embedding rows recorded · {run.succeeded_count}/{run.total_chunk_count} counted by the run
              </dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Failed / reused / invalidated</dt>
              <dd className="text-body">
                {run.failed_count} / {run.reused_count} / {run.invalidated_count}
              </dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Started / completed</dt>
              <dd className="text-body">
                {new Date(run.started_at).toLocaleString()} → {run.completed_at ? new Date(run.completed_at).toLocaleString() : "—"}
              </dd>
            </div>
            {run.artifact_sha256 ? (
              <div className="sm:col-span-2">
                <dt className="text-xs uppercase tracking-wide text-muted">Artifact checksum</dt>
                <dd className="font-mono text-xs text-body">{run.artifact_sha256}</dd>
              </div>
            ) : null}
            {run.invalidation_reason ? (
              <div className="sm:col-span-2">
                <dt className="text-xs uppercase tracking-wide text-muted">Invalidation reason</dt>
                <dd className="text-body">{run.invalidation_reason}</dd>
              </div>
            ) : null}
          </dl>
          {canCancel ? (
            <form action={cancelEmbeddingRunAction} className="mt-sm flex flex-wrap items-end gap-xs border-t border-border pt-sm">
              <input type="hidden" name="embeddingRunId" value={run.id} />
              <TextInput label="Cancellation reason" name="reason" required className="flex-1" />
              <Button type="submit" size="sm" variant="danger">
                Cancel run
              </Button>
            </form>
          ) : null}
        </Card>
      </Section>

      {chunkEmbeddingCount === 0 ? (
        <EmptyState title="No chunk embeddings recorded yet" description={run.status === "processing" || run.status === "queued" ? "This run has not produced any chunk embeddings yet." : "This run produced no chunk-embedding rows."} />
      ) : null}
    </main>
  );
}
