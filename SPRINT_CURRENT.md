# Sprint Current: Sprint 0.5 — Hosted Infrastructure & Design System Activation

**Status:** Complete and Hosted-Verified. The one dashboard-only action
(Vercel Protection Bypass for Automation) has been configured by the user
and the protected Preview smoke test has passed 10/10 with body-content
verification. See `PROJECT_STATE.md` §-3 and
`docs/verification/sprint-0.5-hosted-verification.md`.

## Objectives

- [x] Re-verify Sprint 0's local foundation before changing anything
- [x] Push the repository to GitHub for real (was never pushed before)
- [x] Get CI actually running and passing on GitHub Actions (three times, now)
- [x] Add a push trigger + secret-scan job to CI
- [x] Noor Design System: tokens, 32 components, `/design-system` showcase,
      ADR 0005, accessibility contrast audit
- [x] Restyle every existing route onto the design system
- [x] Password reset flow (forgot-password, update-password), signup
      policy documented (invite-only)
- [x] Next.js security-advisory decision — spiked and applied the 15.5.21
      upgrade, ADR 0006
- [x] Environment variables audited, standardized, runtime-validated on
      both Web and Worker; a real Worker auth gap found and fixed
- [x] Real HTTP smoke test against a local `next start` + real local
      Supabase (10/10 passed)
- [x] Vercel: authenticated, project linked and correctly configured
      (monorepo root directory fix), Preview build succeeds
- [x] **Hosted Supabase Development project connected, migrated, and
      verified** — 26 Auth/RLS/Authorization/Feature-flag/Audit assertions
      + 8 Storage assertions, all with real JWTs, all passed. One real
      finding (unnecessary `anon` grants) discovered and fixed via a new
      migration. See `docs/verification/sprint-0.5-hosted-verification.md`.
- [x] Vercel Preview environment configured with hosted Development values,
      redeployed, Deployment Protection kept enabled (not disabled)
- [x] Supabase Auth URLs configured (explicit allowlist, no wildcards)
- [x] Synthetic hosted test data created, verified against, and fully
      cleaned up
- [x] Full authenticated Preview HTTP smoke test — Protection Bypass for
      Automation configured by the user in the Vercel dashboard;
      `scripts/smoke-test-web.mjs` run against the protected Preview with
      the bypass token, 10/10 checks passed, all 6 body-content checks
      confirmed real Noor content (not the Vercel SSO page). See
      `docs/verification/sprint-0.5-hosted-verification.md`.
- [ ] Clinical domain confirmed — separate, Sprint 1 decision (G-03), not
      a Sprint 0.5 blocker (awaiting your decision on guideline sourcing)

## Next sprint

Sprint 0.5 is closed. **Sprint 1 — Guideline Registry Schema and
Lifecycle** (see `MASTER_BACKLOG.md`). Playwright browser-driven E2E stays
on the backlog as a documented pre-Controlled-Beta requirement (see
`KNOWN_LIMITATIONS.md`), not a Sprint 1 blocker.
