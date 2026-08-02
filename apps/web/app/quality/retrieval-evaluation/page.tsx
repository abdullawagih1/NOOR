import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { listRetrievalEvaluationDatasets, RETRIEVAL_EVALUATION_LANGUAGES } from "@/lib/retrieval-evaluation/queries";
import { RetrievalEvaluationDatasetStatusBadge, RETRIEVAL_EVALUATION_LANGUAGE_LABELS } from "@/lib/retrieval-evaluation/ui";
import { createRetrievalEvaluationDatasetAction } from "@/lib/retrieval-evaluation/actions";
import { PageHeader, Card, EmptyState, Alert, TextInput, Textarea, Select, Checkbox, Button } from "@noor/ui";

export const dynamic = "force-dynamic";

const STATUS_FILTERS: Array<{ key: string; label: string }> = [
  { key: "", label: "All" },
  { key: "draft", label: "Draft" },
  { key: "ready_for_review", label: "Ready for review" },
  { key: "frozen", label: "Frozen" },
  { key: "archived", label: "Archived" },
];

export default async function RetrievalEvaluationQueuePage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; filter?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.RETRIEVAL_EVALUATION_READ);
  const { error, filter } = await searchParams;

  const allItems = await listRetrievalEvaluationDatasets(context.organizationId);
  const items = filter ? allItems.filter((i) => i.dataset.status === filter) : allItems;

  const canCreate = context.permissionKeys.includes(PERMISSIONS.RETRIEVAL_EVALUATION_CREATE_DATASET);

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Sprint 1-E1 — Retrieval Preparation and Evaluation Foundation"
        title="Retrieval Evaluation Datasets"
        description="Frozen evaluation corpora, versioned queries, and graded relevance judgments — the reproducible foundation every future retrieval approach (lexical, embedding, hybrid, reranked) is measured against. Synthetic content only, never real patient data — see ADR 0015."
      />

      {error ? (
        <Alert tone="critical" title="Could not complete that action">
          {error}
        </Alert>
      ) : null}

      <nav className="flex flex-wrap gap-xs text-xs" aria-label="Filter datasets by status">
        {STATUS_FILTERS.map((f) => (
          <Link
            key={f.key}
            href={f.key ? `/quality/retrieval-evaluation?filter=${f.key}` : "/quality/retrieval-evaluation"}
            className={`rounded-full border px-sm py-xxs ${filter === f.key || (!filter && !f.key) ? "border-ink bg-ink text-onPrimary" : "border-border text-muted"}`}
          >
            {f.label}
          </Link>
        ))}
      </nav>

      {canCreate ? (
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">New dataset</p>
          <form action={createRetrievalEvaluationDatasetAction} className="mt-xs grid gap-sm sm:grid-cols-2">
            <TextInput label="Logical name" name="logicalName" required placeholder="e.g. diabetes-guidelines-eval" />
            <TextInput label="Version" name="version" type="number" min={1} defaultValue={1} required />
            <TextInput label="Title" name="title" required className="sm:col-span-2" />
            <Textarea label="Description" name="description" className="sm:col-span-2" />
            <TextInput label="Domain scope" name="domainScope" placeholder="e.g. endocrinology" />
            <TextInput label="Purpose" name="purpose" />
            <fieldset className="sm:col-span-2">
              <legend className="text-sm font-medium text-body">Language scope</legend>
              <div className="mt-xxs flex gap-md">
                {RETRIEVAL_EVALUATION_LANGUAGES.map((lang) => (
                  <Checkbox key={lang} label={RETRIEVAL_EVALUATION_LANGUAGE_LABELS[lang]} name="languageScope" value={lang} />
                ))}
              </div>
            </fieldset>
            <div className="sm:col-span-2">
              <Button type="submit" size="sm">
                Create dataset
              </Button>
            </div>
          </form>
        </Card>
      ) : null}

      {items.length === 0 ? (
        <EmptyState title="No datasets" description="No retrieval evaluation datasets match this filter." />
      ) : (
        <div className="flex flex-col gap-md">
          {items.map(({ dataset, corpusItemCount, queryCount }) => (
            <Card key={dataset.id}>
              <div className="flex flex-wrap items-center justify-between gap-sm">
                <div>
                  <p className="text-base font-semibold text-ink">
                    {dataset.title} <span className="font-mono text-xs text-muted">v{dataset.version}</span>
                  </p>
                  <p className="text-sm text-muted">{dataset.logical_name}</p>
                  <p className="text-xs text-muted">
                    {corpusItemCount} corpus item{corpusItemCount === 1 ? "" : "s"} · {queryCount} quer{queryCount === 1 ? "y" : "ies"}
                  </p>
                </div>
                <RetrievalEvaluationDatasetStatusBadge status={dataset.status} />
              </div>
              <div className="mt-sm">
                <Link className="text-sm underline" href={`/quality/retrieval-evaluation/${dataset.id}`}>
                  Open dataset
                </Link>
              </div>
            </Card>
          ))}
        </div>
      )}
    </main>
  );
}
