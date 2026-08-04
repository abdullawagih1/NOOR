# Known Limitations — Sprint 1-D3

Honest accounting of what this build does and does not verify. Update in
the same PR that resolves an item.

1. ~~No hosted Supabase project.~~ **Resolved.** Connected to the "Noor
   Development" project, all 4 migrations applied, and verified with real
   GoTrue-issued JWTs against real `/rest/v1` and `/storage/v1` endpoints —
   26 Auth/RLS/Authorization/Feature-flag/Audit assertions + 8 Storage
   assertions, all passed. See
   `docs/verification/sprint-0.5-hosted-verification.md`. One real,
   previously-unknown finding surfaced and fixed along the way: `anon` held
   unnecessary full-CRUD table grants (migration 0004).

2. ~~Vercel Preview *fully authenticated* HTTP verification needs one
   dashboard action.~~ **Resolved.** Preview is deployed with hosted
   Development Supabase values, Deployment Protection is correctly
   preserved (kept enabled, not disabled). "Protection Bypass for
   Automation" — dashboard-only, no CLI/API path exists — was configured
   by the user, who then ran `scripts/smoke-test-web.mjs` against the
   protected Preview with the bypass token: 10/10 checks passed, including
   all 6 body-content checks confirming real Noor content (not the Vercel
   SSO page). See `docs/verification/sprint-0.5-hosted-verification.md`.
   This is an HTTP-level check, not browser-driven E2E — see item 8.

3. **No custom SMTP on the hosted Development project.** GoTrue's default
   email-send rate limit applies; investigated this session (a real
   status-code difference between existing/non-existent addresses on
   `/auth/v1/recover` was root-caused to this, not an enumeration bug —
   see `docs/operations/hosted-supabase-setup.md`). Configure custom SMTP
   before Controlled Beta if reset-email volume needs to exceed the
   default quota.

4. ~~No guideline/document/RAG schema yet.~~ **Further resolved.** The
   guideline *registry* (clinical domains, authorities, guidelines,
   versions, reviews, lifecycle) exists — migration
   `0005_guideline_registry_and_lifecycle.sql`. **Secure source-document
   intake now also exists and is hosted-verified**: upload sessions,
   server-verified object registration (size/PDF-signature/SHA-256),
   duplicate detection, and idempotent `queued` processing-job creation —
   migration `0006_secure_guideline_document_intake.sql`, see
   `docs/domain/{guideline-source-documents,document-intake-lifecycle}.md`
   and `docs/verification/sprint-1.1-document-intake-verification.md`.
   Document *processing* (claiming a queued job, OCR, parsing, chunking,
   embeddings, retrieval, generation) is still not built — `guideline_versions`
   carries no file/document reference at all, by design (ADR 0007 keeps
   the clinical publication lifecycle and the document-processing
   lifecycle as two separate state machines; ADR 0008 further separates
   the upload-session and processing-job lifecycles from each other). Next
   task: "Processing Worker Claim, Retry, and Extraction Foundation"
   (Sprint 1.2, S1-C).

5. ~~Worker does not process anything yet.~~ **Partially resolved.** The
   Worker can now claim, lease, heartbeat, retry, recover, and complete a
   job end-to-end (`WORKER_PROCESSING_MODE=noop`,
   `apps/worker/app/worker_loop.py`) — but the processor itself remains a
   controlled no-op (`apps/worker/app/processing.py`), never parsing a
   real PDF, chunking text, or calling any embedding/reranking/LLM
   provider. `POST /jobs` (the queue-message-shaped endpoint) still only
   validates and acknowledges a contract, unconnected to the new polling
   loop. No AI provider has been selected. See
   `docs/domain/document-processing-orchestration.md`.

6. **No queue integration.** Supabase Queues remains the approved
   long-term design; Sprint 1.2A deliberately chose direct database
   polling instead (Mode A, ADR 0009) — correctness does not depend on a
   queue, proven under real dual-process concurrency
   (`supabase/tests/concurrency/verify_concurrent_claim.sh`). Nothing
   currently publishes or consumes a queue message.

7. **Auth covers session/permission/password-reset, not full account
   lifecycle.** Login, logout, session refresh, active-membership
   resolution, permission-gated routes, and password reset are real and
   verified — against a real hosted project this session, with real JWTs.
   Public signup is intentionally disabled (invite-only V1 Controlled
   Beta — not a gap, a policy). Not yet built: organization switching for a
   user with multiple active memberships (resolver picks the
   earliest-created one), and an admin UI for inviting/suspending members
   (the RLS/permission rules exist; no screen yet).

8. **No Playwright/browser-driven E2E.** The login and password-reset forms
   submit via Next.js Server Actions, whose wire protocol isn't a stable
   target for a plain-`fetch` script — real HTTP-level smoke tests exist
   against a local `next start` + real local Supabase (10/10), the hosted
   Development project's Auth/REST/Storage APIs directly (34/34), and the
   protected Vercel Preview deployment itself (10/10, body-content
   verified), but actual form submission through a rendered browser page
   remains unverified. **Recorded as a pre-Controlled-Beta requirement, not
   a Sprint 1 blocker** — it does not gate Sprint 1's guideline-registry
   data-model work.

