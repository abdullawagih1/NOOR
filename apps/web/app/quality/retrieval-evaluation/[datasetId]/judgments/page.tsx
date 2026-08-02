import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getRetrievalEvaluationDatasetDetail } from "@/lib/retrieval-evaluation/queries";
import { RetrievalEvaluationDatasetStatusBadge, RelevanceGradeBadge, QUERY_CATEGORY_LABELS } from "@/lib/retrieval-evaluation/ui";
import { createRelevanceJudgmentAction, updateRelevanceJudgmentAction } from "@/lib/retrieval-evaluation/actions";
import { PageHeader, Card, Section, Badge, Select, TextInput, Button, Alert, EmptyState } from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function RetrievalEvaluationJudgmentsPage({
  params,
  searchParams,
}: {
  params: Promise<{ datasetId: string }>;
  searchParams: Promise<{ error?: string; query?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_READ);
  const { datasetId } = await params;
  const { error, query: queryFilter } = await searchParams;

  const detail = await getRetrievalEvaluationDatasetDetail(datasetId);
  if (!detail || detail.dataset.organization_id !== context.organizationId) {
    notFound();
  }
  const { dataset, corpusItems, queries, judgments, judgmentCoverage } = detail;

  const isDraft = dataset.status === "draft";
  const canEdit = isDraft && context.permissionKeys.includes(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);

  const judgmentByPair = new Map(judgments.map((j) => [`${j.query_id}:${j.corpus_item_id}`, j]));

  const visibleQueries = queryFilter ? queries.filter((q) => q.id === queryFilter) : queries;

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E1 — Relevance Judgment Workspace"
        title={`Judgments — ${dataset.title} (v${dataset.version})`}
        description="Graded 0–3 relevance judgments per query/corpus-item pair — a technical lexical-relevance judgment, never a clinical review. Only editable while the dataset is a draft."
        actions={<RetrievalEvaluationDatasetStatusBadge status={dataset.status} />}
      />

      {error ? (
        <Alert tone="critical" title="Could not complete that action">
          {error}
        </Alert>
      ) : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href={`/quality/retrieval-evaluation/${dataset.id}`}>
          ← Back to dataset
        </Link>
        {queryFilter ? (
          <Link className="underline" href={`/quality/retrieval-evaluation/${dataset.id}/judgments`}>
            Clear query filter
          </Link>
        ) : null}
      </div>

      <Section title="Freeze readiness">
        <Card>
          <p className="text-sm text-body">
            {judgmentCoverage.judgedQueryCount}/{judgmentCoverage.gatingQueryCount} active, non-negative-control queries have at least one grade ≥ 2 (relevant) judgment. This coverage gates whether{" "}
            <code>freeze_retrieval_evaluation_dataset</code> will succeed.
          </p>
          {judgmentCoverage.unjudgedQueryKeys.length > 0 ? (
            <Alert tone="warning" title="Queries still missing a relevant judgment" className="mt-sm">
              {judgmentCoverage.unjudgedQueryKeys.join(", ")}
            </Alert>
          ) : (
            <p className="mt-sm text-sm text-body">Every gating query has at least one relevant judgment.</p>
          )}
          {judgmentCoverage.negativeControlFalsePositiveKeys.length > 0 ? (
            <Alert tone="critical" title="Negative-control queries with a positive judgment" className="mt-sm">
              {judgmentCoverage.negativeControlFalsePositiveKeys.join(", ")} — negative controls must have no grade ≥ 2 judgment before freezing.
            </Alert>
          ) : null}
        </Card>
      </Section>

      {corpusItems.length === 0 || queries.length === 0 ? (
        <EmptyState title="Nothing to judge yet" description="Add at least one corpus item and one query on the dataset detail page first." />
      ) : (
        <div className="flex flex-col gap-md">
          {visibleQueries.map((q) => (
            <Section key={q.id} title={q.query_key} description={`${q.query_text} — ${QUERY_CATEGORY_LABELS[q.category]}${q.is_negative_control ? " · negative control" : ""}`}>
              <div className="flex flex-col gap-xs">
                {corpusItems.map((item) => {
                  const judgment = judgmentByPair.get(`${q.id}:${item.id}`);
                  return (
                    <Card key={item.id} className="!p-sm">
                      <div className="flex flex-wrap items-center justify-between gap-xs">
                        <div>
                          <p className="font-mono text-xs text-ink">{item.chunk_checksum.slice(0, 16)}</p>
                          <p className="text-xs text-muted">
                            Page {item.page_number} · {item.representation_type}
                          </p>
                          {judgment?.rationale ? <p className="mt-xxs text-xs text-body">{judgment.rationale}</p> : null}
                        </div>
                        <div className="flex items-center gap-xs">
                          {judgment ? <RelevanceGradeBadge grade={judgment.relevance_grade} /> : <Badge>Unjudged</Badge>}
                        </div>
                      </div>
                      {canEdit ? (
                        <form action={judgment ? updateRelevanceJudgmentAction : createRelevanceJudgmentAction} className="mt-xs flex flex-wrap items-end gap-xs border-t border-border pt-xs">
                          <input type="hidden" name="datasetId" value={dataset.id} />
                          {judgment ? <input type="hidden" name="judgmentId" value={judgment.id} /> : null}
                          {!judgment ? (
                            <>
                              <input type="hidden" name="queryId" value={q.id} />
                              <input type="hidden" name="corpusItemId" value={item.id} />
                            </>
                          ) : null}
                          <Select label="Grade" name="relevanceGrade" defaultValue={String(judgment?.relevance_grade ?? 2)}>
                            <option value="0">0 — Not relevant</option>
                            <option value="1">1 — Marginally relevant</option>
                            <option value="2">2 — Relevant</option>
                            <option value="3">3 — Highly relevant</option>
                          </Select>
                          <TextInput label="Rationale" name="rationale" defaultValue={judgment?.rationale ?? ""} className="flex-1" />
                          <Button type="submit" size="sm" variant="secondary">
                            {judgment ? "Update" : "Save"}
                          </Button>
                        </form>
                      ) : null}
                    </Card>
                  );
                })}
              </div>
            </Section>
          ))}
        </div>
      )}
    </main>
  );
}
