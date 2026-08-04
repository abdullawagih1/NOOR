# NOOR Cinematic Mobile Strategy

Status: **LX-1.1 — In Progress**

## Principle

Mobile is a deliberate redesign, not a scaled-down desktop scene
(mission §28). The narrative stays complete; the *execution* changes.

## Breakpoint

`≤767px` (matches Tailwind's default `md` boundary already used
elsewhere in this codebase) triggers the mobile camera keyframe set
(`NOOR_CINEMATIC_CAMERA_MAP.md` §Mobile keyframes) and the mobile
particle/geometry budget (`NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`).

## What changes on mobile

- **Camera travel distance:** capped at roughly 40–60% of the desktop distance per scene — less parallax, less perceived motion, no long orbit.
- **Particle count:** 250 (vs. desktop `high` tier's 900).
- **Geometry:** the document-stack plane count is unchanged (5 — it's already cheap), but the provenance-thread tube segment count is reduced (fewer subdivisions along the `CatmullRomCurve3`) since thread smoothness reads less critically at mobile viewing distance.
- **Scene duration:** the master timeline's total scroll distance is shorter on mobile (roughly 70% of desktop's 4200px) so the same narrative completes in less scrolling — long pinned/sticky sections are explicitly avoided per mission §28's "no long pinned scroll sections" rule (the sticky canvas container itself is capped to a shorter total height on mobile).
- **Typography:** larger base size for headlines/copy in the mobile overlay layout (a mobile-specific Tailwind breakpoint class set, not a scaled-down desktop font).
- **No nested scroll, ever** — identical rule to desktop, restated because it's the single most important mobile constraint.

## What stays the same on mobile

- All 7 scenes, in the same order, with the same headlines/copy/status labels.
- Both CTAs, always reachable.
- The reduced-motion path is identical in content to desktop's reduced-motion path (mobile and reduced-motion converge on `StaticFallbackExperience`, sharing the same component — see Technical Architecture).

## Quality-tier interaction

Mobile devices are never assigned the `high` quality tier by default —
they start at `balanced` and can only be *downgraded* further to
`static` by the FPS probe, never upgraded, since typical mobile GPUs
cannot be assumed to sustain the desktop particle/geometry budget.

## Premium, not merely functional

The mobile version keeps the same color system, the same lighting
logic (state changes still shift key-light color), and the same
provenance-thread visual language — it is a shorter, lighter version
of the same cinematic object, not a fallback that abandons the
aesthetic. The genuinely stripped-down fallback (no WebGL at all) is
`StaticFallbackExperience`, reserved for reduced-motion/low-power/
WebGL-unavailable specifically, not applied to mobile by default.
