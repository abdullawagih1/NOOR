import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePermission } from "@/lib/auth/context";
import { PERMISSIONS } from "@/lib/auth/permissions";
import { getDocumentExtractionRun, listDocumentExtractionPages } from "@/lib/documents/queries";
import {
  getExtractionReview,
  listExtractionReviewFindings,
  listExtractionPageReviews,
  getExtractionReviewEligibility,
  EXTRACTION_FINDING_TYPES,
} from "@/lib/extraction-review/queries";
import {
  ExtractionReviewStatusBadge,
  ExtractionFindingSeverityBadge,
  ExtractionFindingStatusBadge,
  ExtractionPageReviewStatusBadge,
  FINDING_TYPE_LABELS,
  TECHNICAL_REVIEW_CHECKLIST,
} from "@/lib/extraction-review/ui";
import {
  assignExtractionReviewerAction,
  claimExtractionReviewAction,
  startExtractionReviewAction,
  markExtractionPageReviewedAction,
  createExtractionFindingAction,
  updateExtractionFindingStatusAction,
  submitExtractionReviewAction,
  reopenExtractionReviewAction,
  invalidateExtractionReviewAction,
} from "@/lib/extraction-review/actions";
import { SourcePdfPanel } from "./SourcePdfPanel";
import { PageHeader, Card, Section, Badge, TextInput, Textarea, Select, Button, Alert } from "@noor/ui";

export const dynamic = "force-dynamic";

const ACTIVE_STATUSES = new Set(["pending_review", "in_review"]);
const TERMINAL_STATUSES = new Set(["accepted", "accepted_with_warnings", "ocr_required", "reprocessing_required", "rejected"]);

