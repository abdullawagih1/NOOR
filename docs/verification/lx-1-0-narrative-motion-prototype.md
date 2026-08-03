# Sprint LX-1.0 — Narrative and Motion Blueprint Verification

Status: **LX-1.0 — Narrative and Motion Blueprint Complete, Pending User Approval**

This report records what was actually verified for LX-1.0 (Immersive
Landing Narrative and Motion Blueprint) — real command output, real
browser evidence, and every bug found and fixed. Nothing here is
inferred from documentation alone.

## 1. Scope confirmation

Per the mission's explicit rules: the production `/` route was **not**
replaced, not redirected, and no prototype links were added to
production navigation. Confirmed:

```
git diff --stat -- apps/web/app/page.tsx apps/web/app/PublicShell.tsx apps/web/app/layout.tsx
```

returned **no output** — zero bytes changed in the production landing
page, its shared shell, or the root layout. No database schema,
migration, RLS policy, storage policy, Worker orchestration, or
extraction/OCR/chunking/retrieval/embedding code was touched (`apps/worker/`
has zero diffs this mission).

## 2. Documentation deliverables (all in `docs/landing/` unless noted)

| File | Contents |
| --- | --- |
| `LX-1-0_BASELINE.md` | Repository audit tables, dependency decision table, current landing baseline (screenshots, Lighthouse, bundle) |
| `NOOR_LANDING_CAPABILITY_TRUTH_MATRIX.md` | Every capability classified Available / In development / Future vision / Not planned, with repository evidence |
| `NOOR_LANDING_NARRATIVE.md` | Audiences, central message, emotional progression, 5-act structure, CTA strategy |
| `NOOR_LANDING_INFORMATION_ARCHITECTURE.md` | 10-section table (purpose, visual, interaction, desktop/mobile/reduced-motion behavior, risks) + text wireframe |
| `NOOR_LANDING_CONTENT_SYSTEM.md` | Per-section eyebrow/headline/copy/proof points/status label/CTA/a11y label/motion narration |
| `NOOR_LANDING_STORYBOARD.md` | 10 scenes, each with explicit narrative meaning (never "animate on scroll") |
| `NOOR_LANDING_MOTION_SYSTEM.md` | Motion tokens (durations, easing, springs, stagger, scroll thresholds, pin/scrub rules) |
| `NOOR_LANDING_VISUAL_LANGUAGE.md` | Illustration language, color usage, typography, RTL structural rules |
| `NOOR_LANDING_THREEJS_DECISION.md` | Decision: not required for LX-1; rationale and reopening conditions |
| `NOOR_LANDING_TECHNICAL_ARCHITECTURE.md` | Server/client component boundaries, dynamic-import strategy, cleanup |
| `NOOR_LANDING_PERFORMANCE_BUDGET.md` | Baseline + production targets + bundle budget by contributor |
| `NOOR_LANDING_ACCESSIBILITY_PLAN.md` | Reduced-motion, keyboard, screen-reader, scroll, mobile, RTL requirements |
| `NOOR_LANDING_SEO_AND_METADATA.md` | Title/description/OG/canonical/heading-hierarchy plan (not yet applied) |
| `NOOR_LANDING_PRODUCTION_PLAN.md` | LX-1.1 → LX-1.4 phase breakdown with acceptance gates |
| `docs/verification/lx-1-0-narrative-motion-prototype.md` | This report |

## 3. Repository audit and baseline — summary

Full detail in `LX-1-0_BASELINE.md`. Headline findings:

- No animation library (`framer-motion`, `gsap`, `motion`, `three`) existed anywhere in the repository before this mission.
- Current `/` page: 2.18 kB / 114 kB First Load JS, Lighthouse desktop 1.00/1.00/1.00/1.00, LCP 0.5 s, 189 KiB total.
- The `/design-system` route's `notFound()`-when-`NODE_ENV==="production"` pattern was identified and reused verbatim for the new prototype route.
- Installed for this mission: `framer-motion@^12.43.0`, `gsap@^3.15.0` (both dependencies of `apps/web`), `@axe-core/playwright@^4.12.1` (devDependency). `three` was **not** installed.

