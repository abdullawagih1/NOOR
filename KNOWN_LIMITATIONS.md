# Known Limitations — Sprint 0

Honest accounting of what this Sprint 0 build does and does not verify.
Update in the same PR that resolves an item.

1. **No hosted Supabase project.** Everything in this document is verified
   against plain local PostgreSQL 16 **and** a real local Supabase CLI stack
   (`supabase start`, Docker) — see `PROJECT_STATE.md` for exact commands
   and results, including a real GoTrue-issued JWT exercised against
   PostgREST. That is real evidence of correctness, but it is not the same
   as a hosted project: no network-latency behavior, no production
   connection pooling, no real email delivery, and no Vercel↔Supabase
   network path have been exercised. Standing up a hosted project and
   re-running the same test files against it is the top Sprint 1 gap.

2. **No guideline/document/RAG schema yet.** Only the identity/tenancy/audit
   (0001), permission/hardening (0002), and storage-foundation (0003)
   migrations exist. Document processing, chunks, embeddings, retrieval, and
   generation tables are Sprint 1+ (MASTER_BACKLOG.md).

3. **Worker does not process anything yet.** `POST /jobs` validates and
   acknowledges a job contract; it does not parse PDFs, chunk text, or call
   any embedding/reranking/LLM provider. No AI provider has been selected.

4. **No queue integration.** Supabase Queues is the approved design; nothing
   currently publishes or consumes a queue message. The worker's `/jobs`
   endpoint is a contract-validation stub, not a queue consumer.

5. **Auth covers the identity/session/permission layer, not account
   lifecycle.** Login, logout, session refresh, active-membership
   resolution, and permission-gated workspace routes are real and verified
   (see PROJECT_STATE.md). Not yet built: self-service signup, password
   reset UI (the `/auth/callback` route can complete a reset link, but there
   is no "forgot password" form yet), organization switching for a user with
   multiple active memberships (the current context resolver picks the
   earliest-created one), and an admin UI for inviting/suspending members
   (the RLS/permission rules exist; there is no screen for them yet).

6. **CI has not run on GitHub Actions.** `.github/workflows/pr.yml` is
   written, YAML-validated, and every job's commands were independently
   reproduced locally this session (see PROJECT_STATE.md). It has not
   executed on GitHub Actions because this environment has no push access
   to the project's GitHub remote, which currently exists but is empty
   (confirmed via `git ls-remote`, this session).

7. **Client/server boundary is convention-only.** Nothing yet prevents a
   future "use client" component from accidentally importing
   `lib/supabase/service-role.ts`. An eslint boundary rule is a named
   Sprint 1 task.

8. **`next@14.2.35` has disclosed advisories with no non-breaking fix.**
   `npm audit` reports several high-severity Next.js advisories; the fix
   requires `next@16`, a breaking major-version change out of scope for a
   Sprint 0 hardening pass. Recorded as a flagged risk (see SECURITY.md),
   not silently upgraded — this is an architecture decision that needs
   explicit sign-off given the App Router surface this session just built
   auth on top of.

9. **No malicious-input, prompt-injection, or adversarial-PDF testing
   exists.** There is no ingestion or generation pipeline yet for such tests
   to exercise meaningfully.

10. **Storage policies are a baseline, not the final design.** 0003 creates
    5 private buckets and one organization-scoped SELECT/INSERT policy pair
    covering all of them. Per-document-type restrictions (e.g. only
    `knowledge_manager` may write to `guideline-originals`), signed-URL
    issuance, and upload workflows are Sprint 1 scope.

11. **Audit immutability has documented, narrow bounds.** See
    `docs/database/schema.md` — append-only for every runtime role via a
    trigger, not merely a grant; overridable only through a direct,
    privileged database session, never through the application or the
    service-role key over HTTP. This is real defense-in-depth, not absolute
    immutability against a database superuser with direct access.
