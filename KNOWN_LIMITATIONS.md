# Known Limitations — Sprint 0.5

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

2. **Vercel Preview *fully authenticated* HTTP verification needs one
   dashboard action.** Preview is deployed with hosted Development
   Supabase values, Deployment Protection is correctly preserved (kept
   enabled, not disabled), and `scripts/smoke-test-web.mjs` correctly
   detects and reports the protection wall rather than false-passing. What
   remains: "Protection Bypass for Automation" must be enabled via the
   Vercel dashboard — confirmed this session there is no CLI command and
   the REST API rejects the plausible field names/endpoints (400/404) for
   doing this programmatically. See
   `docs/operations/vercel-preview-deployment.md`.

3. **No custom SMTP on the hosted Development project.** GoTrue's default
   email-send rate limit applies; investigated this session (a real
   status-code difference between existing/non-existent addresses on
   `/auth/v1/recover` was root-caused to this, not an enumeration bug —
   see `docs/operations/hosted-supabase-setup.md`). Configure custom SMTP
   before Controlled Beta if reset-email volume needs to exceed the
   default quota.

4. **No guideline/document/RAG schema yet.** Only the identity/tenancy/audit
   (0001), permission/hardening (0002), storage-foundation (0003), and
   anon-grant hardening (0004) migrations exist. Document processing,
   chunks, embeddings, retrieval, and generation tables are Sprint 1+
   (MASTER_BACKLOG.md).

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
   against both a local `next start` + real local Supabase (10/10) and the
   hosted Development project's Auth/REST/Storage APIs directly (34/34),
   but actual form submission through a rendered browser page remains
   unverified. Sprint 1 task, not faked here.

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
