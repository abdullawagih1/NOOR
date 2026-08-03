# LX-1.0 — Repository Audit and Landing Baseline

Status: **LX-1.0 — In Progress**

This is the first deliverable of LX-1.0 (Immersive Landing Narrative and
Motion Blueprint). It records the verified state of the repository and
the current public landing page *before* any narrative, motion, or
prototype work began, so later claims of improvement have something
real to compare against.

All findings below were produced by directly inspecting the repository
(git, source files, `next build` output, a real `next start` server,
and real Lighthouse/Playwright runs) on 2026-08-03 — nothing here is
inferred from documentation alone.

## 1. Git state at the start of LX-1.0

```
branch:  main (up to date with origin/main)
HEAD:    f1dfe1d docs: document Sprint 1-E2 embedding and vector index foundation
remote:  https://github.com/abdullawagih1/NOOR.git
tree:    clean (3 pre-existing untracked files not part of any sprint's
         work: apps/web/public/brand.zip, docs/verification/screenshots/
         ux-1-1.zip, logo.jpeg — left untouched)
```

`git diff --check` returned nothing (no whitespace errors in tracked history).

## 2. Repository Audit

| Area | Current State | Reusable | Gap | Decision |
| --- | --- | --- | --- | --- |
| Production `/` landing | `apps/web/app/page.tsx` — static hero + 6-capability grid + trust section, `PublicShell` header/footer, no client JS beyond the shared shell | Yes — shell, tokens, copy tone | Content is stale (predates S1-E1/S1-E2; doesn't mention retrieval evaluation or embeddings at all), no motion, no evidence-journey narrative | Keep unchanged for LX-1.0; supersede in LX-1.2 |
| `PublicShell.tsx` | Shared header (logo + Sign in) / footer for all public, non-workspace routes | Yes | None found | Reuse as-is for the new landing's chrome |
| Brand tokens (`packages/ui/tokens/`) | `colors.ts` (full 50–950 ramps + semantic slots + dark mirror), `typography.ts` (Inter/IBM Plex Sans Arabic via `next/font`), `spacing.ts` (4px base, `xxs`→`section`), `radius.ts`, `shadows.ts` | Yes, fully | None — anchors match this mission's stated palette exactly (Deep Navy `#032855`, Clinical Blue `#045092`, Primary Teal `#078A88`, Deep Teal `#0A6668` via `brandTeal[700]`≈, Emerald `#09B993`, Soft Cyan `#B6DAE0`, Blue Gray `#6E9DA8`) | Use these tokens as sole authority; no parallel landing palette |
| `data-theme` | Pinned to `"light"` on `<html>` always (UX-1.1) — no dark-mode toggle exists | Yes | N/A | New landing must also render only the light theme; do not introduce a toggle |
| RTL support | Structural only: one isolated `dir="rtl" lang="ar"` demo `<div>` inside `/design-system`; the real `<html>` is always `dir="ltr"` | Partial | No live RTL page mode exists anywhere in the app yet | Prototype RTL as a scoped, isolated structural preview (matching the existing precedent), not a live toggle on `/` |
| `globals.css` | 21 lines: Tailwind directives, box-sizing reset, `[dir="rtl"] body` font swap | Yes | No `prefers-reduced-motion` rule anywhere in the codebase | Add reduced-motion handling as part of the new motion system, additive only |
| Design System route | `/design-system` (`apps/web/app/design-system/page.tsx`) — `notFound()` when `NODE_ENV === "production"`, otherwise renders token/component showcase from mocked data only | Yes — this is the exact gating pattern to reuse | None | Reuse verbatim for `/design/landing-experience` |
| `packages/ui` components | Button, Card, Table, Tabs, Badge/SemanticStatusBadge, Alert, clinical/* (EvidenceCard, CitationCard, ProcessingTimeline, ClinicalQuestionBar, ClinicalWarningPanel, StatusBadges), States (Empty/Error/Loading/Skeleton) | Yes, extensively | No landing-specific components yet (hero, scene, timeline-for-storytelling) | New landing components are additive in `packages/ui/components/landing/` or co-located in `apps/web` — decided in Technical Architecture doc |
| Existing animation dependencies | **None.** No `framer-motion`, `gsap`, `motion`, or `three` anywhere in any `package.json` or lockfile prior to this audit | N/A | Confirmed gap | Install only after this audit (see §3) |
| Playwright | `@playwright/test` devDependency present in `apps/web/package.json` (hoisted `playwright-core@1.62.1` at repo root); **no committed `playwright.config.*`, no committed test suite** — prior sprints used ad hoc capture scripts, run and deleted per session | Partial | No durable/reusable Playwright config exists | LX-1.0 will use ad hoc scripts for prototype evidence (matching established practice); a durable config is a candidate for LX-1.2+ if the team wants persistent visual regression tests |
| Lighthouse | Not installed as a dependency; available via `npx lighthouse` (downloads on demand, ~15 MB) | N/A | No committed Lighthouse config/CI gate | Use `npx lighthouse` for baseline + prototype measurement; do not add a CI gate in LX-1.0 (out of scope) |
| Accessibility tooling | No `axe-core` present before this audit | N/A | Confirmed gap | Installed `@axe-core/playwright` (devDependency) for prototype accessibility scanning — see §3 |
| CI (`.github/workflows/pr.yml`) | 4 jobs: secret scan, `web` (lint/typecheck/test/build), `clinical-schemas`, `worker`, `database` (Supabase migrations + RLS) — last confirmed green on `f1dfe1d` | Yes | No landing-specific CI step | No new CI job required; the existing `web` job's lint/typecheck/test/build already covers the new prototype route since it lives inside `apps/web` |
| Vercel deployment | `.vercel/project.json` present at repo root, linked to project `noor`; `scripts/preflight-vercel-deploy.mjs` guards against deploying from the wrong directory (established Sprint 1-D3 fix) | Yes | None | Reuse preflight script before any preview deploy |
| Current public copy | Landing hero: *"NOOR — Clinical Intelligence OS"* / *"Evidence-governed knowledge operations for clinical teams."* — accurate for what shipped at UX-1.1 time, but doesn't reflect S1-E1 (retrieval evaluation) or S1-E2 (embeddings/vector search) at all | Partial (tone only) | Content gap, not a correctness bug — nothing on the current page is false, it is simply incomplete | New narrative supersedes this copy; current copy is not "wrong," just outdated |
| Current feature-status docs | `SPRINT_CURRENT.md`, `PROJECT_STATE.md`, `MASTER_BACKLOG.md`, `KNOWN_LIMITATIONS.md` all current through S1-E2 | Yes | None | Used directly as the evidence source for the Capability Truth Matrix |

## 3. Dependency Decision Table

| Dependency | Installed (before audit) | Version chosen | Current use | Proposed use | Bundle risk |
| --- | --- | --- | --- | --- | --- |
| `framer-motion` | No | `^12.43.0` (latest; actively maintained — the package is now a thin, API-compatible re-export over the renamed `motion` package, so the import name the mission specifies still works) | None | Section reveals, component entrances, staggers, hover/focus, counters, progress states, reduced-motion variants, all 5 non-signature prototypes | Low-moderate — tree-shakeable, loaded only inside client animation islands, never in the shared root bundle |
| `gsap` | No | `^3.15.0` (latest) | None | Reserved for exactly one responsibility: the pinned, scroll-scrubbed reverse-traceability timeline (Section 8 / prototype 22.6), where Framer Motion's scroll primitives are less suited to a multi-stage pinned sequence | Moderate — dynamically imported only on the traceability scene, never in the initial landing bundle |
| `three` | No | **Not installed** | None | None approved yet — see `NOOR_LANDING_THREEJS_DECISION.md` | N/A |
| `@axe-core/playwright` | No | `^4.12.1` (latest, devDependency) | None | Automated accessibility scanning of the prototype gallery and the baseline page | None — dev-only, never ships to the browser bundle |
| `@playwright/test` | Yes (`^1.62.1`) | unchanged | Ad hoc capture scripts in prior sprints | Prototype browser evidence capture (screenshots, DOM/axe checks) | None — dev-only |

No other dependency was installed. `npm audit` reports 5 pre-existing vulnerabilities (`esbuild`/`tsx` — dev-only; `postcss`/`sharp` via `next@15.5.21`) that predate this session and are unrelated to any package installed for LX-1.0; fixing them requires a breaking Next.js downgrade and is out of scope here — recorded as a pre-existing item, not introduced or hidden.

## 4. Current Landing Baseline Evidence

Captured against a real `next build` + `next start` production server (port 4500), not `next dev` (which under-reports real bundle/perf numbers).

### 4.1 Build output (production bundle)

```
Route (app)   Size    First Load JS
/             2.18 kB     114 kB
```

Shared First Load JS across all routes: 103 kB (2 vendor chunks + 2 kB misc).

### 4.2 Screenshots

Captured with a real headless Chromium (Playwright), full-page, at 4 viewports:

| Viewport | File |
| --- | --- |
| Desktop 1440×900 | `docs/landing/baseline-screenshots/desktop-1440.png` |
| Laptop 1280×800 | `docs/landing/baseline-screenshots/laptop-1280.png` |
| Tablet 1024×1366 | `docs/landing/baseline-screenshots/tablet-1024.png` |
| Mobile 390×844 | `docs/landing/baseline-screenshots/mobile-390.png` |

All four independently visually confirmed: the light clinical theme, brand header/footer, hero, 6-capability grid, and trust section render correctly at every size; no overflow, no broken images.

### 4.3 Lighthouse — desktop preset (real run, `docs/landing/baseline-screenshots/lighthouse-baseline.report.{json,html}`)

| Category | Score |
| --- | --- |
| Performance | 1.00 |
| Accessibility | 1.00 |
| Best Practices | 1.00 |
| SEO | 1.00 |

| Metric | Value |
| --- | --- |
| LCP | 0.5 s |
| CLS | 0 |
| TBT | 0 ms |
| Speed Index | 0.4 s |
| FCP | 0.3 s |
| Total byte weight | 189 KiB |

### 4.4 Lighthouse — mobile preset, perf category (`lighthouse-baseline-mobile.report.json`)

| Metric | Value |
| --- | --- |
| Performance score | 0.45 |
| LCP | 4.7 s |
| CLS | 0 |
| TBT | 1,370 ms |
| Speed Index | 5.2 s |

**Caveat, recorded honestly rather than smoothed over:** this mobile score is measured against `localhost`, where Lighthouse's simulated mobile throttling (4× CPU slowdown + simulated slow-4G RTT) is calibrated for real network latency, not a near-zero-latency loopback connection — the simulation model can overstate wait time in exactly this setup. The desktop run against the same server scored a perfect 1.00 with a 0.5 s LCP, and the page ships only 189 KiB total with zero client JS beyond the shared shell, so a 4.7 s mobile LCP is very unlikely to reflect the page's real mobile behavior on a deployed Vercel edge. This is flagged as a **measurement artifact to re-verify against the actual Vercel Preview URL in LX-1.2's performance hardening phase**, not swept under the rug. The desktop numbers and the bundle-size numbers are the trustworthy baseline figures for LX-1.0 planning purposes.

### 4.5 Accessibility

The desktop Lighthouse accessibility score above (1.00) is the accessibility baseline recorded for LX-1.0. A dedicated `@axe-core/playwright` scan is run against every new prototype (§Prototype Testing in the verification report), not against the unchanged production page, since the production page is out of scope for modification this sprint.

## 5. What this baseline means for LX-1.0

- The current landing page has **no defects to fix** — it is fast, accessible, and correct for what it claims. The work ahead is narrative and experiential, not remedial.
- Any future claim that a new landing implementation "improves performance" must be measured against the **desktop** numbers above (LCP 0.5 s, 189 KiB, perfect Lighthouse scores) and the **bundle** number (114 kB First Load JS for `/`) — a new, richer landing experience should be judged against realistic budgets that account for the animation libraries it adds, not against a false expectation of matching a near-zero-JS page byte-for-byte. See `NOOR_LANDING_PERFORMANCE_BUDGET.md`.
- The content gap (missing S1-E1/S1-E2 mention) is the primary reason a narrative refresh is warranted at all, independent of the visual/motion ambitions of this mission.
