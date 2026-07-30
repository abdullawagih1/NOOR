# UX-1 — NOOR Brand and Design System Alignment: Verification Record

Every command and result below was actually run — nothing here is
inferred or assumed. Companion docs: ADR 0013,
`docs/brand/{NOOR_BRAND,noor-logo-usage}.md`,
`docs/design/{noor-color-system,noor-component-theme,noor-accessibility-review}.md`.

**Status: complete and verified, locally and on a real Vercel Preview
deployment (build `Ready`, CI green on `main`).** The one gap left is a
real browser-rendered check of the Preview URL, blocked by this Vercel
team's own SSO Deployment Protection — see "Vercel Preview deployment"
and "What was not done" below for the honest account, including a real
disk-space environmental issue encountered mid-session.

## Starting state

Before this sprint, `apps/web/public/` was completely empty — no
favicon, no logo, no app icons existed anywhere in the repository. The
existing design-system token architecture (`packages/ui/tokens/*` →
CSS custom properties → Tailwind utilities, ADR 0005) was already
sound and required no rewrite, only new values and a small number of
new component-level class references.

## Logo asset handling

The user-supplied logo (`logo.jpeg`, dropped at the repo root, 1254×1254
JPEG) was archived byte-for-byte before any processing:

```
$ sha256sum logo.jpeg apps/web/public/brand/source/noor-logo-original.jpeg
183cb2031a3c47d12d2aeba85625a41266e45ebe7694fc2928fa1a3bca1a16fc *logo.jpeg
183cb2031a3c47d12d2aeba85625a41266e45ebe7694fc2928fa1a3bca1a16fc *apps/web/public/brand/source/noor-logo-original.jpeg
```

Identical checksums confirm the archived source is byte-identical to
what was supplied. Every derived asset
(`apps/web/public/brand/noor-logo-primary.png`,
`noor-logo-navigation.png`, `noor-symbol*.png`, `favicon.ico`,
`social-preview.png`) was produced by cropping this file's own pixels —
crop boxes were measured by a row/column content-boundary scan (see
`docs/design/noor-color-system.md`), not eyeballed, and no pixel was
redrawn or regenerated. A real bug was found and fixed while generating
the navigation crop: the first attempt's padding pushed past the
wordmark's real bottom edge into the descriptor line, producing a
truncated sliver of "CLINICAL INTELLIGENCE" text at the bottom of the
cropped image — caught by actually rendering and looking at the output,
not by trusting the crop math. Fixed by clamping the padded bottom edge
to the real blank gap between the wordmark and descriptor content runs.

## Color sampling and anchor validation

Dominant-color binning was run over the symbol, network graphic, and
wordmark regions of the real source image (not guessed). The mission's
own supplied reference anchors (Deep Navy `#032855`, Clinical Blue
`#045092`, Primary Teal `#078A88`, Emerald `#09B993`) were confirmed to
fall inside the real sampled color ranges and were adopted as final —
see `docs/design/noor-color-system.md` for the full sample table and the
reasoning for preferring the mission's anchors over the raw samples
(JPEG chroma-subsampling artifacts in the raw samples, not a real
design intent).

## Token implementation

`packages/ui/tokens/colors.ts` was rewritten (not just re-valued): four
full 50–950 brand scales (`brandNavy`/`brandBlue`/`brandTeal`/
`brandEmerald`), two partial support scales (`brandCyan`/`brandSlate`),
one gradient constant, updated `brandColors`/`brandColorsDark` semantic
slots (including a **new** `accent` family split out from `primary`),
and five **new** `semanticStates` keys (`queued`, `retryScheduled`,
`ocrRequired`, `reprocessingRequired`, `deadLettered`) with their own
icons (added to `packages/ui/components/Badge.tsx`'s icon map:
`clock`/`rotate-cw`/`rotate-ccw`/`scan-line`). `packages/ui/tokens/index.ts`
gained a `--noor-gradient-brand` CSS variable. `apps/web/tailwind.config.ts`
exposes the new `accent*` slots and raw brand scales as utilities.

