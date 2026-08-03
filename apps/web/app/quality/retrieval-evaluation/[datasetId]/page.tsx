import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import {
  getRetrievalEvaluationDatasetDetail,
  listRetrievalEvaluationRuns,
  QUERY_CATEGORIES,
  QUERY_DIFFICULTIES,
  RETRIEVAL_EVALUATION_LANGUAGES,
  type RetrievalEvaluationCorpusItemRow,
} from "@/lib/retrieval-evaluation/queries";
import {
  RetrievalEvaluationDatasetStatusBadge,
  RetrievalEvaluationRunStatusBadge,
  QUERY_CATEGORY_LABELS,
  QUERY_DIFFICULTY_LABELS,
  RETRIEVAL_EVALUATION_LANGUAGE_LABELS,
} from "@/lib/retrieval-evaluation/ui";
import {
  updateRetrievalEvaluationDatasetAction,
  submitDatasetForReviewAction,
  returnDatasetToDraftAction,
  markDatasetReviewedAction,
  freezeDatasetAction,
  archiveDatasetAction,
  addCorpusItemAction,
  removeCorpusItemAction,
  createEvaluationQueryAction,
  createEvaluationRunAction,
  createQueryEmbeddingsForDatasetAction,
  createVectorEvaluationRunAction,
} from "@/lib/retrieval-evaluation/actions";
import { PageHeader, Card, Section, Badge, TextInput, Textarea, Select, Checkbox, Button, Alert, EmptyState } from "@noor/ui";

export const dynamic = "force-dynamic";

export default async function RetrievalEvaluationDatasetDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ datasetId: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_READ);
  const { datasetId } = await params;
  const { error } = await searchParams;

  const detail = await getRetrievalEvaluationDatasetDetail(datasetId);
  if (!detail || detail.dataset.organization_id !== context.organizationId) {
    notFound();
  }
  const { dataset, corpusItems, queries, judgments, judgmentCoverage } = detail;
  const runs = await listRetrievalEvaluationRuns(datasetId);

  const has = (p: string) => context.permissionKeys.includes(p);
  const isCreator = context.userId === dataset.created_by;
  const isDraft = dataset.status === "draft";
  const isReadyForReview = dataset.status === "ready_for_review";
  const isFrozen = dataset.status === "frozen";

  const canEdit = isDraft && has(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET);
  const canReview = isReadyForReview && has(PERMISSIONS.RETRIEVAL_EVALUATION_REVIEW_DATASET);
  const canFreeze = isReadyForReview && has(PERMISSIONS.RETRIEVAL_EVALUATION_FREEZE_DATASET);
  const canArchive = isFrozen && has(PERMISSIONS.RETRIEVAL_EVALUATION_ARCHIVE_DATASET);
  const canRun = isFrozen && has(PERMISSIONS.RETRIEVAL_EVALUATION_RUN);

  const judgmentCountByQuery = new Map<string, number>();
  for (const j of judgments) judgmentCountByQuery.set(j.query_id, (judgmentCountByQuery.get(j.query_id) ?? 0) + 1);

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E1 — Retrieval Evaluation Dataset"
        title={`${dataset.title} (v${dataset.version})`}
        description={dataset.no_clinical_use_notice}
        actions={<RetrievalEvaluationDatasetStatusBadge status={dataset.status} />}
      />

      {error ? (
        <Alert tone="critical" title="Could not complete that action">
          {error}
        </Alert>
      ) : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href="/quality/retrieval-evaluation">
          ← Back to datasets
        </Link>
        <span className="font-mono text-xs text-muted">
          {dataset.logical_name} · schema {dataset.dataset_schema_version} · normalization {dataset.normalization_version}
        </span>
      </div>

      <Section title="Dataset metadata">
        <Card>
          <dl className="grid gap-sm text-sm sm:grid-cols-2">
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Domain scope</dt>
              <dd className="text-body">{dataset.domain_scope ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Purpose</dt>
              <dd className="text-body">{dataset.purpose ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Language scope</dt>
              <dd className="text-body">{dataset.language_scope.length > 0 ? dataset.language_scope.map((l) => RETRIEVAL_EVALUATION_LANGUAGE_LABELS[l] ?? l).join(", ") : "—"}</dd>
            </div>
            <div>
              <dt className="text-xs uppercase tracking-wide text-muted">Description</dt>
              <dd className="text-body">{dataset.description ?? "—"}</dd>
            </div>
            {dataset.return_to_draft_reason ? (
              <div className="sm:col-span-2">
                <dt className="text-xs uppercase tracking-wide text-muted">Last returned to draft because</dt>
                <dd className="text-body">{dataset.return_to_draft_reason}</dd>
              </div>
            ) : null}
            {isFrozen || dataset.status === "archived" ? (
              <>
                <div className="sm:col-span-2">
                  <dt className="text-xs uppercase tracking-wide text-muted">Dataset checksum</dt>
                  <dd className="font-mono text-xs text-body">{dataset.dataset_sha256}</dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-muted">Frozen at</dt>
                  <dd className="text-body">{dataset.frozen_at ? new Date(dataset.frozen_at).toLocaleString() : "—"}</dd>
                </div>
              </>
            ) : null}
          </dl>
        </Card>
      </Section>

      {isDraft ? (
        <Section title="Corpus items" description="A dataset needs at least one corpus item before it can be submitted for review.">
          {canEdit ? (
            <Card>
              <p className="text-xs font-semibold uppercase tracking-wide text-muted">Add corpus item</p>
              <form action={addCorpusItemAction} className="mt-xs flex flex-wrap items-end gap-xs">
                <input type="hidden" name="datasetId" value={dataset.id} />
                <TextInput label="Chunk ID" name="chunkId" required hint="Must be embedding-ready in this organization" className="flex-1" />
                <Button type="submit" size="sm" variant="secondary">
                  Add
                </Button>
              </form>
            </Card>
          ) : null}
          <CorpusItemList corpusItems={corpusItems} canEdit={canEdit} datasetId={dataset.id} />
        </Section>
      ) : (
        <Section title="Corpus items" description={`${corpusItems.length} item${corpusItems.length === 1 ? "" : "s"}`}>
          <CorpusItemList corpusItems={corpusItems} canEdit={false} datasetId={dataset.id} />
        </Section>
      )}

      <Section
        title="Queries"
        description={`${queries.length} quer${queries.length === 1 ? "y" : "ies"} · judgment coverage: ${judgmentCoverage.judgedQueryCount}/${judgmentCoverage.gatingQueryCount} gating queries judged`}
      >
        {isDraft && canEdit ? (
          <Card>
            <p className="text-xs font-semibold uppercase tracking-wide text-muted">Add query</p>
            <form action={createEvaluationQueryAction} className="mt-xs grid gap-sm sm:grid-cols-2">
              <input type="hidden" name="datasetId" value={dataset.id} />
              <TextInput label="Query key" name="queryKey" required placeholder="e.g. q-001" />
              <Select label="Language" name="language" required defaultValue="en">
                {RETRIEVAL_EVALUATION_LANGUAGES.map((lang) => (
                  <option key={lang} value={lang}>
                    {RETRIEVAL_EVALUATION_LANGUAGE_LABELS[lang]}
                  </option>
                ))}
              </Select>
              <Textarea label="Query text" name="queryText" required className="sm:col-span-2" />
              <Select label="Category" name="category" required defaultValue="keyword_lookup">
                {QUERY_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {QUERY_CATEGORY_LABELS[c]}
                  </option>
                ))}
              </Select>
              <Select label="Difficulty" name="difficulty" required defaultValue="basic">
                {QUERY_DIFFICULTIES.map((d) => (
                  <option key={d} value={d}>
                    {QUERY_DIFFICULTY_LABELS[d]}
                  </option>
                ))}
              </Select>
              <TextInput label="Intent note" name="intentNote" />
              <TextInput label="Expected source scope" name="expectedSourceScope" />
              <Checkbox label="Negative control (must use category = negative_control)" name="isNegativeControl" />
              <div className="sm:col-span-2">
                <Button type="submit" size="sm" variant="secondary">
                  Add query
                </Button>
              </div>
            </form>
          </Card>
        ) : null}

        {queries.length === 0 ? (
          <EmptyState title="No queries yet" description="Add at least one active query before this dataset can be submitted for review." />
        ) : (
          <div className="flex flex-col gap-sm">
            {queries.map((q) => {
              const judgedCount = judgmentCountByQuery.get(q.id) ?? 0;
              return (
                <Card key={q.id}>
                  <div className="flex flex-wrap items-start justify-between gap-xs">
                    <div>
                      <p className="text-sm font-semibold text-ink">
                        {q.query_key} {q.is_negative_control ? <Badge>Negative control</Badge> : null} {!q.active ? <Badge>Inactive</Badge> : null}
                      </p>
                      <p className="text-sm text-body">{q.query_text}</p>
                      <p className="text-xs text-muted">
                        {RETRIEVAL_EVALUATION_LANGUAGE_LABELS[q.language] ?? q.language} · {QUERY_CATEGORY_LABELS[q.category]} · {QUERY_DIFFICULTY_LABELS[q.difficulty]} · {judgedCount} judgment
                        {judgedCount === 1 ? "" : "s"}
                      </p>
                    </div>
                    <Link className="text-sm underline" href={`/quality/retrieval-evaluation/${dataset.id}/judgments?query=${q.id}`}>
                      Judge relevance
                    </Link>
                  </div>
                </Card>
              );
            })}
          </div>
        )}
      </Section>

      <Section title="Lifecycle actions">
        <Card>
          {isDraft ? (
            <div className="flex flex-col gap-sm">
              {canEdit ? (
                <form action={updateRetrievalEvaluationDatasetAction} className="grid gap-sm sm:grid-cols-2">
                  <input type="hidden" name="datasetId" value={dataset.id} />
                  <TextInput label="Title" name="title" defaultValue={dataset.title} className="sm:col-span-2" />
                  <Textarea label="Description" name="description" defaultValue={dataset.description ?? ""} className="sm:col-span-2" />
                  <TextInput label="Domain scope" name="domainScope" defaultValue={dataset.domain_scope ?? ""} />
                  <TextInput label="Purpose" name="purpose" defaultValue={dataset.purpose ?? ""} />
                  <div className="sm:col-span-2">
                    <Button type="submit" size="sm" variant="secondary">
                      Save changes
                    </Button>
                  </div>
                </form>
              ) : null}
              {has(PERMISSIONS.RETRIEVAL_EVALUATION_EDIT_DATASET) ? (
                <form action={submitDatasetForReviewAction}>
                  <input type="hidden" name="datasetId" value={dataset.id} />
                  <Button type="submit" size="sm">
                    Submit for review
                  </Button>
                </form>
              ) : null}
            </div>
          ) : null}

          {isReadyForReview ? (
            <div className="flex flex-col gap-sm">
              {isCreator ? (
                <Alert tone="warning" title="You cannot review your own dataset">
                  You created this dataset. The two-person rule (ADR 0015) requires a different reviewer to mark it reviewed before it can be frozen.
                </Alert>
              ) : null}
              {dataset.reviewed_by ? <p className="text-sm text-body">Reviewed at {dataset.reviewed_at ? new Date(dataset.reviewed_at).toLocaleString() : "—"}.</p> : <p className="text-sm text-muted">Not yet reviewed.</p>}
              <div className="flex flex-wrap gap-sm">
                {canReview && !isCreator ? (
                  <form action={markDatasetReviewedAction}>
                    <input type="hidden" name="datasetId" value={dataset.id} />
                    <Button type="submit" size="sm">
                      Mark reviewed
                    </Button>
                  </form>
                ) : null}
                {canReview ? (
                  <form action={returnDatasetToDraftAction} className="flex flex-1 items-end gap-xs">
                    <input type="hidden" name="datasetId" value={dataset.id} />
                    <TextInput label="Return-to-draft reason" name="reason" required className="flex-1" />
                    <Button type="submit" size="sm" variant="secondary">
                      Return to draft
                    </Button>
                  </form>
                ) : null}
              </div>
              {canFreeze ? (
                <form action={freezeDatasetAction}>
                  <input type="hidden" name="datasetId" value={dataset.id} />
                  <Button type="submit" size="sm" disabled={!dataset.reviewed_by || dataset.reviewed_by === dataset.created_by}>
                    Freeze dataset
                  </Button>
                </form>
              ) : null}
            </div>
          ) : null}

          {isFrozen ? (
            <div className="flex flex-col gap-sm">
              <p className="text-sm text-body">This dataset is frozen and immutable — corpus items, queries, and judgments can no longer change.</p>
              {canRun ? (
                <form action={createEvaluationRunAction} className="flex flex-wrap items-end gap-xs">
                  <input type="hidden" name="datasetId" value={dataset.id} />
                  <TextInput label="Top-K values" name="topKValues" defaultValue="1,3,5,10" hint="Comma-separated" />
                  <TextInput label="Relevance threshold" name="relevanceThreshold" type="number" min={0} max={3} defaultValue={2} />
                  <Button type="submit" size="sm">
                    Run evaluation
                  </Button>
                </form>
              ) : null}
              {canRun ? (
                <div className="flex flex-col gap-sm border-t border-border pt-sm">
                  <p className="text-sm text-body">
                    Sprint 1-E2 — vector baseline (noor-vector-baseline). Query embeddings must be generated before a vector evaluation run can succeed; a run also requires every corpus item to have a succeeded chunk
                    embedding at the approved configuration.
                  </p>
                  <form action={createQueryEmbeddingsForDatasetAction} className="flex flex-wrap items-end gap-xs">
                    <input type="hidden" name="datasetId" value={dataset.id} />
                    <Button type="submit" size="sm" variant="secondary">
                      Generate query embeddings
                    </Button>
                  </form>
                  <form action={createVectorEvaluationRunAction} className="flex flex-wrap items-end gap-xs">
                    <input type="hidden" name="datasetId" value={dataset.id} />
                    <TextInput label="Top-K values" name="topKValues" defaultValue="1,3,5,10" hint="Comma-separated" />
                    <TextInput label="Relevance threshold" name="relevanceThreshold" type="number" min={0} max={3} defaultValue={2} />
                    <Button type="submit" size="sm">
                      Run vector evaluation
                    </Button>
                  </form>
                </div>
              ) : null}
              {canArchive ? (
                <form action={archiveDatasetAction}>
                  <input type="hidden" name="datasetId" value={dataset.id} />
                  <Button type="submit" size="sm" variant="danger">
                    Archive dataset
                  </Button>
                </form>
              ) : null}
            </div>
          ) : null}

          {dataset.status === "archived" ? <p className="text-sm text-muted">This dataset is archived and immutable.</p> : null}
        </Card>
      </Section>

      <Section title="Evaluation runs" description={`${runs.length} run${runs.length === 1 ? "" : "s"}`}>
        {runs.length === 0 ? (
          <EmptyState title="No evaluation runs yet" description={isFrozen ? "Run the deterministic lexical baseline against this frozen dataset." : "Evaluation runs require a frozen dataset."} />
        ) : (
          <div className="flex flex-col gap-sm">
            {runs.map((run) => (
              <Card key={run.id}>
                <div className="flex flex-wrap items-center justify-between gap-xs">
                  <div>
                    <p className="text-sm font-semibold text-ink">
                      {run.retriever_name} v{run.retriever_version}
                    </p>
                    <p className="text-xs text-muted">
                      {new Date(run.created_at).toLocaleString()} · top-K {run.top_k_values.join(", ")} · threshold {run.relevance_threshold}
                    </p>
                  </div>
                  <RetrievalEvaluationRunStatusBadge status={run.status} />
                </div>
                <div className="mt-sm">
                  <Link className="text-sm underline" href={`/quality/retrieval-evaluation/${dataset.id}/runs/${run.id}`}>
                    Open run dashboard
                  </Link>
                </div>
              </Card>
            ))}
          </div>
        )}
      </Section>
    </main>
  );
}