9. ~~Client/server boundary is convention-only.~~ **Resolved.**
   `lib/supabase/service-role.ts` and `lib/env/server.ts` both import the
   `server-only` npm package, which turns an accidental "use client"
   import into a real `next build` failure — verified directly (a
   throwaway Client Component was made to import `lib/env/server.ts`, the
   build failed with a genuine webpack error, then the test file was
   removed). Not an eslint rule, but a stronger guarantee: enforced by the
   bundler itself.

10. **`next@15.5.21`** (upgraded from 14.2.35 — see ADR 0006) resolves
    every Next-specific advisory `npm audit` flagged. One new transitive
    dependency appeared (`sharp`, pulled in by Next 15's image pipeline)
    with its own disclosed advisory; `apps/web` does not use `next/image`
    anywhere, so it's currently inert — re-check before ever adopting
    `next/image`.

11. **No malicious-input, prompt-injection, or adversarial-PDF testing
    exists.** There is no ingestion or generation pipeline yet for such
    tests to exercise meaningfully.

12. **Storage policies are a baseline, not the final design.** 0003 creates
    5 private buckets and one organization-scoped SELECT/INSERT policy
    pair covering all of them — verified against the hosted project this
    session (upload/read/cross-org-denial/path-traversal-denial all
    confirmed with real JWTs). Per-document-type restrictions, signed-URL
    issuance, and upload workflows are Sprint 1 scope.

13. **Audit immutability has documented, narrow bounds.** See
    `docs/database/schema.md` — append-only for every runtime role via a
    trigger, not merely a grant; overridable only through a direct,
    privileged database session, never through the application or the
    service-role key over HTTP. Confirmed live on the hosted project this
    session (see `docs/verification/sprint-0.5-hosted-verification.md`).

14. **Design system is a foundation, not final visual polish.** 32
    components exist and are typechecked and rendered on `/design-system`
    with mocked data; no animation, no component-level test suite beyond
    the build/typecheck/lint gates, and one documented, scoped WCAG
    contrast exception (`muted-soft` on placeholder text only — see
    `docs/design-system/ACCESSIBILITY.md`).

15. ~~Worker `/jobs` has zero authentication.~~ **Resolved.** A full
    environment-variable audit found `WORKER_INTERNAL_TOKEN` had been
    declared in every `.env.example` since Sprint 0 but never actually
    implemented or checked anywhere — the endpoint accepted any request.
    Now enforced via `apps/worker/app/auth.py`
    (`Authorization: Bearer <token>`, constant-time comparison, 401/403,
    no token-value leakage in errors) and the process refuses to start at
    all without a valid (≥32-char) token. See
    `docs/operations/worker-deployment.md`.

16. **No dependency store shared between Web and Worker for
    `WORKER_INTERNAL_TOKEN`.** Both sides must be configured with the
    identical value by hand in their respective hosting environments;
    there's no automated secret-sync. Acceptable for Sprint 0.5 (no real
    call site exists yet between them); worth revisiting once Sprint 1
    wires an actual Web→Worker call.

17. **No clinical domain has been confirmed or seeded.** Migration 0005
    deliberately seeds zero clinical domains — the mission explicitly
    requires human clinical confirmation before Noor commits to a starting
    scope (e.g. Adult Hypertension). See `PROJECT_STATE.md` gap G-03. The
    registry itself works with any domain once one is created through the
    normal `guidelines.create`/`clinical_domains.manage` permission path.

18. ~~Self-approval-by-a-creator-who-also-holds-`guidelines.approve` is
    blocked by code, not exercised by a live test.~~ **Resolved (G-12).**
    A dedicated regression test
    (`supabase/tests/rls/004_g12_self_approval_regression.sql`) creates a
    synthetic role holding both `guidelines.create` and
    `guidelines.approve` on one user and proves the exact scenario is
    denied — passed against plain Postgres 16 and hosted Development with
    a real GoTrue JWT. See
    `docs/verification/sprint-1.1-document-intake-verification.md`.

19. **Guideline Registry UI is minimal, not final.** No bulk operations, no
    real pagination (client filters only), no inline draft-content editing
    UI for `update_guideline_draft`/`update_guideline_version_draft` (the
    functions exist and are tested; only creation and lifecycle-transition
    forms were built this session). A review's `changes_requested`/
    `rejected` decision does not automatically transition the version back
    to `draft` — that is a deliberate design decision (review feedback and
    lifecycle transitions are separate, both append-only, event streams —
    see `docs/domain/guideline-lifecycle.md`), not an oversight, but it
    does mean a second explicit action is always required to act on
    review feedback.

20. **`guideline_versions` itself still has no file/document column — by
    design, not by omission.** A guideline version can be fully reviewed,
    approved, and activated purely as registry metadata, with or without a
    source document. What changed this sprint: a version *may* now have an
    associated `guideline_source_documents` row (a separate table, linked
    by `guideline_version_id`) once one is uploaded and verified — see
    item 4 above. `guideline_versions` deliberately does not gain a direct
    file-reference column, per ADR 0007/0008's separation of the clinical
    publication lifecycle from the intake/processing lifecycles.

21. ~~Document intake is registry/verification only — no processing
    consumer exists yet.~~ **Resolved (control plane only).** A
    `document_processing_jobs` row is now claimed, leased, retried,
    recovered, and completed by a real Worker polling loop (Sprint 1.2A,
    S1-C1) — but the processor is a controlled no-op (item 5). No progress
    percentage is ever shown — the UI displays only real, discrete
    statuses (`Queued`/`Claimed`/`Processing`/`Retry Scheduled`/
    `Succeeded`/`Failed`/`Cancelled`/`Dead-lettered`), never a fabricated
    intermediate percentage, since the underlying job has no measurable
    sub-progress to report honestly.

