# Sprint Current: Sprint 0.5 — Hosted Infrastructure & Design System Activation

**Status:** In progress. Two items are genuinely blocked on external
decisions (see `PROJECT_STATE.md` §5/§6); everything else in scope is done
and verified.

## Objectives

- [x] Re-verify Sprint 0's local foundation before changing anything
- [x] Push the repository to GitHub for real (was never pushed before)
- [x] Get CI actually running and passing on GitHub Actions (twice, now)
- [x] Add a push trigger + secret-scan job to CI
- [x] Noor Design System: tokens, 32 components, `/design-system` showcase,
      ADR 0005, accessibility contrast audit
- [x] Restyle every existing route onto the design system
- [x] Password reset flow (forgot-password, update-password), signup
      policy documented (invite-only)
- [x] Next.js security-advisory decision — spiked and applied the 15.5.21
      upgrade, ADR 0006
- [x] Real HTTP smoke test against a local `next start` + real local
      Supabase (10/10 passed)
- [x] Vercel: authenticated, project linked and correctly configured
      (monorepo root directory fix), Preview build succeeds
- [ ] Hosted Supabase Development project — **BLOCKED**, needs credentials
      (`SUPABASE_ACCESS_TOKEN` or you running `supabase login`)
- [ ] Full HTTP verification of the deployed Vercel Preview — **BLOCKED**
      by this team's default Vercel Authentication (Deployment Protection);
      needs a decision (disable it, or generate a Protection Bypass secret)
- [ ] Clinical domain confirmed (blocked — awaiting your decision)

## Next sprint

Sprint 0.5 is not complete until both blocked items above close. Once they
do: apply migrations to the hosted project, re-run the RLS suite and
`scripts/smoke-test-web.mjs` against it, wire real env vars into Vercel.
Only then: **Sprint 1 — Guideline Registry Schema and Lifecycle**
(see `MASTER_BACKLOG.md`).