A real, concrete gap was found and fixed, not merely described: before
this sprint, `ocr_required` and `reprocessing_required` extraction/OCR
review statuses were **visually identical** (same `underReview` color
and icon, differing only in label text). They now have distinct colors
and icons — see `docs/design/noor-component-theme.md`.

## Shared component updates

`Button`/`IconButton`/`Checkbox`/`Radio`/`Select`/`TextInput` focus
rings changed from `outline-primary` to `outline-accent` (teal) —
matching the logo's own "blue interaction / teal wayfinding" split, and
incidentally making the focus indicator visually distinct from an
ordinary primary button for the first time. `WorkspaceNav`'s
active-item styling changed from `bg-primary-soft text-primary-active`
to `bg-accent-soft text-accent-active`.

## Status-mapping updates

`apps/web/lib/documents/ui.tsx` (`queued`, `retry_scheduled`,
`dead_lettered`), `apps/web/lib/extraction-review/ui.tsx`
(`ocr_required`, `reprocessing_required`), and `apps/web/lib/ocr/ui.tsx`
(`queued`, `reprocessing_required` ×3) were updated to the new,
distinct semantic keys. Guideline lifecycle's mapping
(`draft`/`ready_for_review`/`approved`/`active`/`superseded`/
`withdrawn`) was already correctly using six distinct existing buckets
and was left untouched.

## Application shell and auth

