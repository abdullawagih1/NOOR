# Sprint Current: LX-1.2 — Production Cinematic Landing Implementation and Controlled Integration

**Status:** LX-1.2 — Production Cinematic Landing Integration
Complete, Pending LX-1.3 Hardening and User Preview Approval. See
`docs/verification/lx-1-2-production-integration.md` for the full
record.

This is a **continuation of the same separate, dedicated
landing-experience workstream** as LX-1.0/LX-1.1/LX-1.1.1 — not a
platform sprint. It does not touch the database, RLS, permissions,
Worker, or any backend code. Production continues to serve the legacy
landing throughout this mission; only a protected Vercel Preview runs
the cinematic experience. The platform's next step remains
`S1-E3 — Hybrid Retrieval`, unaffected.

## What this mission does

Promotes the user-approved LX-1.1.1 cinematic prototype from an
internal Development/Preview-only route into production-integrated
architecture: a server-controlled feature flag at `/`, the legacy
landing preserved and componentized as an immediate rollback path, a
fixed post-login redirect defect, a profiled and optimized Scene 5,
production-grade SEO/metadata, and a real, rehearsed Vercel Preview
deployment and rollback. The public production landing was never
enabled — production stays on `legacy` throughout.

## Objectives

- [x] Server-controlled feature flag (`NOOR_PUBLIC_LANDING_EXPERIENCE`), fails closed to `legacy` on any invalid value, never a `NEXT_PUBLIC_` variable.
- [x] `LegacyPublicLanding.tsx` extraction — byte-identical copy to the pre-LX-1.2 page, immediately available as a rollback target.
- [x] `CinematicPublicLanding.tsx` extraction — the approved LX-1.1.1 markup, now a real production component shared by both the public root route and the internal design/Preview route (no duplicated scene markup).
- [x] `/` selects exactly one experience server-side per request — no dual render, no client-side switch, no hydration mismatch.
- [x] Post-login redirect fixed: one canonical resolver (`resolvePostLoginDestination`), never returns `/`, verified by unit tests AND a real end-to-end run against the hosted Supabase project with a synthetic account.
- [x] Auth-aware public CTA: "Sign in" unauthenticated, "Open NOOR" → authorized workspace when authenticated.
- [x] Scene 5 profiled (real `renderer.info` diagnostics) and optimized (5 concrete changes) — real GPU FPS 40 → 56-61.
- [x] `robots.txt`/`sitemap.xml` added (neither existed before); page-specific `generateMetadata()` for `/`; defense-in-depth noindex on the Preview-reachable internal route.
- [x] A real mobile performance regression (introduced by the auth-check itself) found and fixed: `getSession()` fast path before `getUser()`, Lighthouse Performance 0.87 → 0.94.
- [x] Two real, pre-existing accessibility violations found and fixed in `AuthShell.tsx` (missing `<main>` landmark), unrelated to cinematic content.
- [x] Error containment reviewed (found already adequate from LX-1.1.1 — no gap requiring new code).
- [x] Route/bundle isolation reconfirmed via live HTTP response inspection, not just build-manifest inspection.
- [x] Real Vercel Preview deployed (cinematic-enabled), Deployment Protection confirmed active throughout, never disabled.
- [x] Rollback rehearsed for real: cinematic → legacy → cinematic, ~57 seconds, zero code revert.
- [x] Clean production-integration recordings + screenshots captured and inspected (frame-extracted, not trusted from file size alone).
- [x] 7 new docs + 2 verification reports + a media index written; 4 existing docs updated.
- [x] 3 new committed tests + 2 updated; all 25 `apps/web` test files, typecheck, and lint pass.
- [x] No backend/database/Worker file touched — confirmed via `git status`.

## Real bugs/gaps found and fixed (or honestly documented) this workstream

1. **The reported post-login redirect defect, confirmed at the code level before any fix**: `signInWithPassword` redirected to `next`, which defaulted to `"/"` — every plain sign-in bounced back to the public landing. Fixed with `resolvePostLoginDestination()`.
2. **A real desktop-vs-mobile blind spot avoided before shipping**: an early draft of the redirect resolver checked membership status before checking the requested path, which would have broken the password-reset flow (`/update-password`) for any caller whose membership state was irrelevant to that flow. Caught by reasoning through the consequence, restructured before it ever shipped.
3. **Scene 5's real FPS outlier**, profiled (not guessed) and fixed with 5 targeted changes — see `NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`.
4. **A real mobile Lighthouse regression this mission's own auth-aware CTA introduced**, found via honest before/after measurement, fixed via a `getSession()` fast path.
5. **`landmark-one-main`/`region` axe violations in `AuthShell.tsx`**, pre-existing, found by broader scan coverage than any prior mission ran, fixed.
6. **A genuine Next.js 15 framework limitation** (`<meta name="description">` renders in `<body>`, not `<head>`, on any dynamic route) — investigated to its real root cause, confirmed pre-existing on an untouched route (`/login`), documented honestly rather than chased to a risky, out-of-scope fix.
7. **Deployment Protection blocked direct HTTP verification of the real Preview URL** — no bypass token was available this session (a one-time dashboard action, not reachable via CLI/API). Substituted with authenticated build-log inspection (route table match) plus exhaustive local-production-build verification of the identical code — recorded as a real, bounded limitation, not silently worked around or claimed complete.

## Next step

```text
User review of the protected production-build Preview,
followed by LX-1.3 performance and accessibility hardening
```

Do not enable the cinematic landing publicly in Production. Do not
begin LX-1.3 automatically. The platform's own next step remains
`S1-E3 — Hybrid Retrieval`, unaffected by this workstream.
