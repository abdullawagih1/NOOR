import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import {
  getChunkingReview,
  getChunkingRun,
  listChunksForRun,
  listChunkReviews,
  listChunkFindings,
  CHUNK_FINDING_TYPES,
} from "@/lib/chunking/queries";
import {
  ChunkingReviewStatusBadge,
  ChunkingRunStatusBadge,
  ChunkReviewStatusBadge,
  ChunkFindingSeverityBadge,
  ChunkFindingStatusBadge,
  CHUNK_FINDING_TYPE_LABELS,
  CHUNK_TECHNICAL_REVIEW_CHECKLIST,
} from "@/lib/chunking/ui";
import {
  assignChunkingReviewerAction,
  claimChunkingReviewAction,
  startChunkingReviewAction,
  markChunkReviewedAction,
  createChunkFindingAction,
  updateChunkFindingStatusAction,
  submitChunkingReviewAction,
  reopenChunkingReviewAction,
  invalidateChunkingRunAction,
} from "@/lib/chunking/actions";
import { PageHeader, Card, Section, Badge, TextInput, Textarea, Select, Button, Alert } from "@noor/ui";

export const dynamic = "force-dynamic";

const ACTIVE_STATUSES = new Set(["pending_review", "in_review"]);
const TERMINAL_STATUSES = new Set(["accepted", "accepted_with_warnings", "rechunk_required", "rejected"]);

