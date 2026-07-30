import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getDocumentExtractionPage } from "@/lib/documents/queries";
import {
  getOcrReview,
  getOcrRequest,
  listOcrRequestPages,
  listOcrPageReviews,
  listOcrFindings,
  getLatestOcrRunsByPage,
  OCR_FINDING_TYPES,
} from "@/lib/ocr/queries";
import {
  OcrReviewStatusBadge,
  OcrRequestStatusBadge,
  OcrRunStatusBadge,
  OcrPageReviewStatusBadge,
  OcrFindingSeverityBadge,
  OcrFindingStatusBadge,
  OCR_FINDING_TYPE_LABELS,
  OCR_TECHNICAL_REVIEW_CHECKLIST,
} from "@/lib/ocr/ui";
import {
  assignOcrReviewerAction,
  claimOcrReviewAction,
  startOcrReviewAction,
  markOcrPageReviewedAction,
  createOcrFindingAction,
  updateOcrFindingStatusAction,
  submitOcrReviewAction,
  reopenOcrReviewAction,
  invalidateOcrReviewAction,
} from "@/lib/ocr/actions";
import { OcrSourcePagePanel } from "./OcrSourcePagePanel";
import { PageHeader, Card, Section, Badge, TextInput, Textarea, Select, Button, Alert } from "@noor/ui";

export const dynamic = "force-dynamic";

const ACTIVE_STATUSES = new Set(["pending_review", "in_review"]);
const TERMINAL_STATUSES = new Set(["accepted", "accepted_with_warnings", "reprocessing_required", "rejected"]);

