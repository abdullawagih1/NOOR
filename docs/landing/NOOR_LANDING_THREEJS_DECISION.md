# NOOR Landing Three.js Decision

Status: **LX-1.0 — In Progress**

## Decision

```
Not required for LX-1 production implementation.
```

Three.js is **not installed** anywhere in this repository as of LX-1.0
(confirmed by `LX-1-0_BASELINE.md` §2 — no `three` dependency existed
before this mission, and none was added during it).

## Rationale

The mission names exactly one concept that could plausibly justify
Three.js: an "interactive evidence topology" or "provenance network."
The signature scene this mission actually needs — Section 8's reverse
traceability journey — is a **strictly linear, 5-stage sequence**
(statement → evidence → chunk → span → page → guideline), not a
network or topology. A linear sequence has no missing dimension that a
2D DOM/SVG + GSAP ScrollTrigger implementation fails to communicate:

- Causality is inherently linear and reads clearly as a top-to-bottom or scroll-driven progression.
- The connector lines needed (Scene 5's chunk↔source line, Scene 8's breadcrumb) are simple, low-count paths — well within plain SVG's comfortable range.
- Nothing about "exact source span" or "original page" benefits from a 3D camera, depth, or spatial arrangement; if anything, 3D would add ambiguity about which direction is "back toward the source."

No prototype was built to test a 3D alternative, because no concept in
this mission's storyboard has a plausible 3D-shaped narrative gap. Per
the mission's own default ("Not approved unless a prototype proves
unique product value" / "Do not install Three.js during LX-1.0 unless
a documented experiment is explicitly approved by the Council audit"),
the absence of such a documented, approved experiment means the
default holds.

## What would change this decision

A future workstream could reopen this decision if NOOR ever needs to
visualize something genuinely topological — for example, a real
knowledge graph of guideline-to-guideline cross-references, or a
corpus-wide map of evaluation-query clusters. Neither exists in the
product today (`NOOR_LANDING_CAPABILITY_TRUTH_MATRIX.md` has no
"knowledge graph" row at all), so there is nothing to prototype against
yet. If that changes, the approval requirements in the mission's §23
apply in full: unique storytelling value, no simpler DOM/SVG
equivalent, measured bundle/GPU impact, mobile fallback, accessibility
fallback, reduced-motion fallback, no content hidden inside canvas, and
explicit user approval — all required before installation, not after.

## Status

Closed for LX-1.0. `three` remains uninstalled.