22. **PDF-signature validation is not malware scanning.** Verifying the
    first 5 bytes equal `%PDF-` confirms the uploaded file *is a PDF*; it
    proves nothing about whether the file is safe to open or clinically
    valid. No antivirus/malware-scanning provider is integrated in this
    sprint (mission explicitly scoped this out: "prepare a future hook...
    without implementing an unavailable provider"). Required before
    accepting externally-sourced documents at any real scale — see
    `docs/security/document-intake-authorization.md`.

23. **Only PDF is supported.** `.pdf`/`application/pdf` is the only
    accepted file type — no DOCX, HTML, images, or scanned-image
    archives. A controlled, page-scoped OCR pipeline for scanned/
    image-only *pages within* an already-accepted PDF now exists
    (Sprint 1-D2 — see item 57 below); this does not extend to other
    file formats.

24. **No browser-driven (Playwright) E2E of the upload flow.** The
    signed-upload-URL + direct-to-Storage-PUT sequence
    (`apps/web/app/knowledge/guidelines/[guidelineId]/UploadPanel.tsx`) is
    verified via real Postgres 16 assertions and a real hosted
    Storage-upload/download round trip driven directly over HTTP (not
    through a rendered browser page) — see
    `docs/verification/sprint-1.1-document-intake-verification.md`. Actual
    browser file-input + upload-progress UI interaction remains
    unverified, consistent with the existing Playwright gap (item 8),
    which already covers this as a pre-Controlled-Beta requirement.

25. **Large-file upload performance is not production-tested.** The 50 MB
    limit (`MAX_UPLOAD_SIZE_BYTES`) is enforced but has not been exercised
    with a real large file against hosted Storage under this sprint's
    verification (only a small synthetic fixture was used) — worth a
    dedicated load check before Controlled Beta if real guideline PDFs
    regularly approach the limit.

26. **Processing handler remains a controlled no-op (Sprint 1.2A, by
    design).** See item 5. Real PDF page/text extraction is Sprint 1.2B.

27. **Retry timing is a baseline policy, not production-tuned.**
    30s/60s/120s/.../900s-cap backoff and `max_attempts=3` are reasonable
    defaults, not derived from real extraction failure-mode data (which
    doesn't exist yet, since extraction itself doesn't exist yet). Revisit
    once Sprint 1.2B surfaces real, characteristic failure modes.

28. **Lease-expiry recovery runs on every Worker poll tick, not a
    dedicated schedule.** Safe under concurrent recovery calls (proven,
    `supabase/tests/rls/006_processing_orchestration.sql` TEST 10) but
    means recovery only happens while at least one Worker instance is
    online and polling — if every Worker is down, a crashed job's lease
    simply waits until one comes back. See
    `docs/operations/job-recovery-and-dead-letter.md`.

29. **`WORKER_MAX_CONCURRENT_JOBS` is declared but not enforced.** The
    current loop always processes exactly one job at a time per Worker
    process regardless of this setting's value.

30. **No manual retry of a `dead_lettered` job through the application.**
    Dead-lettered jobs are visible (permission-gated) but reactivating one
    requires a direct database statement today — deliberately deferred
    rather than shipping an undertested reactivation path. See
    `docs/operations/job-recovery-and-dead-letter.md`.

31. **No dedicated metrics/alerting pipeline for job processing.**
    Observability today is Worker process logs, direct database queries,
    and the Web UI's Job Status Card / Attempt History — no dashboards, no
    paging on stuck/dead-lettered jobs.

32. **`WORKER_INSTANCE_ID` uniqueness across a Worker fleet is not
    enforced.** Auto-generated ids are randomized per process (collision
    astronomically unlikely); an operator who pins `WORKER_INSTANCE_ID`
    explicitly on two simultaneously-running processes could cause them to
    interfere with each other's leases. Document as an operational
    requirement — not validated in code.

33. **`service_role` is shared by every Worker instance; there is no
    per-instance database credential.** Lease-token hash verification
    (`assert_lease_owner`), not the database role, is what prevents one
    Worker instance from acting on another's claimed job. See
    `docs/security/worker-orchestration-authorization.md`.

34. **Streaming file verification (Sprint 1.1's remaining item, closed
    this sprint):** the mandatory Sprint 1.2A review found
    `completeGuidelineUploadAction` fully buffered the uploaded file into
    memory (`.download()` → `arrayBuffer()`) before computing size/
    signature/checksum. Refactored to genuine incremental streaming
    (`apps/web/lib/documents/streamVerification.ts`, a raw authenticated
    `fetch()` against the Storage REST endpoint + `ReadableStream`
    processing) — same trust model, same 50 MB limit, now provably
    early-aborts on an oversized stream rather than buffering the whole
    file first. 5 new unit tests, including an explicit early-abort proof.

35. **No genuine concurrent-Worker proof beyond the dedicated bash
    harness.** `supabase/tests/rls/006_processing_orchestration.sql`
    proves sequential exclusivity within one `psql` session; real
    dual-process concurrency is proven separately
    (`supabase/tests/concurrency/verify_concurrent_claim.sh`), but that
    harness is a manual/CI-optional script, not wired into the automatic
    `npm test`/`pytest` gates — run it explicitly when reviewing changes
    to the claim function.

36. **No browser-driven (Playwright) E2E of the Job Status Card / Attempt
    History / cancel-job UI.** Consistent with the existing Playwright gap
    (item 8) — verified via real Postgres assertions and (pending) hosted
    PostgREST calls, not through a rendered browser page.

37. **Job status/attempt history reads share the existing
    `guideline_processing_jobs.read` permission — no separate
    `.read_attempts` permission was introduced.** A deliberate
    simplification (both tables carry an identical RLS predicate); revisit
    if a future role ever needs job-status visibility without
    attempt-history visibility or vice versa.

38. **Extraction itself performs no OCR.** A page with no extractable
    text layer is reported honestly (`no_text_layer`/`suspected_scanned`)
    by the deterministic extraction pipeline, never silently
    reconstructed — OCR is a separate, human-gated pipeline (Sprint
    1-D2, item 57) that only ever processes pages a reviewer explicitly
    flagged, never triggered automatically by this flag.

39. **No table reconstruction, no image extraction.** Only page-level
    plain text, dimensions, rotation, and technical metrics are extracted
    — no structured tables, no embedded image content.

40. **No layout-aware reading-order correction beyond the extractor's own
    output.** `pypdf`'s `extract_text()` reconstructs reading order from
    the PDF content stream's operator order — complex multi-column
    layouts or right-to-left (Arabic) paragraphs may not extract in true
    visual reading order. Noor's own normalization code never attempts to
    algorithmically "fix" this (mission §17: no reordering, no inference).

41. **No clinical section classification, no semantic or fixed-size
    chunking, no embeddings, no retrieval.** This sprint stops at
    immutable, deterministic, page-level extraction artifacts and
    technical metrics — S1-D (chunking, reviewer extraction queue) and
    S1-E (embeddings, retrieval) are future, separate workstreams.

42. **No human correction UI.** The page-detail view
    (`/knowledge/guidelines/[guidelineId]/extractions/[runId]/pages/[pageNumber]`)
    is read-only — no editing, no clinical-approval controls. A reviewer
    correction workflow is S1-D scope.

43. **Suspected-scanned detection is a conservative heuristic, not a
    certainty.** A page is flagged only when it has no extractable text
    *and* contains at least one embedded raster image — this can miss
    genuinely scanned pages whose PDF has no embedded-image XObject in an
    unusual encoding, and will never falsely flag a text-bearing page.
    See `docs/domain/document-extraction-artifacts.md`.

44. **Encrypted/password-protected PDFs are rejected outright**, never
    decrypted with a supplied password — `encrypted_pdf`/
    `password_protected_pdf` are terminal (non-retryable) failure codes.

45. **Extraction quality depends entirely on the source PDF's own text
    layer.** A well-formed born-digital PDF extracts cleanly; a PDF with a
    malformed or missing `ToUnicode` CMap may extract garbled or no text
    — this is a property of the source file, not a pipeline defect, and
    is reported as a low/zero character count rather than an error.

46. **Production-scale and maximum-size (50 MB) extraction performance is
    untested.** Only small synthetic fixtures (largest ~44 KB) were used
    this sprint's verification — a real, large, complex clinical
    guideline PDF's extraction time and memory profile are unverified.
    `EXTRACTION_MAX_SECONDS` (default 300s) is a configurable bound, not a
    tuned production value.

47. **Orphaned temporary files from a hard-killed (`SIGKILL`) Worker
    process are not actively swept.** Graceful shutdown and per-attempt
    `finally`-block cleanup are both real and verified; there is no
    startup routine that sweeps a stale `noor-extract-*` temp directory
    left behind by a process that was killed rather than stopped cleanly.
    See `docs/operations/pdf-extraction-worker-runbook.md`.

48. **This pipeline provides technical extraction, not clinical
    validation.** Page counts, character counts, blank-page detection,
    and suspected-scanned flags are technical facts about the PDF's text
    layer — they say nothing about clinical accuracy, guideline approval,
    evidence quality, recommendation validity, or medical completeness
    (mission §2.4). No extraction result implies or grants any clinical
    status.

49. **Extraction review is a technical quality gate, not a clinical
    review.** Sprint 1-D1's review decisions (accepted, accepted with
    warnings, OCR required, reprocessing required, rejected) judge
    whether extracted *text* is technically usable — reading order,
    encoding, completeness. They say nothing about clinical accuracy,
    guideline approval, or evidence quality, and are entirely separate
    from `guideline_reviews`' clinical review workflow.

