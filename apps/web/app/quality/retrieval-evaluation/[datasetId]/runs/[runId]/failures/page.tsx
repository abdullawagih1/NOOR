import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getRetrievalEvaluationDataset, getRetrievalEvaluationRunDetail, listEvaluationQueries, FAILURE_CATEGORIES } from "@/lib/retrieval-evaluation/queries";
import { RetrievalEvaluationRunStatusBadge, RetrievalEvaluationFailureStatusBadge, FAILURE_CATEGORY_LABELS } from "@/lib/retrieval-evaluation/ui";
import { createFailureAnnotationAction, updateFailureAnnotationAction } from "@/lib/retrieval-evaluation/actions";
import { PageHeader, Card, Section, Badge, Select, TextInput, Textarea, Button, Alert, EmptyState } from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function RetrievalEvaluationFailureAnalysisPage({
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
  const { run, failures } = detail;
  const queries = await listEvaluationQueries(datasetId);
  const queryByid = new Map(queries.map((q) => [q.id, q]));

  const canAnnotate = context.permissionKeys.includes(PERMISSIONS.RETRIEVAL_EVALUATION_ANNOTATE_FAILURES);

  const systemFailures = failures.filter((f) => f.source === "system");
  const humanFailures = failures.filter((f) => f.source === "human");

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E1 — Retrieval Failure Analysis"
        title={`Failure analysis — ${run.retriever_name} v${run.retriever_version}`}
        description="System-detected failures (deterministic rules, no model judgment) alongside human review annotations. A clean run proves no detectable symptom against this baseline — never that retrieval is 'good' in any absolute sense."
        actions={<RetrievalEvaluationRunStatusBadge status={run.status} />}
      />

      {error ? (
        <Alert tone="critical" title="Could not complete that action">
          {error}
        </Alert>
      ) : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href={`/quality/retrieval-evaluation/${datasetId}/runs/${runId}`}>
          ← Back to run dashboard
        </Link>
      </div>

      <Section title="System-detected failures" description={`${systemFailures.length} detected`}>
        {systemFailures.length === 0 ? (
          <EmptyState title="No system-detected failures" description="Every evaluated query cleared every deterministic detector for this run." />
        ) : (
          <FailureList failures={systemFailures} queryByid={queryByid} datasetId={datasetId} runId={runId} canAnnotate={canAnnotate} />
        )}
      </Section>

      <Section title="Human review annotations" description={`${humanFailures.length} annotation${humanFailures.length === 1 ? "" : "s"}`}>
        {canAnnotate ? (
          <Card>
            <p className="text-xs font-semibold uppercase tracking-wide text-muted">Add annotation</p>
            <form action={createFailureAnnotationAction} className="mt-xs grid gap-sm sm:grid-cols-2">
              <input type="hidden" name="datasetId" value={datasetId} />
              <input type="hidden" name="runId" value={runId} />
              <Select label="Query" name="queryId" required>
                {queries.map((q) => (
                  <option key={q.id} value={q.id}>
                    {q.query_key}
                  </option>
                ))}
              </Select>
              <Select label="Failure category" name="failureCategory" required defaultValue="other">
                {FAILURE_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {FAILURE_CATEGORY_LABELS[c]}
                  </option>
                ))}
              </Select>
              <Textarea label="Reviewer note" name="reviewerNote" className="sm:col-span-2" />
              <Textarea label="Recommended experiment" name="recommendedExperiment" className="sm:col-span-2" />
              <div className="sm:col-span-2">
                <Button type="submit" size="sm" variant="secondary">
                  Add annotation
                </Button>
              </div>
            </form>
          </Card>
        ) : null}

        {humanFailures.length === 0 ? (
          <EmptyState title="No human annotations yet" description="A reviewer can annotate categories a deterministic rule cannot safely detect (tokenization, tie-break, judgment-gap, corpus-gap, other)." />
        ) : (
          <FailureList failures={humanFailures} queryByid={queryByid} datasetId={datasetId} runId={runId} canAnnotate={canAnnotate} />
        )}
      </Section>
    </main>
  );
}

function FailureList({
  failures,
  queryByid,
  datasetId,
  runId,
  canAnnotate,
}: {
  failures: import("@/lib/retrieval-evaluation/queries").RetrievalEvaluationFailureRow[];
  queryByid: Map<string, import("@/lib/retrieval-evaluation/queries").RetrievalEvaluationQueryRow>;
  datasetId: string;
  runId: string;
  canAnnotate: boolean;
}) {
  return (
    <div className="flex flex-col gap-xs">
      {failures.map((failure) => {
        const query = queryByid.get(failure.query_id);
        return (
          <Card key={failure.id} className="!p-sm">
            <div className="flex flex-wrap items-start justify-between gap-xs">
              <div>
                <p className="text-sm font-semibold text-ink">
                  {FAILURE_CATEGORY_LABELS[failure.failure_category]} <Badge>{failure.source === "system" ? "System" : "Human"}</Badge>
                </p>
                <p className="text-xs text-muted">Query: {query?.query_key ?? failure.query_id}</p>
                {failure.reviewer_note ? <p className="mt-xxs text-xs text-body">{failure.reviewer_note}</p> : null}
                {failure.recommended_experiment ? <p className="mt-xxs text-xs text-body">Recommended: {failure.recommended_experiment}</p> : null}
              </div>
              <RetrievalEvaluationFailureStatusBadge status={failure.status} />
            </div>
            {canAnnotate ? (
              <form action={updateFailureAnnotationAction} className="mt-xs flex flex-wrap items-end gap-xs border-t border-border pt-xs">
                <input type="hidden" name="datasetId" value={datasetId} />
                <input type="hidden" name="runId" value={runId} />
                <input type="hidden" name="failureId" value={failure.id} />
                <Select label="Status" name="status" defaultValue={failure.status}>
                  <option value="open">Open</option>
                  <option value="acknowledged">Acknowledged</option>
                  <option value="resolved">Resolved</option>
                </Select>
                <TextInput label="Reviewer note" name="reviewerNote" defaultValue={failure.reviewer_note ?? ""} className="flex-1" />
                <Button type="submit" size="sm" variant="secondary">
                  Update
                </Button>
              </form>
            ) : null}
          </Card>
        );
      })}
    </div>
  );
}
