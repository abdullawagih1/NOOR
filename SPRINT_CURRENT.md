# Sprint Current: Sprint 0 — Platform Foundation

**Status:** Technically complete, awaiting hosted-infrastructure verification.
See `PROJECT_STATE.md` for the full gap report and exit-criteria review.

This sprint was remediated in a follow-up session after an independent
review found the prior delivery's repository had no `.git`, a pass-through
auth middleware, an unseeded permissions table, and RLS verified only
against plain Postgres. That review's findings were reproduced and fixed —
see `CHANGELOG.md` for the itemized diff.

## Objectives

- [x] Repository audit (reproduced independently this session, not assumed)
- [x] Git repository actually initialized on `main` (was missing entirely)
- [x] Monorepo structure, cleaned of tracked build artifacts
- [x] Identity/tenancy/RLS foundation, migrated and tested (0001)
- [x] Permissions seeded and mapped to roles; auth-hardening triggers (0002)
- [x] Storage foundation: 5 private buckets + RLS (0003)
- [x] Real Supabase Auth: SSR clients, session refresh, login/logout/callback,
      permission-gated workspace routes, controlled 403/access-denied pages
- [x] RLS re-verified against a real local Supabase stack (not just plain
      Postgres) — real `authenticated` role, real GoTrue `auth.uid()`, a
      real JWT exercised against PostgREST
- [x] CI workflow corrected (was silently resolving the wrong lockfile in
      this npm-workspaces monorepo) and every job's commands independently
      reproduced locally
- [x] Worker scaffold with health endpoint and job contract
- [x] Intended Use draft
- [x] Initial Risk Register
- [x] ADR directory
- [x] PROJECT_STATE.md — rewritten to match actual verified state
- [ ] Hosted Supabase project (blocked — no credentials/infra access in this
      environment; **top Sprint 1 task**, downgraded risk since the schema/
      RLS/auth design is now proven locally against real Supabase)
- [ ] CI actually executed on GitHub Actions (blocked — no push access; the
      intended remote exists and was confirmed empty via `git ls-remote`)
- [ ] Vercel deployment (blocked — no hosted Supabase project yet to point at)
- [ ] Clinical domain confirmed (blocked — awaiting your decision)
- [ ] Named clinical reviewer confirmed (blocked — awaiting your decision)

## Next sprint

Sprint 1 backlog: see `MASTER_BACKLOG.md`. First recommended task:
**S1-08 (hosted Supabase project)** — it unblocks S1-01 through S1-06 and
lets the now-locally-verified Sprint 0 RLS suite be re-verified against
hosted infrastructure.
