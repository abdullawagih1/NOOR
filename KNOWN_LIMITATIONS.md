# Known Limitations — Sprint 0.5

Honest accounting of what this build does and does not verify. Update in
the same PR that resolves an item.

1. **No hosted Supabase project.** Verified against plain local PostgreSQL
   16 **and** a real local Supabase CLI stack (`supabase start`, Docker) —
   see `PROJECT_STATE.md`, including a real GoTrue-issued JWT exercised
   against PostgREST. That is real evidence of correctness, but it is not
   the same as a hosted project: no network-latency behavior, no
   production connection pooling, no real email delivery, and no
   Vercel↔Supabase network path have been exercised. **Blocked on
   credentials** — see `docs/operations/hosted-supabase-setup.md`.

2. **Vercel Preview HTTP verification is blocked by Deployment
   Protection.** The project builds and deploys successfully (confirmed
   this session, after fixing a monorepo root-directory misconfiguration),
   but every route on the live Preview URL — including `/login` — redirects
   to Vercel's own SSO wall by default. See
   `docs/operations/vercel-preview-deployment.md` for the two remediation
   options; neither was applied unilaterally since it's a security-posture
   decision for the project owner.

3. **No guideline/document/RAG schema yet.** Only the identity/tenancy/audit
   (0001), permission/hardening (0002), and storage-foundation (0003)
   migrations exist. Document processing, chunks, embeddings, retrieval, and
   generation tables are Sprint 1+ (MASTER_BACKLOG.md).

4. **Worker does not process anything yet.** `POST /jobs` validates and
   acknowledges a job contract; it does not parse PDFs, chunk text, or call
   any embedding/reranking/LLM provider. No AI provider has been selected.

5. **No queue integration.** Supabase Queues is the approved design; nothing
   currently publishes or consumes a queue message.

6. **Auth covers session/permission/password-reset, not full account
   lifecycle.** Login, logout, session refresh, active-membership
   resolution, permission-gated routes, and password reset (new this
   session: `/forgot-password`, `/update-password`) are real and verified.
   Public signup is intentionally disabled (invite-only V1 Controlled
   Beta — not a gap, a policy). Not yet built: organization switching for a
   user with multiple active memberships (resolver picks the
   earliest-created one), and an admin UI for inviting/suspending members
   (the RLS/permission rules exist; no screen yet).

7. **No Playwright/browser-driven E2E.** The login and password-reset forms
   submit via Next.js Server Actions, whose wire protocol isn't a stable
   target for a plain-`fetch` script — a real HTTP smoke test was run
   against a local `next start` + real local Supabase instead (route
   protection, page availability, dev-only-route enforcement; 10/10
   passed), but actual form submission through a rendered browser page
   remains unverified. Sprint 1 task, not faked here.

8. ~~Client/server boundary is convention-only.~~ **Resolved this
   session.** `lib/supabase/service-role.ts` and the new
   `lib/env/server.ts` both import the `server-only` npm package, which
   turns an accidental "use client" import into a real `next build`
   failure — verified directly (a throwaway Client Component was made to
   import `lib/env/server.ts`, the build failed with a genuine webpack
   error, then the test file was removed). Not an eslint rule, but a
   stronger guarantee: enforced by the bundler itself.

9. **`next@15.5.21`** (upgraded this session from 14.2.35 — see ADR 0006)
   resolves every Next-specific advisory `npm audit` flagged. One new
   transitive dependency appeared (`sharp`, pulled in by Next 15's image
   pipeline) with its own disclosed advisory; `apps/web` does not use
   `next/image` anywhere, so it's currently inert — re-check before ever
   adopting `next/image`.

10. **No malicious-input, prompt-injection, or adversarial-PDF testing
    exists.** There is no ingestion or generation pipeline yet for such
    tests to exercise meaningfully.

11. **Storage policies are a baseline, not the final design.** 0003 creates
    5 private buckets and one organization-scoped SELECT/INSERT policy pair
    covering all of them. Per-document-type restrictions, signed-URL
    issuance, and upload workflows are Sprint 1 scope.

12. **Audit immutability has documented, narrow bounds.** See
    `docs/database/schema.md` — append-only for every runtime role via a
    trigger, not merely a grant; overridable only through a direct,
    privileged database session, never through the application or the
    service-role key over HTTP.

13. **Design system is a foundation, not final visual polish.** 32
    components exist and are typechecked and rendered on `/design-system`
    with mocked data; no animation, no component-level test suite beyond
    the build/typecheck/lint gates, and one documented, scoped WCAG
    contrast exception (`muted-soft` on placeholder text only — see
    `docs/design-system/ACCESSIBILITY.md`).

14. ~~Worker `/jobs` has zero authentication.~~ **Resolved this session.**
    A full environment-variable audit found `WORKER_INTERNAL_TOKEN` had
    been declared in every `.env.example` since Sprint 0 but never
    actually implemented or checked anywhere — the endpoint accepted any
    request. Now enforced via `apps/worker/app/auth.py`
    (`Authorization: Bearer <token>`, constant-time comparison, 401/403,
    no token-value leakage in errors) and the process refuses to start at
    all without a valid (≥32-char) token. See
    `docs/operations/worker-deployment.md`.

15. **No dependency store shared between Web and Worker for
    `WORKER_INTERNAL_TOKEN`.** Both sides must be configured with the
    identical value by hand in their respective hosting environments;
    there's no automated secret-sync. Acceptable for Sprint 0.5 (no real
    call site exists yet between them); worth revisiting once Sprint 1
    wires an actual Web→Worker call.
