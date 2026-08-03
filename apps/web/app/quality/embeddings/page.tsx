import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { listDocumentEmbeddingRuns, listEmbeddingConfigurationsByIds } from "@/lib/embeddings/queries";
import { DocumentEmbeddingRunStatusBadge } from "@/lib/embeddings/ui";
import { createEmbeddingJobAction } from "@/lib/embeddings/actions";
import { PageHeader, Card, EmptyState, Alert, TextInput, Button } from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function EmbeddingRunQueuePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.DOCUMENT_EMBEDDINGS_READ);
  const { error } = await searchParams;

  const runs = await listDocumentEmbeddingRuns(context.organizationId);
  const configurationIds = Array.from(new Set(runs.map((r) => r.embedding_configuration_id)));
  const configurations = await listEmbeddingConfigurationsByIds(configurationIds);
  const configurationKeyById = new Map(configurations.map((c) => [c.id, c.configuration_key]));

  const canCreate = context.permissionKeys.includes(PERMISSIONS.DOCUMENT_EMBEDDINGS_CREATE);

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E2 — Embedding and pgvector Foundation"
        title="Document Embedding Runs"
        description="Immutable, checksum-verified chunk vectors under the one approved embedding configuration (self-hosted, no external API calls). No raw vectors are ever shown here — see ADR 0016."
      />

      {error ? (
        <Alert tone="critical" title="Could not complete that action">
          {error}
        </Alert>
      ) : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href="/quality/embeddings/configuration">
          View approved embedding configuration
        </Link>
      </div>

      {canCreate ? (
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Create embedding job</p>
          <form action={createEmbeddingJobAction} className="mt-xs flex flex-wrap items-end gap-xs">
            <TextInput label="Source document ID" name="sourceDocumentId" required hint="Must have a succeeded, accepted chunking run" className="flex-1" />
            <Button type="submit" size="sm">
              Create job
            </Button>
          </form>
        </Card>
      ) : null}

      {runs.length === 0 ? (
        <EmptyState title="No embedding runs yet" description="No document embedding runs have been created for this organization." />
      ) : (
        <div className="flex flex-col gap-md">
          {runs.map((run) => (
            <Card key={run.id}>
              <div className="flex flex-wrap items-center justify-between gap-sm">
                <div>
                  <p className="text-base font-semibold text-ink">{configurationKeyById.get(run.embedding_configuration_id) ?? run.embedding_configuration_id}</p>
                  <p className="text-xs text-muted">
                    {run.succeeded_count}/{run.total_chunk_count} succeeded · {run.failed_count} failed · created {new Date(run.created_at).toLocaleString()}
                  </p>
                </div>
                <DocumentEmbeddingRunStatusBadge status={run.status} />
              </div>
              <div className="mt-sm">
                <Link className="text-sm underline" href={`/quality/embeddings/runs/${run.id}`}>
                  Open run detail
                </Link>
              </div>
            </Card>
          ))}
        </div>
      )}
    </main>
  );
}