function CorpusItemList({
  corpusItems,
  canEdit,
  datasetId,
}: {
  corpusItems: RetrievalEvaluationCorpusItemRow[];
  canEdit: boolean;
  datasetId: string;
}) {
  if (corpusItems.length === 0) {
    return <EmptyState title="No corpus items yet" description="Add at least one embedding-ready chunk before this dataset can be submitted for review." />;
  }
  return (
    <div className="flex flex-col gap-xs">
      {corpusItems.map((item) => (
        <Card key={item.id} className="!p-sm">
          <div className="flex flex-wrap items-center justify-between gap-xs text-sm">
            <div>
              <p className="font-mono text-xs text-ink">{item.chunk_checksum.slice(0, 16)}</p>
              <p className="text-xs text-muted">
                Page {item.page_number} · {item.representation_type} · order {item.display_order}
                {item.warning_state ? " · has warnings" : ""}
              </p>
            </div>
            {canEdit ? (
              <form action={removeCorpusItemAction}>
                <input type="hidden" name="datasetId" value={datasetId} />
                <input type="hidden" name="corpusItemId" value={item.id} />
                <Button type="submit" size="sm" variant="danger">
                  Remove
                </Button>
              </form>
            ) : null}
          </div>
        </Card>
      ))}
    </div>
  );
}
