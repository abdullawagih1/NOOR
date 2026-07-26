# Known Limitations — Sprint 1

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

4. ~~No guideline/document/RAG schema yet.~~ **Partially resolved.** The
   guideline *registry* (clinical domains, authorities, guidelines,
   versions, reviews, lifecycle) exists and is fully implemented and
   hosted-verified — migration `0005_guideline_registry_and_lifecycle.sql`,
   see `docs/domain/guideline-registry.md` and
   `docs/verification/sprint-1-guideline-registry-verification.md`.
   Document processing (upload, OCR, parsing, chunking, embeddings,
   retrieval, generation) is still not built — `guideline_versions`
   carries no file/document reference at all, by design (see ADR 0007,
   which keeps the clinical publication lifecycle and the future
   document-processing lifecycle as two separate state machines). Next
   Sprint 1 task: "Secure Guideline Upload and Processing Job Foundation."

5. **Worker does not process anything yet.** `POST /jobs` validates and
   acknowledges a job contract; it does not parse PDFs, chunk text, or call
   any embedding/reranking/LLM provider. No AI provider has been selected.

6. **No queue integration.** Supabase Queues is the approved design; nothing
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

18. **Self-approval-by-a-creator-who-also-holds-`guidelines.approve` is
    blocked by code, not exercised by a live test.** The check inside
    `transition_guideline_version` (`auth.uid() <> guideline_versions.created_by`)
    is independent of the reviewer/approver role split and was verified by
    code review, but no seeded RLS or hosted test fixture combines "authored
    this version" with "holds guidelines.approve" to hit that exact branch
    end-to-end (the non-creator-approver and non-approver-denied paths are
    both live-tested). Low risk — the same check pattern is already
    live-tested for self-review (`prevent_self_review` trigger). See
    `docs/security/guideline-registry-authorization.md`.

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

20. **No document/file reference exists on `guideline_versions` at all.**
    Not a gap so much as a boundary: ADR 0007 keeps the clinical
    publication lifecycle (this sprint) and the document-processing
    lifecycle (upload/OCR/parsing/chunking, not yet built) as two separate
    concerns by design. A guideline version can be fully reviewed,
    approved, and activated today purely as registry metadata, with no
    underlying source file wired in yet.
