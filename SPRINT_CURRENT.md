# Sprint Current: Sprint 0.5 — Hosted Infrastructure & Design System Activation

**Status:** Technically Complete — Hosted Verification Blocked. One
dashboard-only action remains (see `PROJECT_STATE.md` §5/§6); every check
reachable via API/CLI passed against real hosted infrastructure.

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
- [ ] Full authenticated Preview HTTP smoke test — **BLOCKED**, needs
      "Protection Bypass for Automation" enabled in the Vercel dashboard
      (no CLI/API path exists for this — confirmed this session)
- [ ] Clinical domain confirmed (blocked — awaiting your decision)

## Next sprint

One dashboard action remains: enable Protection Bypass for Automation in
Vercel (`noor` project → Settings → Deployment Protection), then re-run
`scripts/smoke-test-web.mjs` with `BYPASS_TOKEN` set. Once that closes (or
is explicitly accepted as an ongoing manual gate): **Sprint 1 — Guideline
Registry Schema and Lifecycle** (see `MASTER_BACKLOG.md`).
