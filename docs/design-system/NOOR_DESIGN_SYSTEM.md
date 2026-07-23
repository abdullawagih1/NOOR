# Noor Design System

See ADR 0005 (`docs/architecture/adr/0005-noor-design-system.md`) for the
composition decision and rationale. This document is the practical
reference for building with it.

## Token source

`packages/ui/tokens/*.ts` is the only place a token value is defined:

| File | Contents |
|---|---|
| `colors.ts` | `brandColors`, `brandColorsDark`, `semanticStates` (16 clinical/system states) |
| `typography.ts` | `fontFamilies`, `typeScale` (7 steps: display → caption) |
| `spacing.ts` | 4px-based scale, `xxs` (4px) → `section` (64px) |
| `radius.ts` | `none` / `sm` (8px) / `md` (12px) / `lg` (16px) / `pill` |
| `shadows.ts` | `none` / `card` / `raised` — deliberately just two tiers |
| `index.ts` | re-exports everything + `tokensToCssVariables()` |

**Never add a second copy of a token value.** If you need a new color or
spacing step, add it in `packages/ui/tokens/`, not in a component file, not
in `tailwind.config.ts`, not in `globals.css`.

## How a token reaches the screen

```
packages/ui/tokens/*.ts
        │
        ├──► apps/web/tailwind.config.ts   (imports the TS objects directly
        │                                   for spacing/radius/shadow/font
        │                                   utility class generation)
        │
        └──► tokensToCssVariables()  ──►  <TokensStyleTag />  (root layout)
                                            │
                                            ▼
                                     CSS custom properties (:root, and
                                     :root[data-theme="dark"] / prefers-
                                     color-scheme for dark mode)
                                            │
                                            ▼
                              Tailwind color utilities (bg-primary, text-ink,
                              …) resolve through these variables — one class
                              name, correct in both themes automatically.
```

Semantic-state colors (`semanticStates`) are **not** Tailwind classes —
they're runtime-selected (one of 16 states, unknowable at Tailwind's
build-time content scan), so components read them via
`semanticStateVarRefs(key)` and apply them as inline `style`, still backed
by the same CSS variables.

## Using components

```tsx
import { Button, Card, EvidenceCard, SemanticStatusBadge } from "@noor/ui";
```

`@noor/ui` is an npm workspace member (`packages/ui`), transpiled directly
by Next (`transpilePackages: ["@noor/ui"]` in `next.config.mjs`) — same
pattern as `@noor/clinical-schemas`. No build step, no published package.

### Generic primitives (22)

Button, IconButton, TextInput, PasswordInput, Select, Checkbox, Radio,
Textarea, Badge, Alert, Card, Section, PageHeader, EmptyState, ErrorState,
LoadingState, Skeleton, Modal, Tabs, Breadcrumb, Table (+Head/Body/Row/Cell),
Pagination, Tooltip.

### Noor clinical components (10)

`EvidenceStatusBadge`, `GuidelineStatusBadge`, `AIGeneratedLabel`,
`HumanApprovedLabel`, `ClinicalWarningPanel`, `EvidenceCard`, `CitationCard`,
`ProcessingTimeline`, `PermissionDeniedPanel`, `ClinicalQuestionBar`.

All render **mocked data only** — none are wired to retrieval or generation.
Sprint 1 wires real data into the same components rather than rebuilding
them.

### Workspace navigation

`WorkspaceNav` (presentational, `packages/ui`) + `WorkspaceHeader`
(`apps/web/app/WorkspaceHeader.tsx`, app-specific) together render nav items
**derived from the signed-in user's `permissionKeys`**, not from which route
happens to be active. Adding a 5th workspace means adding one entry to
`NAV_DEFINITIONS` in `WorkspaceHeader.tsx` — nothing else changes.

## Showcase route

`/design-system` (`apps/web/app/design-system/page.tsx`) renders every
token and component with mocked data. It calls `notFound()` whenever
`NODE_ENV === "production"`, so:

* **Local dev** (`npm run dev`): reachable, no auth required (nothing
  privileged is shown).
* **Any deployed build** (Vercel Preview or Production): 404.

This is the `/design-system` route's documented answer to Sprint 0.5 §13's
"document whether it is development only, admin only, excluded from
production, or intentionally available internally" — it is **development
only**, enforced in code, not by convention.

## Fonts

`next/font/google` self-hosts Inter (`--noor-font-latin`) and IBM Plex Sans
Arabic (`--noor-font-arabic`) at build time in `apps/web/app/layout.tsx` — no
external font CDN request at runtime, no proprietary font license. Noto Sans
Arabic is the documented intended fallback; it isn't separately self-hosted
because `next/font`'s automatic metric-adjusted fallback already covers
that gap without a second Arabic webfont download.

## What Sprint 0.5 does not include

Final visual polish, animation, a component test suite beyond the smoke
checks in `apps/web/tests/`, and any component wired to real
retrieval/generation data are explicitly out of scope — see MASTER_BACKLOG.md.
