# NOOR Landing Visual Language

Status: **LX-1.0 — In Progress**

## Illustration language

All landing visuals are **product-derived interfaces and abstract
evidence paths**, not illustration in the traditional sense:

- Document/guideline cards styled exactly like `EvidenceCard`/`Card` from `packages/ui`
- Provenance connector lines: 1px SVG paths using `brandTeal[500]` at reduced opacity, animated via `pathLength`, matching the brand's own "teal = motion path" rule (§6 of the mission)
- Status chips: reuse `SemanticStatusBadge` and the existing `semanticStates` tokens exactly (`verified`, `underReview`, `processing`, etc.) — no new status colors invented for the landing page
- Nodes/steps: simple rounded rectangles and circles built from the existing `radius`/`shadows` tokens, never custom illustration assets
- Gradients: only the one official `brandGradient` (blue→teal→emerald), used exactly as sparingly as the token's own doc-comment prescribes — a thin accent line, never a full-bleed background

## Explicitly avoided (per mission §5.4 and §26)

Generic animated gradients everywhere, floating glass cards without
purpose, decorative medical crosses, DNA animations, rotating brains,
particle systems, 3D globes, cyberpunk interfaces, neon dashboards,
generic chatbot mockups, stock medical photography, excessive blur,
constant/ambient motion, stock illustrations, human anatomy diagrams,
fake hospital scenes, decorative 3D medical objects, robot imagery,
unlicensed third-party artwork, AI-generated images for any part of the
core narrative.

## Color usage on the landing page specifically

- Base ground: warm white canvas (`#FFFFFF` / `surfaceSoft` for section alternation), matching the existing `/` page's alternating `bg-canvas`/`bg-surface-soft` pattern exactly — no new background colors introduced.
- Structural text: Deep Navy (`ink`).
- Interaction (CTAs, links, focus ring): Clinical Blue (`primary`/`accent`).
- Motion paths (connector lines, the evidence-flow strip's connecting thread): Primary Teal.
- Verified/positive states: Emerald (`semanticStates.verified`), never repurposed for anything else.
- Depth/atmosphere (subtle section-transition backgrounds, if any): Soft Cyan at very low opacity — never a full section background, only a thin top-edge wash.
- One deliberate dark-Navy section is permitted for contrast per mission §6 — reserved for Scene 8 (the traceability signature scene) specifically, where a slightly deeper ground (`brandNavy[800]`, not pure black) helps the pinned sequence read as a distinct, focused moment. The rest of the page stays on the light clinical canvas. This is the only section that departs from the light background, and it never becomes a "dark mode" — it is one deliberately weighted section, not a page-wide shift.

## Typography

No new typefaces. Inter (Latin) / IBM Plex Sans Arabic, both already
self-hosted via `next/font` — reused exactly. The landing introduces
one new scale step not in the current `typeScale` (`display` tops out
at 28px, appropriate for in-app pages but modest for a hero headline):

```ts
// Proposed addition to packages/ui/tokens/typography.ts (LX-1.2 candidate,
// NOT added during LX-1.0 — prototypes use an inline landing-scoped value
// so the shared token file stays untouched until the narrative is approved)
heroDisplay: { fontSize: "2.5rem", lineHeight: "1.15", fontWeight: 600 } // 40px, ~48px on ≥1024px via a responsive clamp
```

Body copy throughout stays at the existing `body`/`bodySecondary` scale
— this is still a clinical reading surface, not a marketing page that
needs an oversized type system throughout.

## RTL structural rules

- Logo remains unmirrored in every RTL preview (matches existing brand rule).
- Provenance/traceability direction: the reversal (Scene 8) reads right-to-left in an RTL context — evidence flows from the reader's right toward their left, matching natural RTL reading order, not a mirrored copy of the LTR left-to-right animation.
- Arrows and connector lines use semantic direction (pointing toward the next real step) rather than automatic CSS mirroring, which would otherwise flip an arrow's meaning.
- English technical labels (checksums, IDs, dimension counts) stay LTR inside an RTL layout, exactly matching the existing `/quality` workspace convention already shipped in S1-E1/S1-E2.
- Arabic typography preserves line-height via `font-arabic`'s existing token; no compression.
- True Arabic-content translation/validation is out of scope for LX-1.0 (English copy only) and is recorded as a future localization acceptance gate in `NOOR_LANDING_PRODUCTION_PLAN.md`.