export default async function OcrReviewDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ ocrReviewId: string }>;
  searchParams: Promise<{ error?: string; page?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_OCR_READ);
  const { ocrReviewId } = await params;
  const { error, page: pageParam } = await searchParams;

  const review = await getOcrReview(ocrReviewId);
  if (!review || review.organization_id !== context.organizationId) {
    notFound();
  }

  const request = await getOcrRequest(review.ocr_request_id);
  if (!request) notFound();

  const [requestPages, pageReviews, findings, runsByPage] = await Promise.all([
    listOcrRequestPages(request.id),
    listOcrPageReviews(review.id),
    listOcrFindings(review.id),
    getLatestOcrRunsByPage(request.id),
  ]);

  const currentPageNumber = Math.max(1, Math.min(Number(pageParam) || 1, requestPages[0]?.page_number ?? 1));
  const currentRequestPage = requestPages.find((p) => p.page_number === currentPageNumber) ?? requestPages[0];
  const currentRun = currentRequestPage ? runsByPage.get(currentRequestPage.id) : undefined;
  const currentPageReview = pageReviews.find((pr) => pr.page_number === currentPageNumber);
  const nativePage = currentRequestPage ? await getDocumentExtractionPage(request.extraction_run_id, currentRequestPage.page_number) : null;

  const has = (p: string) => context.permissionKeys.includes(p);
  const isAssignedReviewer = review.assigned_reviewer_id === context.userId;
  const canOverride = has(PERMISSIONS.GUIDELINE_OCR_REVIEW);
  const isActive = ACTIVE_STATUSES.has(review.review_status);
  const isTerminal = TERMINAL_STATUSES.has(review.review_status);
  const openCritical = findings.filter((f) => f.severity === "critical" && f.status === "open").length;
  const openMajor = findings.filter((f) => f.severity === "major" && f.status === "open").length;

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Technical OCR Review — not a clinical review"
        title={`OCR review round ${review.review_round}`}
        description="Compares the original page, the deterministic native extraction, and the OCR recognition result side by side. Findings and decisions here never edit either text representation — they only decide whether the OCR result is technically usable."
        actions={<OcrReviewStatusBadge status={review.review_status} />}
      />

      {error ? <Alert tone="critical" title="Could not complete that action">{error}</Alert> : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href="/reviewer/ocr">
          ← Back to queue
        </Link>
        <span className="text-muted">
          {review.pages_reviewed}/{review.total_pages} pages reviewed
        </span>
        <OcrRequestStatusBadge status={request.status} />
        <span className="font-mono text-xs text-muted">
          {request.provider_name} {request.provider_version} · {request.renderer_name} {request.renderer_version} · {request.language_hints.join("+")}
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
            {!review.assigned_reviewer_id && has(PERMISSIONS.GUIDELINE_OCR_REVIEW) ? (
              <form action={claimOcrReviewAction}>
                <input type="hidden" name="ocrReviewId" value={review.id} />
                <Button type="submit" size="sm" variant="secondary">
                  Claim this review
                </Button>
              </form>
            ) : null}
            {(!review.assigned_reviewer_id || isAssignedReviewer) && has(PERMISSIONS.GUIDELINE_OCR_REVIEW) ? (
              <form action={startOcrReviewAction}>
                <input type="hidden" name="ocrReviewId" value={review.id} />
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
          {has(PERMISSIONS.GUIDELINE_OCR_REOPEN_REVIEW) ? (
            <div className="mt-sm flex flex-col gap-sm sm:flex-row sm:items-end">
              <form action={reopenOcrReviewAction} className="flex flex-1 items-end gap-xs">
                <input type="hidden" name="ocrReviewId" value={review.id} />
                <TextInput label="Reopen reason" name="reason" required hint="Required" className="flex-1" />
                <Button type="submit" size="sm" variant="secondary">
                  Reopen
                </Button>
              </form>
              {review.review_status === "accepted" || review.review_status === "accepted_with_warnings" ? (
                <form action={invalidateOcrReviewAction} className="flex flex-1 items-end gap-xs">
                  <input type="hidden" name="ocrReviewId" value={review.id} />
                  <TextInput label="Invalidate reason" name="reason" required hint="Required" className="flex-1" />
                  <Button type="submit" size="sm" variant="danger">
                    Invalidate
                  </Button>
                </form>
              ) : null}
            </div>
          ) : null}
        </Card>
      ) : null}

      {review.review_status === "in_review" && currentRequestPage ? (
        <>
          <div className="flex flex-wrap items-center justify-between gap-xs">
            <p className="text-sm font-semibold text-ink">
              Page {currentPageNumber} — request page {requestPages.findIndex((p) => p.id === currentRequestPage.id) + 1} of {requestPages.length}
            </p>
            <div className="flex items-center gap-xs">
              {currentPageReview ? <OcrPageReviewStatusBadge status={currentPageReview.review_status} /> : <Badge>Unreviewed</Badge>}
              {currentRun ? <OcrRunStatusBadge status={currentRun.status} /> : null}
            </div>
          </div>
          <div className="flex flex-wrap gap-xs text-xs">
            {requestPages.map((p) => {
              const pr = pageReviews.find((x) => x.page_number === p.page_number);
              return (
                <Link
                  key={p.id}
                  href={`/reviewer/ocr/${review.id}?page=${p.page_number}`}
                  className={`rounded-full border px-xs py-xxs ${p.page_number === currentPageNumber ? "border-ink bg-ink text-onPrimary" : "border-border text-muted"}`}
                >
                  {p.page_number}
                  {pr && pr.review_status !== "unreviewed" ? " ✓" : ""}
                </Link>
              );
            })}
          </div>

          <div className="grid gap-md lg:grid-cols-3">
            <div className="min-h-[420px]">
              <p className="mb-xxs text-xs font-semibold uppercase tracking-wide text-muted">Original page</p>
              <OcrSourcePagePanel extractionRunId={request.extraction_run_id} pageNumber={currentPageNumber} />
            </div>
            <div className="flex min-h-[420px] flex-col rounded-sm border border-border bg-surface p-sm">
              <p className="mb-xxs text-xs font-semibold uppercase tracking-wide text-muted">Native extraction</p>
              <p className="whitespace-pre-wrap text-sm text-body">{nativePage?.normalized_text || "(no native text — this page was flagged for OCR)"}</p>
            </div>
            <div className="flex min-h-[420px] flex-col rounded-sm border border-border bg-surface p-sm">
              <p className="mb-xxs text-xs font-semibold uppercase tracking-wide text-muted">OCR result</p>
              {currentRun ? (
                <>
                  <p className="whitespace-pre-wrap text-sm text-body">{currentRun.normalized_text || "(no text recognized)"}</p>
                  <dl className="mt-sm grid grid-cols-2 gap-x-md gap-y-xxs border-t border-border pt-xs text-xs text-muted">
                    <div>
                      <dt className="uppercase tracking-wide">Characters</dt>
                      <dd className="text-ink">{currentRun.character_count}</dd>
                    </div>
                    <div>
                      <dt className="uppercase tracking-wide">Words</dt>
                      <dd className="text-ink">{currentRun.word_count}</dd>
                    </div>
                    <div>
                      <dt className="uppercase tracking-wide">Avg. confidence</dt>
                      <dd className="text-ink">
                        {typeof currentRun.confidence_summary?.average_confidence === "number"
                          ? `${(currentRun.confidence_summary.average_confidence as number).toFixed(1)}% (provider-specific, not a clinical or evidence signal)`
                          : "not reported"}
                      </dd>
                    </div>
                    <div>
                      <dt className="uppercase tracking-wide">Checksum</dt>
                      <dd className="font-mono text-ink">{currentRun.text_checksum ? currentRun.text_checksum.slice(0, 12) : "—"}</dd>
                    </div>
                  </dl>
                  {currentRun.warnings.length > 0 ? (
                    <ul className="mt-xs text-xs text-warning">
                      {currentRun.warnings.map((w) => (
                        <li key={w}>⚠ {w}</li>
                      ))}
                    </ul>
                  ) : null}
                </>
              ) : (
                <p className="text-sm text-muted">No OCR run recorded for this page.</p>
              )}
            </div>
          </div>

          {isAssignedReviewer ? (
            <Card>
              <form action={markOcrPageReviewedAction} className="flex flex-wrap items-end gap-xs">
                <input type="hidden" name="ocrReviewId" value={review.id} />
                <input type="hidden" name="pageNumber" value={currentPageNumber} />
                <Select label="Mark page as" name="pageReviewStatus" defaultValue="accepted">
                  <option value="accepted">Accepted</option>
                  <option value="accepted_with_warnings">Accepted with warnings</option>
                  <option value="reprocessing_required">Reprocessing required</option>
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
              <p className="text-xs font-semibold uppercase tracking-wide text-muted">Add a finding (this page)</p>
              <form action={createOcrFindingAction} className="mt-xs grid gap-sm">
                <input type="hidden" name="ocrReviewId" value={review.id} />
                <input type="hidden" name="pageNumber" value={currentPageNumber} />
                <Select label="Finding type" name="findingType" required>
                  {OCR_FINDING_TYPES.map((t) => (
                    <option key={t} value={t}>
                      {OCR_FINDING_TYPE_LABELS[t]}
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
                    <p className="text-sm font-medium text-ink">
                      {f.title} (page {f.page_number})
                    </p>
                    <p className="text-xs text-muted">{OCR_FINDING_TYPE_LABELS[f.finding_type]}</p>
                  </div>
                  <div className="flex items-center gap-xs">
                    <OcrFindingSeverityBadge severity={f.severity} />
                    <OcrFindingStatusBadge status={f.status} />
                  </div>
                </div>
                {f.description ? <p className="mt-xs text-sm text-body">{f.description}</p> : null}
                {f.suggested_action ? <p className="mt-xxs text-xs text-muted">Suggested: {f.suggested_action}</p> : null}
                {f.resolution_note ? <p className="mt-xxs text-xs text-muted">Resolution: {f.resolution_note}</p> : null}

                {isActive && f.status === "open" && has(PERMISSIONS.GUIDELINE_OCR_REVIEW) ? (
                  <form action={updateOcrFindingStatusAction} className="mt-xs flex flex-wrap items-end gap-xs border-t border-border pt-xs">
                    <input type="hidden" name="findingId" value={f.id} />
                    <input type="hidden" name="ocrReviewId" value={review.id} />
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
            {OCR_TECHNICAL_REVIEW_CHECKLIST.map((item) => (
              <li key={item}>· {item}</li>
            ))}
          </ul>

          <div className="mt-md border-t border-border pt-md">
            <p className="text-xs font-semibold uppercase tracking-wide text-muted">Submit decision</p>
            {!review.all_pages_reviewed ? (
              <p className="mt-xs text-sm text-muted">Every OCR page must be marked reviewed before a decision can be submitted.</p>
            ) : null}
            <form action={submitOcrReviewAction} className="mt-xs grid gap-sm">
              <input type="hidden" name="ocrReviewId" value={review.id} />
              <Select label="Decision" name="targetStatus" required defaultValue="accepted">
                <option value="accepted">Accepted</option>
                <option value="accepted_with_warnings">Accepted with warnings</option>
                <option value="reprocessing_required">Reprocessing required</option>
                <option value="rejected">Rejected</option>
              </Select>
              <Textarea label="Decision reason" name="decisionReason" hint="Required for reprocessing required and rejected" />
              <Textarea label="Warning summary" name="warningSummary" hint="Required for accepted with warnings" />
              <div>
                <Button type="submit" disabled={!review.all_pages_reviewed}>
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
          <form action={assignOcrReviewerAction} className="mt-xs flex items-end gap-xs">
            <input type="hidden" name="ocrReviewId" value={review.id} />
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