## 4. Prototype gallery — what was built

Development-only route `/design/landing-experience`
(`apps/web/app/design/landing-experience/`), gated identically to
`/design-system`. Contains:

1. **Hero Evidence Flow** (Framer Motion) — 5-node evidence-flow strip.
2. **Source Verification** (Framer Motion) — combines the storyboard's Sections 2+3 per the mission's own §22.2 description; a valid and an illustrative invalid path.
3. **Human Review Gate** (Framer Motion) — 4-column review scene with an explicit downstream unlock.
4. **Structured Knowledge** (Framer Motion + SVG) — span-highlight-to-chunk assembly with a drawn provenance connector line.
5. **Retrieval Illustration** (Framer Motion) — ranked synthetic candidates, explicitly labeled "Evaluation framework — internal, not yet clinician-facing."
6. **Reverse Traceability** (GSAP + ScrollTrigger, signature scene) — a real, scroll-scrubbed 5-stage sequence inside a self-contained scroller (never hijacks the gallery page's own scroll); reduced-motion and narrow-viewport visitors get a static, manually-advanced fallback with identical content and order, per the mission's mobile/reduced-motion rules.
7. **RTL Structural Preview** — an isolated `dir="rtl"` demonstration (same precedent as `/design-system`'s existing Arabic swatch), confirming an unmirrored logo, semantically-directed connectors, and LTR-preserved checksum text.

Every scene reads `useEffectiveReducedMotion()` (a thin wrapper over Framer Motion's `useReducedMotion`, plus a manual override for reviewer testing) and renders a fully resolved, static end-state when motion is disabled — matching the Accessibility Plan exactly. Review-only chrome (`PrototypeFrame`) provides Play/Pause/Reset, a Desktop/Mobile width toggle, a reduced-motion-preview checkbox, a step/progress readout, an implementation-technology badge, and performance notes — none of which ship to production.

## 5. Verification commands run

```
npm run typecheck --workspace=apps/web   → clean
npm run lint --workspace=apps/web        → clean (0 warnings, 0 errors)
npm run build --workspace=apps/web       → clean; see §6 for route sizes
npx tsc --noEmit (packages/ui)           → clean
npx tsc --noEmit && npx tsx src/structuredAnswer.test.ts (packages/clinical-schemas) → clean, 6/6 assertions pass
```

**apps/web test suite** — all 21 test files, 141 assertions total,
were run and pass. Note: invoking the suite via `npm run test
--workspace=apps/web` (i.e. through npm's own `npm-cli.js` wrapper)
repeatedly hung on this Windows/git-bash setup with zero stdout
flushed for minutes — traced to a handful of **orphaned npm/`next dev`
processes from earlier verification steps in this same session**
(confirmed via `Get-CimInstance Win32_Process`, all clearly scoped to
this repository's own `npm run test --workspace=apps/web` and `next
dev` invocations — never anything from an unrelated project). Once
those were killed, running the exact same command chain the
`package.json` `test` script defines **directly** (bypassing
`npm-cli.js`) completed cleanly in well under a minute with exit code
0 and all 21 files' `PASS` lines printed. This is recorded honestly as
a real environment quirk discovered and root-caused during this
session, not a test or product defect — every individual test file,
and the full chain run directly, passed with no failures.

Worker (`apps/worker`) was not modified this mission (no backend scope
per the mission's own rule) and was therefore not re-run — its test
suite was already verified clean at the close of Sprint 1-E2.

## 6. Production build route sizes (real `next build` output)

```
Route                              Size      First Load JS
/                                   2.18 kB   114 kB   (unchanged)
/design-system                      3.25 kB   111 kB   (unchanged, pre-existing)
/design/landing-experience          50.1 kB   164 kB   (new — prototype gallery only)
```

`/design/landing-experience` never renders outside development — see
§7 for the direct 404 confirmation — so its 164 kB First Load JS never
reaches a real visitor.

## 7. Production-route-protection verification (real server, not inferred)

```
next build && next start -p 4501
curl /                          → 200
curl /design/landing-experience → 404
curl /design-system             → 404   (existing precedent, confirmed identical behavior)
```

Then, separately, a **development-mode** server (`next dev -p 4502`,
i.e. `NODE_ENV !== "production"`) was used for all browser evidence
below, confirming the route is reachable in development and gated in
production — genuinely tested both ways, not assumed from one.

## 8. Browser evidence

All captured with a real headless Chromium via `playwright-core`
against the real dev server (never a static mock). Saved to
`docs/verification/screenshots/lx-1-0/`.

| # | File | Viewport | Motion mode | Notes |
| - | --- | --- | --- | --- |
| 1 | `01-narrative-overview-desktop.png` | 1440×900 | enabled | Full gallery, all 7 sections |
| 2 | `02-hero-prototype-desktop.png` | 1440×900 | enabled | Mid-sequence (after Play) |
| 3 | `03-source-verification-prototype-desktop.png` | 1440×900 | enabled | Mid-sequence |
| 4 | `04-human-review-prototype-desktop.png` | 1440×900 | enabled | Mid-sequence |
| 5 | `05-structured-knowledge-prototype-desktop.png` | 1440×900 | enabled | Mid-sequence |
| 6 | `06-retrieval-prototype-desktop.png` | 1440×900 | enabled | Mid-sequence |
| 7 | `07-reverse-traceability-desktop.png` | 1440×900 | enabled | Mid-sequence, real GSAP scrub |
| 8 | `08-reduced-motion-view-desktop.png` | 1440×900 | **real** `prefers-reduced-motion: reduce` emulation | Full gallery, static end-states |
| 9 | `09-traceability-stage-{1..5}-of-5.png` | 1440×900 | reduced-motion | Deterministic 5-frame sequence via the "Next stage" control — substitutes for a video recording, matching the mission's own fallback instruction ("a sequence of timeline-state screenshots") |
| 10 | `10-mobile-prototype-390.png` | 390×844 | enabled | Full gallery; Scene 6 correctly renders its static fallback at this width even with motion enabled |
| 11 | `11-rtl-structural-prototype-desktop.png` | 1440×900 | n/a | Isolated RTL structural preview |

No screen recording was created — none is claimed. The stage-by-stage
sequence in row 9 is the honest substitute the mission itself allows
for.

## 9. Accessibility verification (real `@axe-core/playwright` scans)

| State | Violations found (first pass) | Violations after fixes |
| --- | --- | --- |
| Desktop, motion enabled | 0 | 0 |
| Desktop, reduced motion (real emulation) | 5 distinct rule instances (`color-contrast`) | 0 |
| Mobile 390px | 2 (`color-contrast`, `scrollable-region-focusable`) | 0 |
| RTL structural preview | 0 | 0 |

Verified stable across 3 repeated runs after fixes (0/0/0/0 every
time).

### Real bugs found and fixed

1. **Text dimmed via `opacity` fell below WCAG AA contrast** in four places (`HeroEvidenceFlowScene`, `SourceVerificationScene`, `StructuredKnowledgeScene`, `RetrievalScene`): animating a wrapping element's `opacity` down to 0.25–0.5 to convey an "unresolved" state blended label text toward the background, producing contrast ratios as low as **1.36:1** against a 4.5:1 requirement. Fixed by separating the animated element (icon/decoration only) from the text, which now always renders at a token-checked color (`text-body`/`text-muted` at full opacity) regardless of state.
2. **`text-muted` fails contrast against `accent-soft`**: `var(--noor-color-muted)` (`#59718F`) clears AA against white (5.02:1) and the app's usual blue-tinted `surface-soft` (4.54:1), but only reaches **4.31:1** against the teal-tinted `accent-soft` (`#E1F1F1`) background used for "active/emphasized" states in `TraceabilityTimelineScene` and `HumanReviewScene` — just under the 4.5:1 minimum. Fixed by using `text-body` (10.04:1 against the same background) for any text that can render on an `accent-soft` surface.
3. **`scrollable-region-focusable`**: the `PrototypeFrame` stage container (any scene whose content overflows at 390px) and the traceability scene's own internal scroller were horizontally/vertically scrollable but not keyboard-reachable. Fixed by adding `tabIndex={0}` + `role`/`aria-label` to both.
4. **Architecture gap versus the documented plan**: `TraceabilityTimelineScene` originally branched only on `reducedMotion`, not on viewport width — contradicting this mission's own Motion System/Storyboard rule that mobile never gets the pinned/scrubbed version regardless of the reduced-motion preference. This was caught directly by the mobile `scrollable-region-focusable` violation above, not by inspection. Fixed by adding a real `matchMedia("(min-width: 768px)")` check (`isDesktopViewport`) so mobile now always renders the static fallback, exactly as documented.

## 10. Performance / bundle measurement (spike, not a production budget claim)

Measured against the **dev server** (webpack dev bundles are
deliberately unoptimized/uncompressed relative to a production build —
this is a spike to compare technologies, not a production budget
compliance claim; the real budget target in
`NOOR_LANDING_PERFORMANCE_BUDGET.md` is judged against the **production**
`next build` numbers in §6 above):

- Total script bytes transferred (dev bundles, all 7 scenes + gallery chrome loaded): ~13.1 MB — dominated by webpack dev-mode's unminified React/Next runtime, not representative of production.
- The GSAP + ScrollTrigger dynamic chunk was confirmed to load (`gsapChunkFound: true`, ~360–630 KB dev-mode/unminified) only once the traceability scene was scrolled into view — confirming the dynamic-import gate in `NOOR_LANDING_TECHNICAL_ARCHITECTURE.md` actually works, not just documented.
- Real production route sizes are in §6: the production `/design/landing-experience` bundle (164 kB First Load JS) never reaches a real visitor since the route 404s outside development.
- CSS/SVG vs. Framer Motion vs. GSAP comparison for the one scene where more than one technology was genuinely in contention (Scene 6): GSAP + ScrollTrigger was chosen and implemented for the desktop scroll-scrubbed path specifically because Framer Motion's scroll primitives don't cleanly express a scrub tied to a *custom, self-contained scroller element* (vs. the page's own scroll) without hand-rolling the same `IntersectionObserver`/position-mapping logic GSAP's `ScrollTrigger` already provides; plain CSS/SVG was ruled out for this scene specifically because the scrub needs to map a continuous scroll position to 5 discrete content states with smoothing (`scrub: 0.5`), which CSS scroll-linked animations (`animation-timeline`) cannot yet do with sufficient cross-browser reliability at the time of this mission.

## 11. Regression review

- Production `/`, `/login`, `/403`, `/access-denied`: no diff (§1) and all `public-pages-content.test.ts` regression guards pass (root page's single CTA, no retrieval/AI-answer claims, `data-theme="light"` pin, etc. — 12/12 assertions).
- `/design-system` (existing Development-only route): confirmed still 404s in production, unaffected by this mission's changes.
- `apps/web` build: clean, all existing routes unchanged in size except the new prototype route.
- No database, RLS, permissions, storage, or Worker changes — nothing to regress there.

## 12. Git and CI status

Reported in the final closure message alongside this report, after
the logical commits for this mission are made and pushed.

## 13. Honest open items

- The mobile Lighthouse throttling artifact noted in `LX-1-0_BASELINE.md` §4.4 (pre-existing, unrelated to this mission) is still unresolved and is explicitly deferred to LX-1.3.
- The performance numbers in §10 are a dev-mode spike, not a production budget compliance claim — LX-1.2/LX-1.3 must re-measure against a real production build and, ideally, a real Vercel Preview.
- True Arabic-content translation validation remains out of scope (English-only structural RTL preview), as stated throughout `docs/landing/`.
- No video/screen recording was produced; the stage-sequence screenshots in §8 row 9 are the documented substitute.
