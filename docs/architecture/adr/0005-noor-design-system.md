# ADR 0005: Noor Design System — composition and token architecture

**Status:** Accepted
**Source:** Sprint 0.5 mission §7–13

## Decision

Noor's visual direction is a deliberate composition, not a copy of any one
reference:

```
50% Better Design System   — clinical layouts, dense workflows, forms, tables
25% NHS App Design System  — healthcare accessibility, safety messaging, status tags
15% IBM Carbon             — enterprise admin, audit tables, AI/human transparency labels
10% DESIGN.md warmth       — white canvas, generous spacing, soft rounded shapes, pill surfaces
```

`DESIGN.md` (an Airbnb visual-language extraction) is a reference for
*shape and warmth only* — its brand color (#ff385c "Rausch"), marketplace
terminology, property-card metaphors, photography-first hierarchy, and
Cereal/Circular typefaces are explicitly not carried forward. What is kept:
pure white canvas, soft rounded corners, pill-shaped primary surfaces
(applied to the Clinical Question Bar instead of a search bar), minimal
elevation, and calm typography.

## Brand

Deep Teal / Emerald (`packages/ui/tokens/colors.ts`, `#087F73` primary).
Starting values, not immutable — see
`docs/design-system/ACCESSIBILITY.md` for the contrast verification that
must re-run if these change.

## Token architecture

One canonical source: `packages/ui/tokens/*.ts`. Two consumers, zero
duplication:

1. **Tailwind** (`apps/web/tailwind.config.ts`) imports the same TS objects
   for spacing/radius/shadow/font utility classes.
2. **CSS custom properties** are generated at render time by
   `tokensToCssVariables()` (`packages/ui/tokens/index.ts`) and injected via
   `<TokensStyleTag />` in the root layout — this is what Tailwind's color
   utilities (`bg-primary`, `text-ink`, etc.) resolve through, and it's also
   what dark mode and semantic-state colors use directly via inline
   `style` (data-driven color, not statically knowable at Tailwind's
   build-time class-scan, so CSS variables are the only correct mechanism).

There is no second, hand-maintained copy of any token value anywhere in the
app. Changing a color, a spacing step, or a semantic-state color happens in
exactly one file.

## Semantic states, not brand color everywhere

16 clinical/system states (`SemanticStateKey` in `colors.ts`) each carry a
color pair (light + dark), an icon, a label, and an **accessible
description** exposed via `aria-label` — color is never the only signal
(Clinical Safety Agent requirement). `evidenceInsufficient` in particular is
visually distinct from a generic error: it is Noor's fail-closed safety
state, not a system failure, and its helper text says so.

## Components

Foundation only (Sprint 0.5 scope) — 22 generic primitives + 10 Noor
clinical components, listed in
`docs/design-system/NOOR_DESIGN_SYSTEM.md`. All clinical components
(`EvidenceCard`, `CitationCard`, etc.) render mocked data only; none are
wired to retrieval or generation (Sprint 1+ scope).

## Typography

`next/font/google` self-hosts Inter (Latin) and IBM Plex Sans Arabic
(Arabic) at build time — no external font CDN request at runtime, no
proprietary font dependency. Noto Sans Arabic is documented as the intended
fallback but not separately self-hosted (next/font's automatic
metric-adjusted fallback covers the gap without loading a second Arabic
webfont).

## Showcase route

`/design-system` (`apps/web/app/design-system/page.tsx`) 404s outside
`NODE_ENV=production` — i.e., it renders in local dev, but any deployed
build (Preview or Production) serves a 404 for this path. It uses mocked
data exclusively and requires no authentication to reach in dev, since it
exposes no privileged or tenant-scoped data.

## Consequences

* `apps/web` gains Tailwind CSS 3.4 as a build dependency — the first
  utility-CSS framework in the repo. `packages/ui` is a new npm workspace
  member (`transpilePackages: ["@noor/ui"]` in `next.config.mjs`, same
  monorepo pattern already used for `@noor/clinical-schemas`).
* Every pre-existing page (login, 403, access-denied, all 4 workspaces) was
  restyled onto the new tokens/components in the same session — this ADR
  does not leave a mixed old-CSS/new-Tailwind codebase.
* Final visual and copy decisions for actual clinical screens remain
  Sprint 1+ scope; this ADR covers the foundation only.
