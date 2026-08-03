import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getApprovedEmbeddingConfiguration } from "@/lib/embeddings/queries";
import { PageHeader, Card, Section, Alert, Badge } from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function ApprovedEmbeddingConfigurationPage() {
  await requirePermission(PERMISSIONS.EMBEDDING_CONFIGURATIONS_READ);

  let configuration;
  let loadError: string | null = null;
  try {
    configuration = await getApprovedEmbeddingConfiguration();
  } catch {
    loadError = "No approved embedding configuration exists. Contact an administrator.";
  }

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E2 — Embedding and pgvector Foundation"
        title="Approved Embedding Configuration"
        description="The single, server-managed embedding configuration in effect for this platform. Normal users cannot create or mutate configurations — see ADR 0016 / mission §10."
      />

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href="/quality/embeddings">
          ← Back to embedding runs
        </Link>
      </div>

      {loadError ? (
        <Alert tone="critical" title="Could not load a configuration">
          {loadError}
        </Alert>
      ) : configuration ? (
        <Section title="Configuration">
          <Card>
            <div className="flex flex-wrap items-center justify-between gap-sm">
              <p className="text-base font-semibold text-ink">{configuration.configuration_key}</p>
              <Badge>{configuration.approval_status}</Badge>
            </div>
            <dl className="mt-sm grid gap-sm text-sm sm:grid-cols-2">
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Provider</dt>
                <dd className="text-body">
                  {configuration.provider_name} ({configuration.provider_type}) v{configuration.provider_version}
                </dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Model</dt>
                <dd className="text-body">
                  {configuration.model_identifier} @ {configuration.model_revision}
                </dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Embedding dimension</dt>
                <dd className="text-body">{configuration.embedding_dimension}</dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Maximum input tokens</dt>
                <dd className="text-body">{configuration.maximum_input_tokens}</dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Tokenizer</dt>
                <dd className="text-body">
                  {configuration.tokenizer_name} v{configuration.tokenizer_version}
                </dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Distance metric</dt>
                <dd className="text-body">
                  {configuration.distance_metric} ({configuration.output_normalization})
                </dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Passage / query template versions</dt>
                <dd className="text-body">
                  {configuration.passage_input_template_version} / {configuration.query_input_template_version}
                </dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Configuration version</dt>
                <dd className="text-body">{configuration.configuration_version}</dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Data region</dt>
                <dd className="text-body">{configuration.data_region ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">External processing</dt>
                <dd className="text-body">{configuration.external_processing ? "Yes" : "No — self-hosted, no data leaves Noor infrastructure"}</dd>
              </div>
              <div className="sm:col-span-2">
                <dt className="text-xs uppercase tracking-wide text-muted">Data retention</dt>
                <dd className="text-body">{configuration.data_retention_summary ?? "—"}</dd>
              </div>
              <div>
                <dt className="text-xs uppercase tracking-wide text-muted">Approved at</dt>
                <dd className="text-body">{configuration.approved_at ? new Date(configuration.approved_at).toLocaleString() : "—"}</dd>
              </div>
            </dl>
          </Card>
        </Section>
      ) : null}
    </main>
  );
}
