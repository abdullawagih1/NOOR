# Sprint Current: UX-1.1 — Visual Acceptance and Public Surface Redesign

**Status:** UX-1.1 — Implementation Complete, Pending User Visual
Acceptance. This is a corrective workstream: UX-1 shipped real brand
tokens, but the actual rendered public/auth pages still failed visual
acceptance against real screenshots. See
`docs/verification/ux-1-1-visual-acceptance.md` for the full record,
including the root-cause diagnosis and 22 real Playwright screenshots.

Workstreams `S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D1`/`S1-D2`/`UX-1` closed
in prior sessions. This sprint is workstream `UX-1.1`.

## Governing principle

Screenshots, not descriptions, are the acceptance evidence. This
mission does not close itself — the final status stays "Implementation
Complete, Pending User Visual Acceptance" until the user reviews the
actual screenshots and says so.

## Root cause found (not assumed)

The "dark login page" complaint was not a design decision — it was a
real, pre-existing bug: `apps/web/app/layout.tsx`'s `<html>` element
carried no `data-theme` attribute, so `packages/ui/tokens/index.ts`'s
`@media (prefers-color-scheme: dark)` rule silently applied the dark
palette to every page for any visitor on a dark-mode OS. There is no
user-facing theme toggle anywhere in the product — this was never a
deliberate feature. Fixed by pinning `data-theme="light"` on `<html>`.

The lower-left black "N" was investigated, not guessed: confirmed by
reading `next.config.mjs` (no `devIndicators` config existed) to be
Next.js's own built-in development-mode indicator — never present in
production or a deployed Vercel Preview. Disabled locally via the
documented `devIndicators: false` flag for clean screenshots.

## Objectives

- [x] Root landing page (`/`) completely redesigned — the Sprint 0.5
      placeholder (raw workspace links, "no clinical data or generation
      pipeline is wired yet") is gone. Real header/hero/capability-
      cards/workflow/trust/footer structure with accurate current-
      capability copy; protected workspace routes are no longer exposed
      as raw public links.
- [x] Login page redesigned as a two-column light composition (white
      brand panel with the full logo legible, soft-cyan form panel) —
      no more full dark background, no more logo-as-pasted-rectangle.
- [x] Forgot-password / update-password pages moved onto the same
      shared `AuthCardShell`.
- [x] 403 / access-denied pages moved onto `AuthCardShell`, gained a
      real recovery action. `not-found.tsx` / `error.tsx` created —
      neither existed before (Next.js was serving unstyled defaults).
- [x] A real RTL bug found and fixed: the footer's `sm:text-left` did
      not flip under `dir="rtl"` — corrected to logical `sm:text-start`.
- [x] Content-regression tests added (`public-pages-content.test.ts`) —
      bans the retired Sprint 0.5 phrases, enforces exactly one `<h1>`
      on `/` and `/login`, enforces the shared shells are actually used,
      guards the `data-theme="light"` fix against regression.
- [x] 22 real Playwright/Chromium screenshots captured — desktop/
      tablet/mobile for `/` and `/login`, desktop+mobile for
      `/forgot-password`/`/403`/`/access-denied`, plus 3 RTL-simulated
      captures. See `docs/verification/screenshots/ux-1-1/`.
- [x] Full regression verification — `apps/web` typecheck/lint/build
      clean (0 warnings), all 15 unit-test files pass, `packages/ui`
      typecheck clean, `packages/clinical-schemas` typecheck+tests
      pass, `apps/worker`'s full 79-assertion suite unchanged.
- [ ] User visual acceptance of the screenshots — **pending**.

## Explicitly out of scope this task (per the mission)

Any change to database schema, RLS, permissions, processing states,
extraction states, OCR states, review decisions, eligibility rules,
Worker orchestration, or Storage authorization. No i18n/routed-Arabic-
locale work — the RTL screenshots are a layout-mirroring simulation on
the existing English copy, not new Arabic content.

## Next step

```text
User Visual Review of UX-1.1 Screenshots
```

Do not begin S1-D3 until the user has reviewed and approved. See
`MASTER_BACKLOG.md`.