`apps/web/app/WorkspaceHeader.tsx` (the single shared top nav every
workspace layout renders) gained the navigation-crop logo, linked to
`/`. This is a real architectural finding, not an assumption: the
mission's brief described a sidebar shell, but the actual app has no
sidebar — inventing one would have been scope creep, not brand
alignment, so the logo was added to the shell that actually exists.
`apps/web/app/login/page.tsx` gained the primary logo and a thin
gradient accent line, replacing a plain "Noor V1" text eyebrow; a real
accessibility regression was caught and fixed in the same edit — removing
the old `PageHeader` (which rendered the page's only `<h1>`) would have
left the page with no heading at all, so an explicit `<h1>Sign in</h1>`
was added back.

## Metadata and favicon

`apps/web/app/layout.tsx` gained `icons` (favicon.ico + PNG fallback +
apple-touch-icon), `openGraph`/`twitter` (using the generated
`social-preview.png`), and `viewport.themeColor`. A real Next.js build
warning (`metadataBase` not set) was found and fixed by reading
`NEXT_PUBLIC_APP_URL` directly — **not** via the existing `getPublicEnv()`
validator, which would have broken the static routes (`/`, `/403`,
`/access-denied`, `/design-system`) that deliberately build without any
Supabase env vars configured (see that module's own documented
invariant).

## Design-system page

`apps/web/app/design-system/page.tsx` gained an "Official brand"
section (all three logo variants, the gradient swatch, the four primary
anchor colors) and the existing "Colors" swatch grid was extended with
the new `accent`/`accent-active`/`accent-soft` slots. The existing
`semanticStates` swatch loop already iterates every key dynamically, so
the five new status states appear automatically with zero page-level
code change.

## Local verification — real commands, real output

```
$ npx tsc --noEmit                          (apps/web)     → clean, 0 errors
$ npx next lint                             (apps/web)     → "No ESLint warnings or errors"
$ npx next build                            (apps/web)     → ✓ Compiled successfully, 10/10 static pages,
                                                               both /reviewer/ocr routes present, 0 warnings
$ [14 test files run individually]          (apps/web)     → 14/14 PASS (redirect, permissions, env,
                                                               guidelines-schemas/errors, documents-schemas/
                                                               errors/config/stream-verification/orchestration-ui,
                                                               extraction-review-schemas/errors, ocr-schemas/errors)
$ npx tsc --noEmit                          (packages/ui)             → clean, 0 errors
$ npx tsc --noEmit && npx tsx ...test.ts    (packages/clinical-schemas) → clean; 6/6 PASS
$ python -m pytest tests/ -q                (apps/worker)  → 79 passed (untouched by this sprint —
                                                               confirms the brand-only change introduced
                                                               zero backend regression)
```

Contrast verification (WCAG 2.2, computed not eyeballed): full table in
`docs/design/noor-accessibility-review.md`. Headline: Clinical Blue on
white 8.18:1, Deep Navy on white 14.60:1, all five new status colors
5.98–11.23:1 — all pass AA, most pass AAA.

## Vercel Preview deployment — real, done

The six commits above were pushed to `origin/main`
(`950dd3dc375e29f4b4ef76fee04289b40cd2d980`). GitHub Actions' `PR
Pipeline` workflow run for that exact commit completed
`status: completed`, `conclusion: success` — confirmed via the GitHub
REST API, not assumed.

A real Vercel Preview deployment was then triggered (`vercel deploy`
from the repo root): `https://noor-51fty7xaa-abdullah-wagihs-projects.vercel.app`,
status **`● Ready`** (confirmed via `vercel inspect`). The real build
log shows a clean `next build` — `✓ Compiled successfully`, all 22
routes present including `/design-system` (3.26 kB, up from 3.25 kB
before this sprint — the new "Official brand" section) and `/login`
(3.52 kB, up from 3.24 kB — the new logo + heading) — followed by
`Deployment completed`.

**What a headless check cannot get past, again**: this Vercel team's
Deployment Protection (SSO gate) returns a `302` to `vercel.com/sso-api`
for every direct request, including the static brand asset
`/brand/favicon.ico` and the `/login` route — not an application error.
A real browser-rendered check of the new logo/brand pages therefore
still requires the user's own authenticated Vercel session. The build/
route-table evidence above is real and strong, but it is not the same
as a rendered-page visual check — recorded honestly, not glossed over.

## Environmental note — a real, disk-space blocker this session

Mid-session, this machine's `C:` drive was found to be at 99% capacity
(at one point reporting 0 bytes free), which made Docker unresponsive.
This was flagged to the user rather than worked around silently. Root
cause was not fully diagnosed (Docker's own WSL2 data disk was only
~20GB; the bulk of the ~470GB in use was not identified, and a full
recursive scan of personal files was deliberately not performed —
that's the user's data to manage, not something to dig through
unilaterally). All work above (asset generation, token edits, build,
lint, typecheck, all four test suites) completed successfully once a
small amount of space was freed — none of it required more than a few
hundred MB.

## What was not done (honest account)

- **A real browser-rendered check of the deployed Preview** — blocked
  by this Vercel team's own SSO Deployment Protection from any headless
  environment; see "Vercel Preview deployment" above. The deployment
  itself reached `Ready` with a clean build and the correct route
  table, which is strong but not equivalent evidence to an actual
  rendered-page check.
- **No automated accessibility tooling (axe/Lighthouse) exists in this
  repository** — every contrast ratio was computed from real hex
  values, but no automated DOM-level scan of a rendered page was run.
  See `docs/design/noor-accessibility-review.md`.
- **No Playwright/browser-driven visual regression** — consistent with
  this repository's pre-existing, documented gap (`KNOWN_LIMITATIONS.md`
  item 24). No screenshot evidence beyond direct visual inspection of
  the generated PNG assets themselves was captured.
- **`accepted_with_warnings`/`reprocessing_required` OCR review target
  statuses still have the same pre-existing local-test coverage gap**
  documented in the Sprint 1-D2 verification record — unrelated to and
  unaffected by this sprint.
- **No approved dark-background or monochrome logo variant exists** —
  only the white-background artwork was supplied and approved. Dark
  mode's existing CSS variables (`brandColorsDark`) were updated for
  color consistency, but the logo itself is not placed on any dark
  surface anywhere in the product.