50. **Self-review blocking has no "unless no other reviewer exists"
    exception.** `start_document_extraction_review()` unconditionally
    blocks a reviewer from reviewing a document they personally uploaded
    or registered — even in a small organization with only one eligible
    reviewer, where this could stall a review indefinitely until an
    admin manually reassigns it. A live "does another eligible reviewer
    exist" check was deliberately not implemented in V1 (see ADR 0011
    §3.6) to avoid adding untested runtime complexity for an edge case.

51. **`storage.objects` RLS for `guideline-originals`/`guideline-processed`
    is now permission-scoped, not merely organization-scoped — closed in
    Sprint 1-D2** (migration `0010_permission_scoped_storage_access.sql`).
    This item previously described the residual risk from Sprint 1.1;
    see `docs/security/ocr-and-storage-authorization.md` for the closure
    and `docs/security/extraction-review-authorization.md` for the
    original finding. `evaluation-assets`/`generated-reports`/
    `temporary-uploads` remain organization-scoped-only — none of them
    hold guideline source content yet.

52. **Reopening a review discards prior findings rather than copying them
    forward.** A reopened round starts with zero findings and zero pages
    marked reviewed — a deliberate simplicity choice (ADR 0011), but it
    means a reviewer re-establishes every finding from scratch even if
    most of the prior round's findings were still valid.

