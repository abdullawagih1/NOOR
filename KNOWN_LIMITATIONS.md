# Known Limitations — Sprint 1.2A

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

23. **Only PDF is supported; no OCR.** `.pdf`/`application/pdf` is the only
    accepted file type this sprint — no DOCX, HTML, images, or
    scanned-image archives, and no OCR pipeline exists to make a
    scanned/image-only PDF's content extractable later.

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