export default async function ChunkingReviewDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ chunkingReviewId: string }>;
  searchParams: Promise<{ error?: string; chunk?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_CHUNKING_READ);
  const { chunkingReviewId } = await params;
  const { error, chunk: chunkParam } = await searchParams;

  const review = await getChunkingReview(chunkingReviewId);
  if (!review || review.organization_id !== context.organizationId) {
    notFound();
  }

  const run = await getChunkingRun(review.chunking_run_id);
  if (!run) notFound();

  const [chunks, chunkReviews, findings] = await Promise.all([listChunksForRun(run.id), listChunkReviews(review.id), listChunkFindings(review.id)]);

  const currentChunkIndex = Math.max(1, Math.min(Number(chunkParam) || 1, chunks[0]?.chunk_index ?? 1));
  const currentChunk = chunks.find((c) => c.chunk_index === currentChunkIndex) ?? chunks[0];
  const currentChunkReview = chunkReviews.find((cr) => cr.chunk_index === currentChunkIndex);

  const has = (p: string) => context.permissionKeys.includes(p);
  const isAssignedReviewer = review.assigned_reviewer_id === context.userId;
  const canOverride = has(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW);
  const isActive = ACTIVE_STATUSES.has(review.review_status);
  const isTerminal = TERMINAL_STATUSES.has(review.review_status);
  const openCritical = findings.filter((f) => f.severity === "critical" && f.status === "open").length;
  const openMajor = findings.filter((f) => f.severity === "major" && f.status === "open").length;

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Technical Chunk Review — not a clinical review"
        title={`Chunking review round ${review.review_round}`}
        description="Checks chunk boundaries, provenance, and sizing before a document can become eligible for a future embedding step. Findings and decisions here never edit chunk text — chunks are immutable once created."
        actions={<ChunkingReviewStatusBadge status={review.review_status} />}
      />

      {error ? <Alert tone="critical" title="Could not complete that action">{error}</Alert> : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href="/reviewer/chunking">
          ← Back to queue
        </Link>
        <span className="text-muted">
          {review.chunks_reviewed}/{review.total_chunks} chunks reviewed
        </span>
        <ChunkingRunStatusBadge status={run.status} />
        <span className="font-mono text-xs text-muted">
          {run.tokenizer_name} {run.tokenizer_version} · pipeline {run.pipeline_version} · coverage {run.coverage_percentage ?? "—"}% · duplication {run.duplication_percentage ?? "—"}%
        </span>
      </div>

      {review.review_status === "pending_review" ? (
        <Card>
          <p className="text-sm text-body">
            {review.assigned_reviewer_id
              ? isAssignedReviewer
                ? "You are assigned to this review round."
                : "This round is assigned to another reviewer."
              : "This round is unassigned."}
          </p>
          <div className="mt-sm flex flex-wrap gap-sm">
            {!review.assigned_reviewer_id && has(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW) ? (
              <form action={claimChunkingReviewAction}>
                <input type="hidden" name="chunkingReviewId" value={review.id} />
                <Button type="submit" size="sm" variant="secondary">
                  Claim this review
                </Button>
              </form>
            ) : null}
            {(!review.assigned_reviewer_id || isAssignedReviewer) && has(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW) ? (
              <form action={startChunkingReviewAction}>
                <input type="hidden" name="chunkingReviewId" value={review.id} />
                <Button type="submit" size="sm">
                  Start review
                </Button>
              </form>
            ) : null}
          </div>
        </Card>
      ) : null}

      {isTerminal ? (
        <Card>
          <p className="text-sm font-semibold text-ink">Decision: {review.review_status.replace(/_/g, " ")}</p>
          {review.decision_reason ? <p className="mt-xs text-sm text-body">{review.decision_reason}</p> : null}
          {review.warning_summary ? <p className="mt-xs text-sm text-body">Warnings: {review.warning_summary}</p> : null}
          <div className="mt-sm flex flex-col gap-sm sm:flex-row sm:items-end">
            {has(PERMISSIONS.GUIDELINE_CHUNKING_REOPEN_REVIEW) ? (
              <form action={reopenChunkingReviewAction} className="flex flex-1 items-end gap-xs">
                <input type="hidden" name="chunkingReviewId" value={review.id} />
                <TextInput label="Reopen reason" name="reason" required hint="Required" className="flex-1" />
                <Button type="submit" size="sm" variant="secondary">
                  Reopen
                </Button>
              </form>
            ) : null}
            {has(PERMISSIONS.GUIDELINE_CHUNKING_INVALIDATE) && (review.review_status === "accepted" || review.review_status === "accepted_with_warnings") ? (
              <form action={invalidateChunkingRunAction} className="flex flex-1 items-end gap-xs">
                <input type="hidden" name="chunkingRunId" value={run.id} />
                <TextInput label="Invalidate reason" name="reason" required hint="Required" className="flex-1" />
                <Button type="submit" size="sm" variant="danger">
                  Invalidate run
                </Button>
              </form>
            ) : null}
          </div>
        </Card>
      ) : null}

      {review.review_status === "in_review" && currentChunk ? (
        <>
          <div className="flex flex-wrap items-center justify-between gap-xs">
            <p className="text-sm font-semibold text-ink">
              Chunk {currentChunkIndex} of {chunks.length} — page {currentChunk.page_start} · {currentChunk.token_count} tokens · {currentChunk.character_count} characters
            </p>
            <div className="flex items-center gap-xs">
              {currentChunkReview ? <ChunkReviewStatusBadge status={currentChunkReview.review_status} /> : <Badge>Unreviewed</Badge>}
              {currentChunk.warning_state ? <Badge>Warning</Badge> : null}
            </div>
          </div>
          <div className="flex flex-wrap gap-xs text-xs">
            {chunks.map((c) => {
              const cr = chunkReviews.find((x) => x.chunk_index === c.chunk_index);
              return (
                <Link
                  key={c.id}
                  href={`/reviewer/chunking/${review.id}?chunk=${c.chunk_index}`}
                  className={`rounded-full border px-xs py-xxs ${c.chunk_index === currentChunkIndex ? "border-ink bg-ink text-onPrimary" : "border-border text-muted"}`}
                >
                  {c.chunk_index}
                  {cr && cr.review_status !== "unreviewed" ? " ✓" : ""}
                </Link>
              );
            })}
          </div>

          <div className="grid gap-md lg:grid-cols-3">
            <div className="lg:col-span-2 flex min-h-[280px] flex-col rounded-sm border border-border bg-surface p-sm">
              <p className="mb-xxs text-xs font-semibold uppercase tracking-wide text-muted">Chunk text (page {currentChunk.page_start})</p>
              <p className="whitespace-pre-wrap text-sm text-body">{currentChunk.chunk_text}</p>
              {currentChunk.heading_context ? <p className="mt-xs text-xs text-muted">Heading context: {currentChunk.heading_context}</p> : null}
            </div>
            <div className="flex min-h-[280px] flex-col rounded-sm border border-border bg-surface p-sm">
              <p className="mb-xxs text-xs font-semibold uppercase tracking-wide text-muted">Provenance &amp; boundaries</p>
              <dl className="grid grid-cols-1 gap-y-xxs text-xs text-muted">
                <div>
                  <dt className="uppercase tracking-wide">Block types</dt>
                  <dd className="text-ink">{currentChunk.block_type_summary.join(", ") || "—"}</dd>
                </div>
                <div>
                  <dt className="uppercase tracking-wide">Boundary (start / end)</dt>
                  <dd className="text-ink">
                    {currentChunk.boundary_start_reason} / {currentChunk.boundary_end_reason}
                  </dd>
                </div>
                <div>
                  <dt className="uppercase tracking-wide">Source representation</dt>
                  <dd className="text-ink">{currentChunk.contains_native_text ? "Native" : currentChunk.contains_ocr_text ? "OCR" : "—"}</dd>
                </div>
                <div>
                  <dt className="uppercase tracking-wide">Checksum</dt>
                  <dd className="font-mono text-ink">{currentChunk.chunk_checksum.slice(0, 12)}</dd>
                </div>
              </dl>
              {currentChunk.warnings.length > 0 ? (
                <ul className="mt-xs text-xs text-warning">
                  {currentChunk.warnings.map((w) => (
                    <li key={w}>⚠ {w}</li>
                  ))}
                </ul>
              ) : null}
            </div>
          </div>

          {isAssignedReviewer ? (
            <Card>
              <form action={markChunkReviewedAction} className="flex flex-wrap items-end gap-xs">
                <input type="hidden" name="chunkingReviewId" value={review.id} />
                <input type="hidden" name="chunkIndex" value={currentChunkIndex} />
                <Select label="Mark chunk as" name="reviewStatus" defaultValue="reviewed_clear">
                  <option value="reviewed_clear">Reviewed — clear</option>
                  <option value="reviewed_with_findings">Reviewed — with findings</option>
                  <option value="rechunk_candidate">Rechunk candidate</option>
                  <option value="rejected">Rejected</option>
                </Select>
                <TextInput label="Notes" name="notes" />
                <Button type="submit" size="sm">
                  Save
                </Button>
              </form>
            </Card>
          ) : null}

          {isAssignedReviewer ? (
            <Card>
              <p className="text-xs font-semibold uppercase tracking-wide text-muted">Add a finding (this chunk)</p>
              <form action={createChunkFindingAction} className="mt-xs grid gap-sm">
                <input type="hidden" name="chunkingReviewId" value={review.id} />
                <input type="hidden" name="chunkIndex" value={currentChunkIndex} />
                <Select label="Finding type" name="findingType" required>
                  {CHUNK_FINDING_TYPES.map((t) => (
                    <option key={t} value={t}>
                      {CHUNK_FINDING_TYPE_LABELS[t]}
                    </option>
                  ))}
                </Select>
                <Select label="Severity" name="severity" required defaultValue="minor">
                  <option value="informational">Informational</option>
                  <option value="minor">Minor</option>
                  <option value="major">Major</option>
                  <option value="critical">Critical</option>
                </Select>
                <TextInput label="Title" name="title" required />
                <Textarea label="Description" name="description" />
                <Textarea label="Suggested action" name="suggestedAction" />
                <div>
                  <Button type="submit" size="sm" variant="secondary">
                    Add finding
                  </Button>
                </div>
              </form>
            </Card>
          ) : null}
        </>
      ) : null}

      <Section title="Findings" description={`${findings.length} total · ${openCritical} open critical · ${openMajor} open major`}>
        {findings.length === 0 ? (
          <p className="text-sm text-muted">No findings recorded yet.</p>
        ) : (
          <div className="flex flex-col gap-sm">
            {findings.map((f) => (
              <Card key={f.id}>
                <div className="flex flex-wrap items-center justify-between gap-xs">
                  <div>
                    <p className="text-sm font-medium text-ink">{f.title}</p>
                    <p className="text-xs text-muted">{CHUNK_FINDING_TYPE_LABELS[f.finding_type]}</p>
                  </div>
                  <div className="flex items-center gap-xs">
                    <ChunkFindingSeverityBadge severity={f.severity} />
                    <ChunkFindingStatusBadge status={f.status} />
                  </div>
                </div>
                {f.description ? <p className="mt-xs text-sm text-body">{f.description}</p> : null}
                {f.suggested_action ? <p className="mt-xxs text-xs text-muted">Suggested: {f.suggested_action}</p> : null}
                {f.resolution_note ? <p className="mt-xxs text-xs text-muted">Resolution: {f.resolution_note}</p> : null}

                {isActive && f.status === "open" && has(PERMISSIONS.GUIDELINE_CHUNKING_REVIEW) ? (
                  <form action={updateChunkFindingStatusAction} className="mt-xs flex flex-wrap items-end gap-xs border-t border-border pt-xs">
                    <input type="hidden" name="findingId" value={f.id} />
                    <input type="hidden" name="chunkingReviewId" value={review.id} />
                    <Select label="Status" name="status" defaultValue="acknowledged">
                      <option value="acknowledged">Acknowledge</option>
                      <option value="resolved">Resolved</option>
                      <option value="accepted_risk">Accept risk</option>
                      <option value="dismissed">Dismiss</option>
                    </Select>
                    <TextInput label="Resolution note" name="resolutionNote" hint={f.severity === "major" || f.severity === "critical" ? "Required to dismiss or accept risk" : undefined} />
                    <Button type="submit" size="sm" variant="secondary">
                      Update
                    </Button>
                  </form>
                ) : null}
              </Card>
            ))}
          </div>
        )}
      </Section>

      {review.review_status === "in_review" && isAssignedReviewer ? (
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Technical review checklist</p>
          <ul className="mt-xs grid gap-xxs text-sm text-body sm:grid-cols-2">
            {CHUNK_TECHNICAL_REVIEW_CHECKLIST.map((item) => (
              <li key={item}>· {item}</li>
            ))}
          </ul>

          <div className="mt-md border-t border-border pt-md">
            <p className="text-xs font-semibold uppercase tracking-wide text-muted">Submit decision</p>
            {!review.all_chunks_reviewed ? <p className="mt-xs text-sm text-muted">Every chunk must be marked reviewed before a decision can be submitted.</p> : null}
            <form action={submitChunkingReviewAction} className="mt-xs grid gap-sm">
              <input type="hidden" name="chunkingReviewId" value={review.id} />
              <Select label="Decision" name="targetStatus" required defaultValue="accepted">
                <option value="accepted">Accepted</option>
                <option value="accepted_with_warnings">Accepted with warnings</option>
                <option value="rechunk_required">Rechunk required</option>
                <option value="rejected">Rejected</option>
              </Select>
              <Textarea label="Decision reason" name="decisionReason" hint="Required for rechunk required and rejected" />
              <Textarea label="Warning summary" name="warningSummary" hint="Required for accepted with warnings" />
              <div>
                <Button type="submit" disabled={!review.all_chunks_reviewed}>
                  Submit decision
                </Button>
              </div>
            </form>
          </div>
        </Card>
      ) : null}

      {canOverride && (review.review_status === "pending_review" || review.review_status === "in_review") ? (
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Assign reviewer</p>
          <form action={assignChunkingReviewerAction} className="mt-xs flex items-end gap-xs">
            <input type="hidden" name="chunkingReviewId" value={review.id} />
            <TextInput label="Reviewer user ID" name="reviewerUserId" required />
            <Button type="submit" size="sm" variant="secondary">
              Assign
            </Button>
          </form>
        </Card>
      ) : null}
    </main>
  );
}
