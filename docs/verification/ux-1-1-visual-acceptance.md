# UX-1.1 — Visual Acceptance and Public Surface Redesign: Verification Record

This is a corrective workstream. UX-1 shipped real, working brand tokens
and component alignment, but the actual rendered public/auth surfaces
still failed visual acceptance — this record exists because a passing
build and a written closure report are not the same as a page that
actually looks right, and this mission's own governing rule is that
screenshots, not descriptions, are the evidence.

## Root cause of "the login page remains dominated by a full dark background"

This was not a design choice from UX-1 — it was a real, pre-existing
bug that UX-1's new light palette never actually reached the browser
for.

`packages/ui/tokens/index.ts`'s generated CSS (unchanged since ADR
0005, long before UX-1) emits:

```css
:root { /* light values */ }
:root[data-theme="dark"] { /* dark values */ }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { /* dark values */ }
}
```

Before this fix, `apps/web/app/layout.tsx`'s `<html>` element carried
**no `data-theme` attribute at all**. That means the third rule's
selector, `:root:not([data-theme="light"])`, matched for **any visitor
whose OS or browser prefers dark mode** — extremely common — silently
substituting `brandColorsDark`'s dark-navy canvas (`#0B141F`) and
lighter, lower-contrast button colors for every page, including the
brand-new UX-1 login page. There is no user-facing theme toggle
anywhere in the product; this was an unintended, non-user-controllable
side effect of infrastructure that predates the brand refresh, not a
deliberately shipped dark mode. This also explains the "pale blue
button with black text" observation: `brandColorsDark.primary` is a
lighter blue-400 tone, meant to be legible on a dark canvas, not white.

