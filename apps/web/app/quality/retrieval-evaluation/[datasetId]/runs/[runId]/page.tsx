import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getRetrievalEvaluationDataset, getRetrievalEvaluationRunDetail, type RetrievalEvaluationMetricRow } from "@/lib/retrieval-evaluation/queries";
import { RetrievalEvaluationRunStatusBadge, LEXICAL_BASELINE_DISCLAIMER, METRIC_BASE_LABELS } from "@/lib/retrieval-evaluation/ui";
import { cancelEvaluationRunAction } from "@/lib/retrieval-evaluation/actions";
import { PageHeader, Card, Section, Alert, EmptyState, Button, TextInput } from "@noor/ui";

export const dynamic = "force-dynamic";

const K_VALUES = [1, 3, 5, 10];
const METRIC_BASES = ["precision", "recall", "hit_rate", "ndcg"];

export default async function RetrievalEvaluationRunDashboardPage({
  params,
  searchParams,
}: {
  params: Promise<{ datasetId: string; runId: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_READ_RESULTS);
  const { datasetId, runId } = await params;
  const { error } = await searchParams;

  const dataset = await getRetrievalEvaluationDataset(datasetId);
  if (!dataset || dataset.organization_id !== context.organizationId) {
    notFound();
  }

  const detail = await getRetrievalEvaluationRunDetail(runId);
  if (!detail || detail.run.dataset_id !== datasetId) {
    notFound();
  }
  const { run, metrics } = detail;

  const canCancel = run.status === "running" && context.permissionKeys.includes(PERMISSIONS.RETRIEVAL_EVALUATION_CANCEL_RUN);

  const scopeGroups = groupMetricsByScope(metrics);

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E1 — Evaluation Run Dashboard"
        title={`${run.retriever_name} v${run.retriever_version}`}
        description={LEXICAL_BASELINE_DISCLAIMER}
        actions={<RetrievalEvaluationRunStatusBadge status={run.status} />}
      />

      {error ? (
        <Alert tone="critical" title="Could not complete that action">
          {error}
        </Alert>
      ) : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href={`/quality/retrieval-evaluation/${datasetId}`}>
          ← Back to dataset
        </Link>
        <Link className="underline" href={`/quality/retrieval-evaluation/${datasetId}/runs/${runId}/failures`}>
          Open failure analysis
        </Link>
      </div>

      <Section title="Run identity">
        <Card>
          <dl className="grid gap-sm text-sm sm:grid-cols-2">
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Retrieval configuration version</dt>
              <dd className="text-body">{run.retrieval_configuration_version}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Query normalization version</dt>
              <dd className="text-body">{run.query_normalization_version}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Metric definition version</dt>
              <dd className="text-body">{run.metric_definition_version}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Evaluation runner version</dt>
              <dd className="text-body">{run.evaluation_runner_version}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Top-K values</dt>
              <dd className="text-body">{run.top_k_values.join(", ")}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Relevance threshold</dt>
              <dd className="text-body">{run.relevance_threshold} (grade ≥ this counts as a hit)</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Query count / result count</dt>
              <dd className="text-body">
                {run.query_count ?? "—"} / {run.result_count ?? "—"}
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
            <form action={cancelEvaluationRunAction} className="mt-sm flex flex-wrap items-end gap-xs border-t border-border pt-sm">
              <input type="hidden" name="datasetId" value={datasetId} />
              <input type="hidden" name="runId" value={runId} />
              <TextInput label="Cancellation reason" name="reason" required className="flex-1" />
              <Button type="submit" size="sm" variant="danger">
                Cancel run
              </Button>
            </form>
          ) : null}
        </Card>
      </Section>

      <Section title="Metrics" description="Precision/Recall/Hit Rate/nDCG at each K, plus MRR — negative-control queries are excluded from every scope below (see docs/domain/retrieval-metrics.md).">
        {metrics.length === 0 ? (
          <EmptyState title="No metrics yet" description={run.status === "running" ? "This run has not finished yet." : "This run produced no metric rows."} />
        ) : (
          <div className="flex flex-col gap-md">
            {scopeGroups.map((group) => (
              <Card key={`${group.scopeType}:${group.scopeValue ?? ""}`}>
                <p className="text-sm font-semibold text-ink">
                  {scopeLabel(group.scopeType)}
                  {group.scopeValue ? `: ${group.scopeValue}` : ""}
                </p>
                <div className="mt-xs overflow-x-auto">
                  <table className="w-full text-sm" style={{ fontVariantNumeric: "tabular-nums" }}>
                    <thead>
                      <tr className="text-left text-xs uppercase tracking-wide text-muted">
                        <th className="py-xxs pr-sm">Metric</th>
                        {K_VALUES.map((k) => (
                          <th key={k} className="py-xxs pr-sm">
                            K={k}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {METRIC_BASES.map((base) => (
                        <tr key={base} className="border-t border-border">
                          <td className="py-xxs pr-sm text-body">{METRIC_BASE_LABELS[base]}</td>
                          {K_VALUES.map((k) => (
                            <td key={k} className="py-xxs pr-sm font-mono text-xs text-body">
                              {formatMetric(group.byName[`${base}_at_${k}`])}
                            </td>
                          ))}
                        </tr>
                      ))}
                      <tr className="border-t border-border">
                        <td className="py-xxs pr-sm text-body">MRR</td>
                        <td className="py-xxs pr-sm font-mono text-xs text-body" colSpan={K_VALUES.length}>
                          {formatMetric(group.byName.mrr)}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <p className="mt-xxs text-xs text-muted">Sample size: {group.sampleSize ?? "—"} quer{group.sampleSize === 1 ? "y" : "ies"}</p>
              </Card>
            ))}
          </div>
        )}
      </Section>
    </main>
  );
}

interface ScopeGroup {
  scopeType: string;
  scopeValue: string | null;
  byName: Record<string, RetrievalEvaluationMetricRow | undefined>;
  sampleSize: number | null;
}

function groupMetricsByScope(metrics: RetrievalEvaluationMetricRow[]): ScopeGroup[] {
  const groups = new Map<string, ScopeGroup>();
  for (const metric of metrics) {
    const key = `${metric.scope_type}:${metric.scope_value ?? ""}`;
    let group = groups.get(key);
    if (!group) {
      group = { scopeType: metric.scope_type, scopeValue: metric.scope_value, byName: {}, sampleSize: metric.sample_size };
      groups.set(key, group);
    }
    group.byName[metric.metric_name] = metric;
  }
  // "overall" first, then language, category, difficulty — stable, legible ordering.
  const order = ["overall", "language", "category", "difficulty"];
  return Array.from(groups.values()).sort((a, b) => {
    const orderDiff = order.indexOf(a.scopeType) - order.indexOf(b.scopeType);
    if (orderDiff !== 0) return orderDiff;
    return (a.scopeValue ?? "").localeCompare(b.scopeValue ?? "");
  });
}

function scopeLabel(scopeType: string): string {
  switch (scopeType) {
    case "overall":
      return "Overall";
    case "language":
      return "By language";
    case "category":
      return "By category";
    case "difficulty":
      return "By difficulty";
    default:
      return scopeType;
  }
}

function formatMetric(row: RetrievalEvaluationMetricRow | undefined): string {
  if (!row) return "—";
  return row.metric_value.toFixed(3);
}
