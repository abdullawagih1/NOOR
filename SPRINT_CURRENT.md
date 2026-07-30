# Sprint Current: UX-1 — NOOR Brand and Design System Alignment

**Status:** Locally complete and verified (typecheck/lint/build/all
test suites clean across `apps/web`, `packages/ui`,
`packages/clinical-schemas`, and `apps/worker`). A real Vercel Preview
deployment and browser-driven smoke test have **not** been performed in
this session segment — see
`docs/verification/ux-1-brand-alignment-verification.md` for the full,
honest account, including a real disk-space environmental issue
encountered mid-session.

Workstreams `S1-A`/`S1-B`/`S1-C1`/`S1-C2`/`S1-D1`/`S1-D2` closed in
prior sessions. This sprint is workstream `UX-1` — a frontend/design
sprint with **no** clinical-logic, database, RLS, or orchestration
changes. See `MASTER_BACKLOG.md` for the reconciled backlog.

## Governing principle

The user's approved NOOR logo is now the single source of truth for
Noor's visual identity. The existing design-system token architecture
(`packages/ui/tokens/*` → CSS custom properties → Tailwind utilities,
ADR 0005) was sound and unchanged in structure — this sprint changed
*values*, not architecture, plus a small number of component-level
class references (see ADR 0013).

## Objectives

- [x] Official logo preserved byte-for-byte (`apps/web/public/brand/source/`,
      sha256-verified) and derived into five real, unmodified crops
      (primary lockup, navigation lockup, symbol, favicon, social
      preview) — never redrawn.
- [x] Brand color anchors independently sampled from the real logo
      pixels and validated against the mission's own supplied reference
      values before being finalized — see
      `docs/design/noor-color-system.md`.
- [x] Centralized brand + semantic token system extended (not
      replaced): four new 50–950 brand scales, a new `accent` (teal)
      slot split out from `primary` (blue), one gradient token, and
      five new distinct status states (`queued`/`retryScheduled`/
      `ocrRequired`/`reprocessingRequired`/`deadLettered`) that close a
      real, found gap — `ocr_required` and `reprocessing_required` were
      previously visually identical.
- [x] Shared UI components (`packages/ui`) updated: focus rings and
      navigation-active state now use the new teal `accent`, not blue
      `primary`, matching the logo's own blue-interaction/teal-
      wayfinding split.
- [x] Application shell — the logo was added to `WorkspaceHeader`, the
      single shared top nav every workspace (admin/clinician/knowledge/
      quality/reviewer) already renders. The mission described a
      sidebar shell; the app has none, so none was invented.
- [x] Login page redesigned with the primary logo and a restrained
      gradient accent line; a real accessibility regression (losing the
      page's only `<h1>`) was caught and fixed in the same edit.
- [x] Favicon, app icons, Open Graph/Twitter metadata, and `themeColor`
      added — none existed before this sprint.
- [x] Development design-system page gained an "Official brand"
      section (logo variants, gradient, anchor swatches); the existing
      dynamic semantic-state swatch loop picked up the five new states
      with zero page-level code change.
- [x] Brand + design documentation written (ADR 0013,
      `docs/brand/{NOOR_BRAND,noor-logo-usage}.md`,
      `docs/design/{noor-color-system,noor-component-theme,
      noor-accessibility-review}.md`).
- [x] Full regression verification — `apps/web` typecheck/lint/build
      clean, all 14 unit-test files pass, `packages/ui` typecheck
      clean, `packages/clinical-schemas` typecheck+tests pass, and
      `apps/worker`'s full 79-assertion pytest suite still passes
      (confirms zero backend regression from a frontend-only sprint).
- [ ] Vercel Preview deployment and browser-driven smoke test — **not
      done this session segment**, see verification doc for why
      (a real disk-space constraint was hit and flagged, not worked
      around silently).

## A real, disk-space environmental issue this session

Mid-session, this machine's `C:` drive was found at 99% capacity (at
one point 0 bytes reported free), making Docker unresponsive. This was
surfaced to the user immediately rather than pushed through — see
`docs/verification/ux-1-brand-alignment-verification.md`'s
"Environmental note." All verification above completed successfully
once minimal space was freed; none of it needed more than a few hundred
MB.

## Explicitly out of scope this task (per the mission)

Any change to database schema, RLS, permissions, processing states,
extraction states, OCR states, review decisions, eligibility rules,
Worker orchestration, or Storage authorization. Clinical semantic
colors (danger/warning/critical) were deliberately left untouched by
the brand refresh — see ADR 0013 §"Brand colors never override
clinical safety semantics."

## Next sprint

```text
Begin Sprint 1-D3 — Deterministic Page-Aware Chunking
```

See `MASTER_BACKLOG.md` (S1-D3).