53. **The review workspace's PDF panel uses browser-native rendering**
    (an `<iframe>` with the `#page=N` URL fragment), not a bundled PDF.js
    viewer. Page-jump support via `#page=N` varies by browser; some
    browsers ignore it and always open at page 1. No dependency review
    or license audit was needed since nothing was added, but the
    trade-off is real and untested across the full browser matrix.

54. **The side-by-side review layout is a single responsive CSS grid**
    (stacks vertically below the `lg` breakpoint), not the mission's
    suggested tabbed mobile interface. This avoids adding client-side
    tab-state JavaScript for a first version; a real mobile usability
    pass for large multi-page documents has not been done.

55. **"100% of pages reviewed" is enforced uniformly across all five
    terminal decisions, including `rejected`.** A reviewer who
    identifies the wrong document on page 1 must still mark every
    remaining page reviewed (even trivially) before submitting a
    rejection — see ADR 0011's "Consequences" section for the reasoning.
    No sampling or partial-coverage policy exists yet for very large
    documents.

56. **No formal double-review or quorum requirement.** A single
    reviewer's decision is final (subject to reopening/invalidation by
    an admin or quality manager) — there is no built-in "two independent
    reviewers must agree" workflow.

57. **One OCR provider (Tesseract), self-hosted, no failover.** See ADR
    0012 for the selection rationale. No cloud OCR API integration
    exists or is planned without a separate, explicit
    architectural/privacy approval.

58. **No handwriting recognition, table reconstruction, form
    understanding, or manual OCR-text correction.** OCR output is
    machine-recognized plain text only; a future human-corrected-text
    representation is an explicitly separate, not-yet-built workstream
    (`docs/domain/ocr-page-representations.md`).

59. **OCR provider confidence is technical metadata, not clinical
    confidence, and is not comparable across providers or engine
    versions.** Never presented in a UI (once built) as an accuracy
    percentage or evidence-quality signal (mission §20).

60. **OCR quality has not been benchmarked against real, complex
    clinical guideline scans** — only synthetic fixtures (clean English,
    clean Arabic, mixed Arabic/English, rotated, low-resolution, noisy,
    empty-image, multi-column, table-like, headers/footers). Arabic and
    mixed-language output should be assumed to need more careful human
    technical review than clean English scans until real-world
    benchmarking exists.

61. **The OCR web application UI has not been exercised in a real
    browser or against a real deployed environment.** The OCR review
    queue (`/reviewer/ocr`), side-by-side review workspace
    (`/reviewer/ocr/[ocrReviewId]`), and the guideline detail page's OCR
    section are implemented and verified via `tsc --noEmit`, `next lint`,
    a real production `next build` (both routes present in the route
    table), and 136 unit-test assertions — but no Playwright/browser-
    driven E2E and no hosted/Vercel check have been performed (consistent
    with the same pre-existing gap for the extraction review workspace,
    item 24).

62. **A real browser-rendered check of Sprint 1-D2's `/reviewer/ocr`
    routes on the Vercel Preview deployment has not been performed.**
    Hosted Development verification was completed in a later
    continuation of this session (real GoTrue JWTs, a real upload, real
    extraction and OCR execution via the actual unmodified Worker code
    against real Storage, a real permission-scoped Storage RLS proof,
    all synthetic hosted data verified deleted back to zero), the
    commits were pushed to `main` with real CI green, and a real Vercel
    Preview was deployed and confirmed `Ready` with both new routes in
    the production route table — but this Vercel team's own SSO
    Deployment Protection returns a `302` to every headless request
    (including the site root), so no curl/Playwright check from this
    environment can render the page past it. See
    `docs/verification/sprint-1-d2-controlled-ocr-verification.md`.

63. **`accepted_with_warnings` and `reprocessing_required` as
    `submit_document_ocr_review` target statuses have no dedicated local
    RLS test** — only `accepted` and `rejected` are exercised in
    `supabase/tests/rls/011_controlled_ocr.sql`. The validation logic for
    all four statuses was read directly against the SQL and is
    structurally identical in shape to the two tested ones, but this is
    a real, acknowledged test-coverage gap, not a verified-equivalent
    claim.

64. **The self-review test for OCR review uses a direct, test-only
    fixture manipulation** (temporarily reassigning a source document's
    `uploaded_by`), since this repository's synthetic test fixtures
    include only one `clinical_reviewer` account. A second, genuinely
    distinct reviewer account exercising this same scenario has not been
    tested.