**Fix**: `apps/web/app/layout.tsx`'s `<html>` now carries
`data-theme="light"` explicitly, pinning the light palette regardless
of the visitor's OS setting. Per this mission's own scope rule ("dark
mode is out of scope unless it already exists as a fully functional
user-selectable mode... do not introduce a new dark-mode system"), this
is the correct fix — Noor has no functioning user-selectable dark mode
today, so nothing was removed; an unintended, silent override was
neutralized.

## The lower-left black circular "N" — investigated, not guessed

Confirmed by reading `apps/web/next.config.mjs`: no `devIndicators`
configuration existed. This is **Next.js's own built-in development-
mode indicator** (route/build status badge), rendered only by `next
dev`. It is not an application component, not a third-party dependency
(`package.json` has no matching library), and not a browser extension.
It does not render in `next build`/`next start` output or in a deployed
Vercel Preview — both always serve the production build.

**Action taken**: disabled via the documented, supported
`devIndicators: false` config flag (not a framework hack) so local
development screenshots taken for this mission represent the real,
shipped experience rather than a dev-only artifact.

## What was rebuilt

- **`apps/web/app/PublicShell.tsx`** (new) — shared header (logo +
  Sign in) and footer for every non-auth public page (`/`, `/403`,
  `/access-denied`, `/not-found`, `/error`). One definition, not
  copy-pasted CSS per page.
- **`apps/web/app/AuthShell.tsx`** (new) — `AuthSplitShell` (the
  two-column brand-panel/form-panel composition for `/login`) and
  `AuthCardShell` (the simpler centered-card composition for
  `/forgot-password`, `/update-password`, `/403`, `/access-denied`,
  `/not-found`, `/error`).
- **`apps/web/app/page.tsx`** — completely replaced. The Sprint 0.5
  placeholder (raw workspace links, "no clinical data or generation
  pipeline is wired yet") is gone. Real header/hero/capability-cards/
  workflow/trust/footer structure, accurate current-capability copy,
  one `<h1>`, and the four protected workspace routes are no longer
  exposed as raw public links — the only call-to-action is `/login`.
- **`apps/web/app/login/page.tsx`** — two-column `AuthSplitShell`: full
  logo (wordmark and descriptor both legible) on a white brand panel,
  form on a soft-cyan panel, corrected copy ("Sign in to NOOR" / "Access
  your organization's clinical intelligence workspace" / the
  mission-specified invite-only note).
- **`apps/web/app/forgot-password/page.tsx`**,
  **`apps/web/app/update-password/page.tsx`** — moved onto
  `AuthCardShell`.
- **`apps/web/app/403/page.tsx`**, **`apps/web/app/access-denied/page.tsx`**
  — moved onto `AuthCardShell`, gained a "Return to home" recovery
  action.
- **`apps/web/app/not-found.tsx`**, **`apps/web/app/error.tsx`** (new —
  neither existed before; Next.js was serving its unstyled defaults).
  `error.tsx` renders only Next's opaque `digest` as a correlation
  reference — never `error.message`/`error.stack` (verified by a
  regression test, not just written policy).
- **`apps/web/next.config.mjs`** — `devIndicators: false`.

## A real RTL bug found and fixed while auditing the new code

`PublicShell`'s footer used `sm:text-left` for the "NOOR — Clinical
Intelligence OS" line. Under `dir="rtl"`, `text-left` still forces
left-alignment — wrong for RTL, where that line should trail from the
reading start (the right edge). Fixed to the logical `sm:text-start`
(Tailwind 3.4.19 supports this), confirmed correct in the RTL
screenshot evidence below. No other hardcoded `ml-`/`mr-`/`pl-`/`pr-`/
`text-left`/`text-right`/`left-`/`right-` utility exists anywhere in
the new/redesigned files (verified by grep, not assumed) — every other
layout uses `flex`/`gap`, which is direction-agnostic by construction.

## Visual evidence

All screenshots are real, captured with Playwright + real Chromium
against the actual local dev server (`next dev`, the same code that
built and passed lint/typecheck/tests), synthetic content only, no
real user data. Files: `docs/verification/screenshots/ux-1-1/`.

| Route | Viewport | Browser | LTR/RTL | Screenshot | Status |
|---|---|---|---|---|---|
| `/` | 1440×1000 | Chromium | LTR | `landing-desktop-1440x1000.png` | ✅ |
| `/` | 1280×800 | Chromium | LTR | `landing-desktop-1280x800.png` | ✅ |
| `/` | 1024×768 (tablet) | Chromium | LTR | `landing-tablet-1024x768.png` | ✅ |
| `/` | 768×1024 (tablet) | Chromium | LTR | `landing-tablet-768x1024.png` | ✅ |
| `/` | 430×932 | Chromium | LTR | `landing-mobile-430x932.png` | ✅ |
| `/` | 390×844 | Chromium | LTR | `landing-mobile-390x844.png` | ✅ |
| `/` | 360×800 | Chromium | LTR | `landing-mobile-360x800.png` | ✅ |
| `/login` | 1440×1000 | Chromium | LTR | `login-desktop-1440x1000.png` | ✅ |
| `/login` | 1280×800 | Chromium | LTR | `login-desktop-1280x800.png` | ✅ |
| `/login` | 1024×768 (tablet) | Chromium | LTR | `login-tablet-1024x768.png` | ✅ |
| `/login` | 768×1024 (tablet) | Chromium | LTR | `login-tablet-768x1024.png` | ✅ |
| `/login` | 430×932 | Chromium | LTR | `login-mobile-430x932.png` | ✅ |
| `/login` | 390×844 | Chromium | LTR | `login-mobile-390x844.png` | ✅ |
| `/login` | 360×800 | Chromium | LTR | `login-mobile-360x800.png` | ✅ |
| `/login` | 1440×1000 | Chromium | **RTL** (simulated — see note) | `login-desktop-1440x1000-rtl.png` | ✅ |
| `/login` | 390×844 | Chromium | **RTL** (simulated) | `login-mobile-390x844-rtl.png` | ✅ |
| `/forgot-password` | 1440×1000 | Chromium | LTR | `forgot-password-desktop-1440x1000.png` | ✅ |
| `/forgot-password` | 390×844 | Chromium | LTR | `forgot-password-mobile-390x844.png` | ✅ |
| `/403` | 1440×1000 | Chromium | LTR | `403-desktop-1440x1000.png` | ✅ |
| `/403` | 390×844 | Chromium | LTR | `403-mobile-390x844.png` | ✅ |
| `/access-denied` | 1440×1000 | Chromium | LTR | `access-denied-desktop-1440x1000.png` | ✅ |
| `/access-denied` | 390×844 | Chromium | LTR | `access-denied-mobile-390x844.png` | ✅ |
| `/access-denied` | 1440×1000 | Chromium | **RTL** (simulated) | `access-denied-desktop-1440x1000-rtl.png` | ✅ |

**RTL note, honest**: Noor has no routed Arabic locale yet (no
`/ar/...` path, no i18n routing) — that is out of this mission's scope
entirely. The RTL screenshots force `dir="rtl"`/`lang="ar"` on the live
DOM via `page.evaluate()` immediately before capture, the same
technique the pre-existing `/design-system` page's own RTL sample
already uses. This proves the token system and flex-based layouts
mirror correctly (confirmed: the two-column login layout flips, the
logo itself is never mirrored, form alignment flips, the footer bug
above is fixed) — it does not prove real Arabic typography or content,
since no real Arabic copy exists on these pages yet.

**What was confirmed by looking at the actual images, not assumed**:
logo reads clearly at every size down to the mobile brand panel; the
`Sign in` button is Clinical Blue with white text at full contrast (no
more pale-button-black-text); the form card has real visible separation
from the soft-cyan surface behind it; no horizontal overflow at any
captured width; the RTL login screenshot shows the two-column order
correctly reversed with the logo intact and unmirrored.

## Accessibility review

- **Contrast**: unchanged from UX-1's verified values (`docs/design/noor-accessibility-review.md`)
  now actually reaches the browser correctly since the dark-mode
  override is fixed — Clinical Blue button 8.18:1, Deep Navy headings
  14.60:1 against the real white canvas, not the dark one.
- **Heading structure**: `/` and `/login` each verified (by regression
  test, not just visual inspection) to contain exactly one `<h1>`.
  `/forgot-password`, `/update-password`, `/403`, `/access-denied`,
  `/not-found`, `/error` each render exactly one `<h1>` via
  `PageHeader`/`PermissionDeniedPanel`.
- **Password toggle**: `PasswordInput`'s show/hide control (unchanged
  from before this mission) already carries `aria-label`— confirmed
  present in the login screenshot ("Show" button, keyboard-reachable).
- **Focus/keyboard**: no new custom focus-management code was
  introduced; every interactive element is a native `<button>`/`<a>`/
  `<input>` using the existing `accent`-colored focus-visible ring from
  UX-1.
- **Reduced motion**: no new animation was introduced.
- **Touch targets**: the primary CTA and nav "Sign in" link both use
  the existing `Button`/link padding scale (≥44px effective height at
  the `md` button size used throughout).

**Not done, honestly**: no automated axe/Lighthouse scan was run
(pre-existing repository gap, unchanged by this mission — see
`KNOWN_LIMITATIONS.md`).

## Regression review

- **Auth**: `LoginForm`/`ForgotPasswordForm`/`UpdatePasswordForm` —
  unchanged logic, only their surrounding page shell moved.
- **Permissions/workspaces**: `WorkspaceHeader` and all five workspace
  layouts (`admin`/`clinician`/`knowledge`/`quality`/`reviewer`) —
  untouched.
- **Guideline Registry, upload, processing, extraction review, OCR
  review**: no files under these areas were touched by this mission.
- **Build**: `next build` — clean, 0 warnings, all 23 routes present
  (22 from before + the new `/_not-found`).
- **Backend**: `apps/worker`'s full 79-assertion pytest suite —
  unchanged, still passing, confirming zero backend impact from a
  frontend-only corrective mission.

## Local verification — real commands, real output

```
$ npx tsc --noEmit                          (apps/web)     → clean, 0 errors
$ npx next lint                             (apps/web)     → "No ESLint warnings or errors"
$ npx next build                            (apps/web)     → ✓ Compiled successfully, 0 warnings,
                                                               23 routes (new: /_not-found; / and
                                                               403/access-denied now prerender static)
$ [15 test files run individually]          (apps/web)     → 15/15 PASS, including the new
                                                               public-pages-content.test.ts
$ npx tsc --noEmit                          (packages/ui)             → clean, 0 errors
$ npx tsc --noEmit && npx tsx ...test.ts    (packages/clinical-schemas) → clean; 6/6 PASS
$ python -m pytest tests/ -q                (apps/worker)  → 79 passed, unchanged
```

## Screenshot method (honest account)

Real Chromium via `@playwright/test` (newly installed as a dev
dependency of `apps/web` for this mission — not previously present in
the repository), driving the actual `next dev` server on
`localhost:3100` with the same `.env.local` used for real local
development. No mock data, no design tool, no static mockup — every
screenshot is the real rendered application.

## Hosted verification — real, done

The five commits above were pushed to `origin/main`
(`f52f2e085d283c8c90785a20992cb80ebbee8a72`). GitHub Actions' `PR
Pipeline` workflow run for that exact commit completed
`status: completed`, `conclusion: success` — confirmed via the GitHub
REST API.

A real Vercel Preview deployment was then triggered:
`https://noor-hux9lqo3h-abdullah-wagihs-projects.vercel.app`, status
**`● Ready`** (confirmed via `vercel inspect`). The real build log shows
a clean `next build` — `✓ Compiled successfully`, all 23 routes present
including the new `/_not-found`, and `/`/`/403`/`/access-denied` now
correctly prerender as **static** content (`○`), matching the local
build exactly — followed by `Deployment completed`.

**What a headless check still cannot get past**: this Vercel team's
Deployment Protection (SSO gate) returns a `302` to `vercel.com/sso-api`
for every direct request, including `/login` — the same pre-existing
constraint documented in UX-1's own verification record, not a new
issue. A real browser-rendered check of the deployed Preview therefore
still requires the user's own authenticated Vercel session; the local
Playwright screenshots above are the real visual evidence for this
mission's acceptance gate.

## What was not done (honest account)

- **Hosted Vercel Preview browser-rendered verification** — see
  "Hosted verification" in the closure report; this Vercel team's own
  SSO Deployment Protection blocks any headless render check of a live
  Preview URL, a pre-existing, documented constraint from UX-1 that
  applies identically here.
- **No automated accessibility (axe/Lighthouse) or Playwright visual-
  regression suite was added** — the screenshots above are real
  evidence for this mission's one-time visual acceptance gate, not a
  standing, repeatable visual-regression test suite. Adding one is a
  reasonable future improvement, not attempted here to keep this
  corrective mission scoped to what was actually asked.
- **No real Arabic content or routed locale exists** — the RTL
  screenshots are a layout-mirroring simulation, not proof of real
  Arabic typography in production use.

## Final status

**UX-1.1 — Implementation Complete, Pending User Visual Acceptance.**

This status is deliberate, not a placeholder — this mission's own
governing rule is that visual acceptance is the user's call, not a
self-declared outcome of a passing build. Do not change this line to
"Complete and Visually Accepted" without the user having actually
reviewed the screenshots above and said so.