export default async function ExtractionReviewDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ reviewId: string }>;
  searchParams: Promise<{ error?: string; page?: string }>;
}) {
  const context = await requirePermission(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_READ);
  const { reviewId } = await params;
  const { error, page: pageParam } = await searchParams;

  const review = await getExtractionReview(reviewId);
  if (!review || review.organization_id !== context.organizationId) {
    notFound();
  }

  const [run, pages, findings, pageReviews, eligibility] = await Promise.all([
    getDocumentExtractionRun(review.extraction_run_id),
    listDocumentExtractionPages(review.extraction_run_id),
    listExtractionReviewFindings(review.id),
    listExtractionPageReviews(review.id),
    getExtractionReviewEligibility(review.extraction_run_id),
  ]);

  if (!run) notFound();

  const currentPageNumber = Math.max(1, Math.min(Number(pageParam) || 1, pages.length || 1));
  const currentPage = pages.find((p) => p.page_number === currentPageNumber) ?? pages[0];
  const currentPageReview = pageReviews.find((pr) => pr.page_number === currentPageNumber);
  const has = (p: string) => context.permissionKeys.includes(p);
  const isAssignedReviewer = review.assigned_reviewer_id === context.userId;
  const canOverride = has(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_ASSIGN);
  const isActive = ACTIVE_STATUSES.has(review.review_status);
  const isTerminal = TERMINAL_STATUSES.has(review.review_status);
  const openCritical = findings.filter((f) => f.severity === "critical" && f.status === "open").length;
  const openMajor = findings.filter((f) => f.severity === "major" && f.status === "open").length;

  return (
    <main className="flex flex-col gap-lg">
      <PageHeader
        eyebrow="Technical Extraction Review — not a clinical review"
        title={`Review round ${review.review_round}`}
        description="Compares the original PDF page-by-page with the deterministic extraction result. Findings and decisions here gate future OCR and chunking eligibility — they never edit the extraction itself."
        actions={<ExtractionReviewStatusBadge status={review.review_status} />}
      />

      {error ? <Alert tone="critical" title="Could not complete that action">{error}</Alert> : null}

      <div className="flex flex-wrap items-center gap-sm text-sm">
        <Link className="underline" href="/reviewer/extractions">
          ← Back to queue
        </Link>
        <span className="text-muted">
          {review.pages_reviewed}/{review.total_pages} pages reviewed
        </span>
        {eligibility ? (
          <span className="text-muted">
            Eligible for OCR: {eligibility.out_eligible_for_ocr ? "Yes" : "No"} · Eligible for chunking: {eligibility.out_eligible_for_chunking ? "Yes" : "No"}
          </span>
        ) : null}
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
            {!review.assigned_reviewer_id && has(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_REVIEW) ? (
              <form action={claimExtractionReviewAction}>
                <input type="hidden" name="reviewId" value={review.id} />
                <Button type="submit" size="sm" variant="secondary">
                  Claim this review
                </Button>
              </form>
            ) : null}
            {(!review.assigned_reviewer_id || isAssignedReviewer) && has(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_REVIEW) ? (
              <form action={startExtractionReviewAction}>
                <input type="hidden" name="reviewId" value={review.id} />
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
          {has(PERMISSIONS.GUIDELINE_EXTRACTION_REVIEWS_REOPEN) ? (
            <div className="mt-sm flex flex-col gap-sm sm:flex-row sm:items-end">
              <form action={reopenExtractionReviewAction} className="flex flex-1 items-end gap-xs">
                <input type="hidden" name="reviewId" value={review.id} />
                <TextInput label="Reopen reason" name="reason" required hint="Required" className="flex-1" />
                <Button type="submit" size="sm" variant="secondary">
                  Reopen
                </Button>
              </form>
              {review.review_status === "accepted" || review.review_status === "accepted_with_warnings" ? (
                <form action={invalidateExtractionReviewAction} className="flex flex-1 items-end gap-xs">
                  <input type="hidden" name="reviewId" value={review.id} />
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

      {review.review_status === "in_review" ? (
        <div className="grid gap-md lg:grid-cols-2">
          <div className="min-h-[480px]">
            <SourcePdfPanel extractionRunId={review.extraction_run_id} pageNumber={currentPageNumber} />
          </div>

          <div className="flex flex-col gap-md">
            <Card>
              <div className="flex flex-wrap items-center justify-between gap-xs">
                <p className="text-sm font-semibold text-ink">
                  Page {currentPageNumber} of {pages.length}
                </p>
                <div className="flex items-center gap-xs">
                  {currentPageReview ? <ExtractionPageReviewStatusBadge status={currentPageReview.review_status} /> : <Badge>Unreviewed</Badge>}
                </div>
              </div>
              <div className="mt-xs flex flex-wrap gap-xs text-xs">
                {pages.map((p) => {
                  const pr = pageReviews.find((x) => x.page_number === p.page_number);
                  return (
                    <Link
                      key={p.id}
                      href={`/reviewer/extractions/${review.id}?page=${p.page_number}`}
                      className={`rounded-full border px-xs py-xxs ${p.page_number === currentPageNumber ? "border-ink bg-ink text-onPrimary" : "border-border text-muted"}`}
                    >
                      {p.page_number}
                      {pr && pr.review_status !== "unreviewed" ? " ✓" : ""}
                    </Link>
                  );
                })}
              </div>

              {currentPage ? (
                <div className="mt-sm border-t border-border pt-sm text-sm">
                  <p className="whitespace-pre-wrap text-body">{currentPage.normalized_text || "(no text extracted)"}</p>
                  <dl className="mt-xs grid grid-cols-2 gap-x-md gap-y-xxs text-xs text-muted sm:grid-cols-4">
                    <div>
                      <dt className="uppercase tracking-wide">Characters</dt>
                      <dd className="text-ink">{currentPage.character_count}</dd>
                    </div>
                    <div>
                      <dt className="uppercase tracking-wide">Words</dt>
                      <dd className="text-ink">{currentPage.word_count}</dd>
                    </div>
                    <div>
                      <dt className="uppercase tracking-wide">Rotation</dt>
                      <dd className="text-ink">{currentPage.rotation_degrees}°</dd>
                    </div>
                    <div>
                      <dt className="uppercase tracking-wide">Suspected scanned</dt>
                      <dd className="text-ink">{currentPage.suspected_scanned ? "Yes" : "No"}</dd>
                    </div>
                  </dl>
                </div>
              ) : null}

              {isAssignedReviewer ? (
                <form action={markExtractionPageReviewedAction} className="mt-sm flex flex-wrap items-end gap-xs border-t border-border pt-sm">
                  <input type="hidden" name="reviewId" value={review.id} />
                  <input type="hidden" name="pageNumber" value={currentPageNumber} />
                  <Select label="Mark page as" name="pageReviewStatus" defaultValue="reviewed_clear">
                    <option value="reviewed_clear">Reviewed — clear</option>
                    <option value="reviewed_with_findings">Reviewed — findings</option>
                    <option value="ocr_candidate">OCR candidate</option>
                    <option value="reprocessing_candidate">Reprocessing candidate</option>
                  </Select>
                  <TextInput label="Notes" name="notes" />
                  <Button type="submit" size="sm">
                    Save
                  </Button>
                </form>
              ) : null}
            </Card>

            {isAssignedReviewer ? (
              <Card>
                <p className="text-xs font-semibold uppercase tracking-wide text-muted">Add a finding</p>
                <form action={createExtractionFindingAction} className="mt-xs grid gap-sm">
                  <input type="hidden" name="reviewId" value={review.id} />
                  <input type="hidden" name="pageNumber" value={currentPageNumber} />
                  <input type="hidden" name="extractionPageId" value={currentPage?.id ?? ""} />
                  <Select label="Finding type" name="findingType" required>
                    {EXTRACTION_FINDING_TYPES.map((t) => (
                      <option key={t} value={t}>
                        {FINDING_TYPE_LABELS[t]}
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
                      Add finding (this page)
                    </Button>
                  </div>
                </form>
                <details className="mt-sm">
                  <summary className="cursor-pointer text-xs text-muted">Add a document-level finding instead</summary>
                  <form action={createExtractionFindingAction} className="mt-xs grid gap-sm">
                    <input type="hidden" name="reviewId" value={review.id} />
                    <Select label="Finding type" name="findingType" required>
                      {EXTRACTION_FINDING_TYPES.map((t) => (
                        <option key={t} value={t}>
                          {FINDING_TYPE_LABELS[t]}
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
                    <div>
                      <Button type="submit" size="sm" variant="secondary">
                        Add document-level finding
                      </Button>
                    </div>
                  </form>
                </details>
              </Card>
            ) : null}
          </div>
        </div>
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
                      {f.title}
                      {f.page_number ? ` (page ${f.page_number})` : " (document-level)"}
                    </p>
                    <p className="text-xs text-muted">{FINDING_TYPE_LABELS[f.finding_type]}</p>
                  </div>
                  <div className="flex items-center gap-xs">
                    <ExtractionFindingSeverityBadge severity={f.severity} />
                    <ExtractionFindingStatusBadge status={f.status} />
                  </div>
                </div>
                {f.description ? <p className="mt-xs text-sm text-body">{f.description}</p> : null}
                {f.suggested_action ? <p className="mt-xxs text-xs text-muted">Suggested: {f.suggested_action}</p> : null}
                {f.resolution_note ? <p className="mt-xxs text-xs text-muted">Resolution: {f.resolution_note}</p> : null}

                {isActive && f.status === "open" && has(PERMISSIONS.GUIDELINE_EXTRACTION_FINDINGS_RESOLVE) ? (
                  <form action={updateExtractionFindingStatusAction} className="mt-xs flex flex-wrap items-end gap-xs border-t border-border pt-xs">
                    <input type="hidden" name="findingId" value={f.id} />
                    <input type="hidden" name="reviewId" value={review.id} />
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
            {TECHNICAL_REVIEW_CHECKLIST.map((item) => (
              <li key={item}>· {item}</li>
            ))}
          </ul>

          <div className="mt-md border-t border-border pt-md">
            <p className="text-xs font-semibold uppercase tracking-wide text-muted">Submit decision</p>
            {!review.all_pages_reviewed ? (
              <p className="mt-xs text-sm text-muted">Every page must be marked reviewed before a decision can be submitted.</p>
            ) : null}
            <form action={submitExtractionReviewAction} className="mt-xs grid gap-sm">
              <input type="hidden" name="reviewId" value={review.id} />
              <Select label="Decision" name="targetStatus" required defaultValue="accepted">
                <option value="accepted">Accepted</option>
                <option value="accepted_with_warnings">Accepted with warnings</option>
                <option value="ocr_required">OCR required</option>
                <option value="reprocessing_required">Reprocessing required</option>
                <option value="rejected">Rejected</option>
              </Select>
              <Textarea label="Decision reason" name="decisionReason" hint="Required for OCR required, reprocessing required, and rejected" />
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

      {(canOverride || isAssignedReviewer === false) && (review.review_status === "pending_review" || review.review_status === "in_review") && canOverride ? (
        <Card>
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Assign reviewer</p>
          <form action={assignExtractionReviewerAction} className="mt-xs flex items-end gap-xs">
            <input type="hidden" name="reviewId" value={review.id} />
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