65. **UX-1's Vercel Preview deployment and browser-driven smoke test
    have not been performed** — a real disk-space environmental issue
    (`C:` at 99% capacity, Docker unresponsive) was hit mid-session and
    surfaced to the user rather than worked around; local verification
    (typecheck/lint/build/all test suites across `apps/web`,
    `packages/ui`, `packages/clinical-schemas`, `apps/worker`) completed
    successfully once minimal space was freed, but no deployed,
    browser-verified Preview exists yet for this sprint. See
    `docs/verification/ux-1-brand-alignment-verification.md`.

66. **No automated accessibility tooling (axe, Lighthouse CI, or
    equivalent) exists in this repository.** Every WCAG contrast ratio
    in `docs/design/noor-accessibility-review.md` was computed
    programmatically from the actual hex values used, but no automated
    DOM-level scan of a rendered page has ever been run — consistent
    with this repository's broader, pre-existing gap (item 24: no
    Playwright/browser-driven E2E exists at all).

67. **No approved dark-background or monochrome NOOR logo variant
    exists.** Only the white-background artwork was supplied and
    approved. `brandColorsDark` (Noor's pre-existing dark-mode token
    set) was updated for palette consistency, but the logo itself is
    never placed on a dark surface anywhere in the product until such a
    variant is produced by a human designer and separately approved —
    see `docs/brand/noor-logo-usage.md`.

68. **Favicon/app-icon legibility below ~32px is genuinely poor for the
    logo's network-graphic detail.** This is an accepted fidelity
    trade-off (the mission prohibits redrawing/simplifying the mark for
    small sizes), not an oversight — see
    `docs/brand/noor-logo-usage.md`.

69. **UX-1.1's screenshots are a one-time visual-acceptance artifact,
    not a standing automated visual-regression suite.** No axe/
    Lighthouse accessibility scan and no repeatable Playwright
    visual-diff test were added — the 22 screenshots in
    `docs/verification/screenshots/ux-1-1/` prove this specific
    mission's redesign, they do not guard future changes from
    regressing the same pages. Consistent with this repository's
    broader, pre-existing gap (item 24/66: no Playwright/browser-driven
    E2E exists at all).

70. **UX-1.1's RTL screenshots are a layout-mirroring simulation, not
    real Arabic content.** Noor has no routed Arabic locale (no `/ar/...`
    path, no i18n routing) — the RTL captures force `dir="rtl"`/
    `lang="ar"` on the existing English-copy DOM immediately before
    capture, proving the flex-based layouts and token system mirror
    correctly, not that real Arabic typography has been visually
    verified in production use. See
    `docs/verification/ux-1-1-visual-acceptance.md`.

71. ~~UX-1.1's final status intentionally remains "Implementation
    Complete, Pending User Visual Acceptance."~~ **Resolved.** The user
    accepted the screenshot evidence — final status is "Complete and
    Visually Accepted." See `docs/verification/ux-1-1-visual-acceptance.md`.

72. **`noor-simple-tokenizer`'s token count is a technical sizing proxy
    only, never a real embedding model's token count.** Chunk sizing
    (`TARGET_CHUNK_TOKENS`/`HARD_MAXIMUM_CHUNK_TOKENS`) is bounded by a
    deterministic, dependency-free regex tokenizer chosen specifically
    to avoid Arabic-fragmentation bias and the risk of its count being
    mistaken for a real model's tokenization (ADR 0014). Whichever
    embedding model S1-E eventually selects will almost certainly
    tokenize differently — this is expected and does not require
    rechunking by itself, but real per-model token budgets must be
    re-derived at that point, not assumed from this sprint's counts.

73. **Chunking has not been benchmarked against real, complex clinical
    documents.** Verified against synthetic English/Arabic/mixed-language/
    list/heading/table-like/oversized-paragraph fixtures only (Worker
    unit tests) and small synthetic fixtures in the RLS suite — no real
    multi-column clinical guideline PDF, footnote-heavy document, or
    genuinely large document (hundreds of pages) has been chunked yet.
    `finalize_document_chunking_run`'s single atomic insert is sized for
    this sprint's fixture scale — see
    `docs/operations/chunking-worker-runbook.md`'s scaling note.

74. **No automated "rechunk" trigger exists.** A `rechunk_required`/
    `rejected` chunk review decision does not automatically re-run
    chunking under a different configuration — a human must decide what
    `CHUNKING_CONFIGURATION_VERSION` change is warranted and request a
    new chunking job. See `docs/operations/chunking-failure-and-rechunking.md`.

75. **The chunking review workspace has no original-page visual panel.**
    Unlike the OCR review workspace (which shows the original rendered
    page alongside native/OCR text), the chunking review workspace shows
    only chunk text and provenance metadata — a deliberate scope
    reduction, since a reviewer already saw the original page during
    extraction/OCR review. Revisit if chunk-boundary review in practice
    needs the original page visible again.

76. **A real browser-rendered check of Sprint 1-D3's `/reviewer/chunking`
    routes has not been performed**, for the same reason as item 62 (OCR)
    — this Vercel team's SSO Deployment Protection blocks any headless
    browser check of a live Preview URL from this environment.

77. **`noor-lexical-baseline-v1` uses no stemming, no Arabic root
    matching, and no stop-word removal.** PostgreSQL's `simple` text-
    search configuration is used identically for English and Arabic
    (there is no built-in Arabic configuration, and `english` stemming
    would unfairly bias results toward English content) — a query and a
    relevant chunk that differ by inflection/conjugation/root form will
    not match unless they share an exact normalized token. This is a
    real, honestly-documented capability limit of the lexical baseline
    itself (ADR 0015), not a bug to fix within this sprint's scope.

