import { notFound } from "next/navigation";
import Link from "next/link";
import { SemanticStatusBadge } from "@noor/ui";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import {
  getRetrievalEvaluationDataset,
  getRetrievalEvaluationRun,
  listRetrievalEvaluationRuns,
  listEvaluationMetrics,
  type RetrievalEvaluationRunRow,
  type MetricName,
} from "@/lib/retrieval-evaluation/queries";
import { PageHeader, Card, Section, EmptyState } from "@noor/ui";

export const dynamic = "force-dynamic";

const K_VALUES = [1, 3, 5, 10];
const METRIC_BASES = ["precision", "recall", "hit_rate", "ndcg"];
const DELTA_EPSILON = 0.0005;

export default async function RetrievalEvaluationComparisonPage({
  params,
}: {
  params: Promise<{ datasetId: string; runId: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_READ_RESULTS);
  const { datasetId, runId } = await params;

  const dataset = await getRetrievalEvaluationDataset(datasetId);
  if (!dataset || dataset.organization_id !== context.organizationId) {
    notFound();
  }

  const run = await getRetrievalEvaluationRun(runId);
  if (!run || run.dataset_id !== datasetId) {
    notFound();
  }

  const allRuns = await listRetrievalEvaluationRuns(datasetId);
  const lexicalRun = mostRecentSucceeded(allRuns, "noor-lexical-baseline");
  const vectorRun = mostRecentSucceeded(allRuns, "noor-vector-baseline");

  const canCompare = lexicalRun && vectorRun;

  const [lexicalMetrics, vectorMetrics] = canCompare
    ? await Promise.all([listEvaluationMetrics(lexicalRun!.id), listEvaluationMetrics(vectorRun!.id)])
    : [[], []];

  const lexicalOverall = new Map(lexicalMetrics.filter((m) => m.scope_type === "overall").map((m) => [m.metric_name, m.metric_value]));
  const vectorOverall = new Map(vectorMetrics.filter((m) => m.scope_type === "overall").map((m) => [m.metric_name, m.metric_value]));

  const rows: { name: string; lexical: number | undefined; vector: number | undefined }[] = [];
  for (const base of METRIC_BASES) {
    for (const k of K_VALUES) {
      const name = `${base}_at_${k}` as MetricName;
      rows.push({ name, lexical: lexicalOverall.get(name), vector: vectorOverall.get(name) });
    }
  }
  rows.push({ name: "mrr", lexical: lexicalOverall.get("mrr"), vector: vectorOverall.get("mrr") });

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E2 — Lexical vs. Vector Comparison"
        title={`Comparison — ${dataset.title} (v${dataset.version})`}
        description="Overall-scope retrieval-quality metrics side by side for the most recent succeeded run of each retriever against this dataset. Never a proxy for which retriever is 'better' in production — a controlled research comparison only."
      />

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href={`/quality/retrieval-evaluation/${datasetId}/runs/${runId}`}>
          ← Back to run dashboard
        </Link>
      </div>

      {!canCompare ? (
        <EmptyState
          title="Not enough runs to compare yet"
          description={
            !lexicalRun && !vectorRun
              ? "This dataset needs a succeeded noor-lexical-baseline run and a succeeded noor-vector-baseline run before they can be compared."
              : !lexicalRun
                ? "This dataset needs a succeeded noor-lexical-baseline run before it can be compared against the vector baseline."
                : "This dataset needs a succeeded noor-vector-baseline run before it can be compared against the lexical baseline."
          }
        />
      ) : (
        <Section title="Overall metrics">
          <Card>
            <div className="mb-sm flex flex-wrap gap-md text-xs text-muted">
              <span>Lexical run: {new Date(lexicalRun!.created_at).toLocaleString()}</span>
              <span>Vector run: {new Date(vectorRun!.created_at).toLocaleString()}</span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm" style={{ fontVariantNumeric: "tabular-nums" }}>
                <thead>
                  <tr className="text-left text-xs uppercase tracking-wide text-muted">
                    <th className="py-xxs pr-sm">Metric</th>
                    <th className="py-xxs pr-sm">Lexical</th>
                    <th className="py-xxs pr-sm">Vector</th>
                    <th className="py-xxs pr-sm">Delta (vector − lexical)</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => {
                    const delta = row.lexical !== undefined && row.vector !== undefined ? row.vector - row.lexical : undefined;
                    return (
                      <tr key={row.name} className="border-t border-border">
                        <td className="py-xxs pr-sm text-body">{row.name}</td>
                        <td className="py-xxs pr-sm font-mono text-xs text-body">{format(row.lexical)}</td>
                        <td className="py-xxs pr-sm font-mono text-xs text-body">{format(row.vector)}</td>
                        <td className="py-xxs pr-sm">
                          <DeltaBadge delta={delta} />
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>
        </Section>
      )}
    </main>
  );
}

function mostRecentSucceeded(runs: RetrievalEvaluationRunRow[], retrieverName: string): RetrievalEvaluationRunRow | null {
  const candidates = runs.filter((r) => r.retriever_name === retrieverName && r.status === "succeeded");
  if (candidates.length === 0) return null;
  return candidates.reduce((latest, r) => (new Date(r.created_at) > new Date(latest.created_at) ? r : latest));
}

function format(value: number | undefined): string {
  return value === undefined ? "—" : value.toFixed(3);
}

function DeltaBadge({ delta }: { delta: number | undefined }) {
  if (delta === undefined) return <span className="font-mono text-xs text-muted">—</span>;
  if (delta > DELTA_EPSILON) {
    return <SemanticStatusBadge state="verified" labelOverride={`+${delta.toFixed(3)}`} />;
  }
  if (delta < -DELTA_EPSILON) {
    return <SemanticStatusBadge state="critical" labelOverride={delta.toFixed(3)} />;
  }
  return <SemanticStatusBadge state="informational" labelOverride={delta.toFixed(3)} />;
}