78. **Only one deterministic lexical baseline exists — no second
    baseline for comparison.** `noor-lexical-baseline-v1` is the only
    `Retriever` implementation; `VectorRetriever`/`HybridRetriever`/
    `RerankerRetriever` are declared as Protocol stubs only, with nothing
    behind them. Every metric reported this sprint describes lexical
    retrieval only, never embedding/hybrid/reranked retrieval.

79. **Retrieval evaluation has not been benchmarked against real, complex
    clinical content.** Verified against small synthetic English/Arabic/
    negative-control fixtures only (local RLS suite, Worker unit tests,
    and one real hosted 3-page synthetic PDF) — no real multi-hundred-
    chunk corpus or realistic clinical query set has been evaluated yet.

80. **The hosted end-to-end verification's Arabic query returned zero
    candidates**, not because Arabic full-text matching is broken (it is
    separately and directly proven correct by the local RLS suite, which
    inserts real normalized Arabic text without going through PDF
    extraction), but because the ad hoc verification script's hand-built
    synthetic PDF embeds Arabic text using a Latin-only base font
    (Helvetica), which `pypdf` cannot reliably extract as real Arabic
    Unicode text. The system's own failure-detection pipeline correctly
    flagged this as `query_too_narrow` rather than crashing or fabricating
    a match — see `docs/verification/sprint-1-e1-retrieval-evaluation-verification.md`.

81. **A real browser-rendered check of Sprint 1-E1's
    `/quality/retrieval-evaluation/*` routes against the deployed Vercel
    Preview has not been performed**, for the same reason as item 62
    (OCR) and item 76 (chunking) — this Vercel team's SSO Deployment
    Protection blocks any headless browser check of a live Preview URL
    from this environment. Real, authenticated screenshots against real
    hosted data *were* captured this sprint by running a local dev server
    against the hosted Development database directly (see the
    verification doc) — the gap is specifically the Preview *deployment*
    URL, not the feature itself.

82. **`npm run` (the npm CLI wrapper, not the underlying tools) hangs
    indefinitely on this session's Windows/Git-Bash environment** —
    observed for both `npm run test --workspace=apps/web` and `npm run
    build --workspace=apps/web`, producing zero output for many minutes
    before any real test/build output appeared. Root cause not fully
    diagnosed (most plausibly npm's own background update-check network
    call being blocked/stalled in this sandboxed environment) but
    confirmed NOT to be a defect in this sprint's own code: calling the
    underlying tools directly (`npx tsx <file>`, `npx next build`)
    completes normally in seconds. A future session hitting the same
    "nothing is happening" symptom should suspect `npm run` itself first.

83. **The Arabic-vector-ranking case was not re-verified against hosted
    infrastructure after the underlying fixture bug (item 80) was
    diagnosed and fixed.** Sprint 1-E2 confirmed the exact byte-level
    mechanism (Arabic text drawn via a Latin-only-encoded PDF string
    literal double-UTF-8-corrupts through `pypdf`'s single-byte
    decoding — not fixable by font choice alone, since multi-byte
    Arabic code points cannot survive a single-byte string literal at
    all) and verified a real fix (`reportlab` + a registered Unicode TTF
    font + pre-reversing the source string to compensate for `pypdf`'s
    RTL extraction order — confirmed byte-for-byte round-trip locally).
    Time constraints ended this sprint's hosted-verification pass before
    re-running the full pipeline with the corrected fixture. The English
    case, the chunk-embedding pipeline, the query-embedding pipeline, and
    exact-vs-indexed correctness were all proven correct with real hosted
    data and the real model; a real Arabic query/passage pair *was*
    smoke-tested locally against the real model (cosine similarity 0.888)
    but not through the full hosted pipeline. See
    `docs/verification/sprint-1-e2-embedding-and-vector-verification.md`.

84. **A small residual of Sprint 1-E2 hosted synthetic test data was not
    cleaned up** — one synthetic guideline/document/chunk/embedding-run
    chain and three synthetic GoTrue accounts, all clearly labeled
    "S1-E2 Verify"/`e2-*`, containing zero real content. The three
    accounts could not be deleted via the GoTrue admin API because
    `audit_events.actor_id` references them (a real, by-design FK —
    audit history is append-only and cannot reference a deleted actor);
    deleting them requires the same `noor.allow_audit_maintenance`
    override pattern applied to `audit_events` specifically, which this
    session did not complete. Documented here rather than forced through
    with a broader/riskier operation — the same "flag it, don't force
    it" precedent Sprint 1-D3 set for its stray Vercel project. See the
    verification doc for the exact IDs.

85. **This Worker now depends on `torch` and `sentence-transformers`
    (Sprint 1-E2)** — a real, deliberate departure from every prior
    sprint's near-zero-dependency Worker image. The CPU-only wheel keeps
    the added footprint to ~1.2GB (model weights + PyTorch), but this is
    still the single largest dependency change in this codebase's
    history. A future sprint changing the approved embedding model
    should re-read ADR 0016's provider-selection reasoning before adding
    a second heavy ML dependency casually.

86. **LX-1.0's prototype performance measurements are a dev-mode spike,
    not a production budget claim.** The bundle/main-thread numbers
    recorded in `docs/verification/lx-1-0-narrative-motion-prototype.md`
    §10 were measured against `next dev` (webpack dev bundles are
    deliberately unminified/uncompressed) specifically to compare
    Framer Motion vs. GSAP vs. CSS/SVG for the signature scene — they
    are not evidence that the eventual production landing page (LX-1.2)
    will meet the targets in `docs/landing/NOOR_LANDING_PERFORMANCE_BUDGET.md`.
    Real production-build and Vercel-Preview measurement is explicitly
    deferred to LX-1.3.

87. **LX-1.0's mobile Lighthouse baseline reading inherited the same
    localhost-throttling artifact documented for Sprint 1-E2** — see
    `docs/landing/LX-1-0_BASELINE.md` §4.4. The desktop numbers (perfect
    Lighthouse scores, 0.5s LCP, 189 KiB) are the trustworthy baseline
    figures; the mobile Performance score of 0.45 almost certainly
    overstates real mobile latency given the page ships near-zero
    client JS. Re-verification against a real Vercel Preview URL is
    deferred to LX-1.3.

88. **`npm run test --workspace=apps/web` can hang indefinitely on this
    Windows/git-bash development setup** if orphaned `npm`/`next dev`
    processes from an earlier session step are still running — the
    `npm-cli.js` wrapper appears to buffer/block on process contention
    rather than failing loudly. Confirmed during LX-1.0 verification:
    killing the orphaned processes (identified via `Get-CimInstance
    Win32_Process`) resolved it immediately, and the identical test
    command chain run directly (bypassing `npm-cli.js`) always completes
    cleanly. Not a CI risk (GitHub Actions runners don't accumulate
    cross-session orphans), but worth knowing if a future local session
    sees the same hang.

89. **`@react-three/fiber` v8 does not work with Next.js 15.5.21 +
    React 18.3.1 in this repository** — confirmed genuine and upstream,
    not a local misconfiguration (see `docs/landing/
    NOOR_LANDING_THREEJS_DECISION.md` §"LX-1.1 Amendment" and
    `docs/verification/lx-1-1-cinematic-prototype-verification.md` §2
    for the full root-cause chain and GitHub issue citations). LX-1.1's
    cinematic prototype works around this entirely by using plain,
    imperative Three.js instead — `@react-three/fiber`/`@react-three/drei`
    are not installed in this repository. If a future sprint wants
    React Three Fiber specifically, re-check whether v9 (which requires
    React 19) has become viable, since v8 should not be re-attempted
    against this stack without a new fix appearing upstream.

90. **A `useReducedMotion()`-driven hydration-mismatch pattern was
    found and fixed 3 times within LX-1.1's own new code** (`CinematicNav.tsx`,
    `CinematicExperience.tsx`, `SceneSectionReveal.tsx`) but was not
    audited across the rest of `apps/web` — in particular, LX-1.0's
    prototype gallery (`/design/landing-experience`) uses the same
    `useEffectiveReducedMotion` hook in several places and was never
    specifically checked with a real reduced-motion-emulated Playwright
    run monitoring console output for hydration errors (its own
    verification relied on `@axe-core/playwright`, which does not
    surface hydration console errors). A future sprint should run the
    same check there before assuming it's clean.

91. ~~LX-1.1's cinematic route performance numbers (FPS, Lighthouse
    Performance/TBT/byte-weight) were measured against headless
    Chromium running SwiftShader (CPU software rendering, confirmed via
    `WEBGL_debug_renderer_info`) and a `next dev` build.~~ **Resolved
    (LX-1.1.1).** A `NOOR_CINEMATIC_PREVIEW_ENABLED` server-side gate
    (see `docs/landing/NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md`) now lets
    the route be reached on a real production build; headless Chromium
    launched with `--use-gl=angle --use-angle=gl
    --ignore-gpu-blocklist --enable-gpu-rasterization` was confirmed
    via `WEBGL_debug_renderer_info` to reach this machine's real Intel
    GPU (`ANGLE (Intel, Intel(R) RaptorLake-S Mobile Graphics
    Controller, OpenGL 4.5.0)`), contradicting the earlier assumption
    that headless always means software rendering. Real numbers:
    Lighthouse Performance 0.94 desktop / 0.95 mobile, FPS 40–61 across
    all 7 scenes — see `docs/landing/NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`.

92. **Scene 5 (Retrieval) dips to ~40fps on real GPU hardware**, the
    only scene below ~58fps in LX-1.1.1's real-GPU measurement pass —
    every other scene holds at or near 60fps. Likely cause: 3
    DOM-projected rank-badge anchors (`getScreenAnchors()` in
    `EvidenceCoreScene.ts`) recomputing screen position every 2nd RAF
    frame simultaneously with the query-beam animation. Not a
    regression blocker (well above visible-stutter territory) but
    worth a future optimization pass — e.g. widening the projection
    interval further for this scene specifically. See
    `docs/landing/NOOR_CINEMATIC_PERFORMANCE_BUDGET.md` §"What remains
    for a future mission."

93. **LX-1.1.1's mobile Lighthouse "mobile preset" run is still a
    desktop-machine emulation of mobile viewport/network conditions,
    not a measurement on physical mobile hardware.** The real-GPU
    confirmation this mission covers the desktop machine's integrated
    GPU only. A future mission should measure FPS/Lighthouse on an
    actual mobile device before treating the cinematic route's mobile
    performance as production-verified.
