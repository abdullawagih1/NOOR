# NOOR Landing Three.js Decision

Status: **Reversed for LX-1.1 — see §"LX-1.1 Reversal" below, and
§"LX-1.1 Amendment" for a real mid-mission correction to *which*
Three.js-ecosystem library actually shipped. The LX-1.0 decision and
its reasoning are preserved unedited beneath both as a historical
record — this document explains what changed and why, rather than
silently overwriting earlier calls.**

## LX-1.1 Amendment — raw Three.js shipped, not React Three Fiber

`@react-three/fiber`/`@react-three/drei` were installed, integrated,
and then **removed** after a real, reproduced, researched blocker: a
currently-unresolved upstream incompatibility between
`@react-three/fiber` v8's `react-reconciler` usage and Next.js 15's
client bundling, confirmed against multiple independent GitHub reports
of the exact same crash on the exact same React 18.3.1 + Next 15.0–
15.6 + fiber 8.17–8.18 combination this repository uses — not a local
misconfiguration. The library maintainer's own stated fix requires
React 19, a whole-app major upgrade out of scope and unacceptably risky
for one prototype route. Full root-cause chain, every fix attempted,
and the citations: `NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md`
§"Why raw Three.js, not React Three Fiber".

**The Three.js approval below stands exactly as written** — the
Evidence Core, camera choreography, and every design decision are
unchanged. Only the rendering technique changed: plain, imperative
`three` (a `THREE.Scene`/`THREE.PerspectiveCamera`/
`THREE.WebGLRenderer` driven by a component-owned
`requestAnimationFrame` loop) instead of a declarative React renderer.
This has zero dependency on `react-reconciler`, so the bug class
cannot occur by construction.

## LX-1.1 Reversal — Three.js approved (React Three Fiber originally planned)

### Decision

```
Approved for LX-1.1, scoped strictly to the cinematic prototype route
(/design/cinematic-landing). Still not approved for any other route.
```

Installed and shipped: `three@0.185.1`. `@react-three/fiber@8.18.0`
(the latest major compatible with this repo's React 18.3.1 — v9
requires React 19) and `@react-three/drei@9.122.0` were installed,
integrated, found non-functional in this exact stack, and removed —
see the Amendment above.

### Why the reference clarified the value of 3D

LX-1.0's own decision was correct for what it evaluated: a *linear,
5-stage reversal* has no missing dimension a 2D DOM/SVG sequence
can't express. The LX-1.1 mission changes the actual creative brief,
not just the technology preference — it asks for **one continuous
object that visibly transforms across the entire journey** (a single
Evidence Core that is simultaneously a source document, a verified
object, reviewed page layers, structured chunks, a retrieval network,
and a reversible provenance chain), with **camera movement carrying
narrative meaning** (approaching, orbiting, pulling back to reveal
scale). That is a fundamentally different claim than "explain a linear
sequence" — it requires depth, persistent object identity across state
changes, and a camera that is itself a storytelling device. A stack of
DOM cards cannot make one object visibly *become* the next stage; it
can only replace one flat card with another. This is the concrete gap
LX-1.0's audit didn't have a brief to evaluate.

### Why the Evidence Core is narratively meaningful, not decorative

Per the mission's own test ("every animation must explain process,
state, causality, review, transformation, provenance, trust" —
carried over from LX-1.0 §5.4): every transformation the Evidence Core
performs corresponds to a real, verified repository capability from
`NOOR_LANDING_CAPABILITY_TRUTH_MATRIX.md` — page layers resolving is
S1-C2's extraction, the lock/unlock gate is S1-D1's review gate, spans
becoming chunks is S1-D3's chunking, the ranked candidates are S1-E1/
S1-E2's evaluation framework, and the reverse camera pull is the
signature traceability guarantee every prior workstream's provenance
model actually supports. Nothing about the object exists purely to
look advanced — see `NOOR_CINEMATIC_CONCEPT.md` and
`NOOR_EVIDENCE_CORE_DESIGN.md` for the full mapping.

### Why DOM-only step cards are insufficient

LX-1.0's prototype gallery (`/design/landing-experience`) is the
concrete proof: it is technically correct (0 axe violations, clean
build, real Framer Motion/GSAP usage) but behaves as *card → Play
button → step change → static frame*, which is exactly what the
LX-1.1 mission was written to reject. A card that swaps its internal
state on a button click cannot express "the same object is continuously
present and transforming" — that requires one persistent 3D scene
whose state is driven by the page's own scroll position, which is a
capability DOM layout transitions do not have.

### Why readable content remains outside the canvas

Every headline, status label, product-truth label, and CTA in the
cinematic route is real DOM text (Framer Motion for entrance/exit),
never drawn inside the WebGL canvas — matching LX-1.0's own
accessibility principle that meaning must never live only inside a
canvas. The canvas is `aria-hidden="true"` everywhere it carries no
unique readable content of its own. See
`NOOR_CINEMATIC_ACCESSIBILITY.md`.

### Performance constraints

Three.js/R3F/drei are dynamically imported and **route-isolated** to
`/design/cinematic-landing` only — confirmed by inspecting the
production `next build` output for every other route
(`/`, `/login`, `/quality/*`, `/reviewer/*`, `/clinician/*`,
`/admin/*`) and verifying none of them gained bytes from this
installation. See `NOOR_CINEMATIC_PERFORMANCE_BUDGET.md` for the full
measured bundle/FPS/memory record, including any target not met and
why.

### Mobile fallback

Mobile does not receive a shrunk desktop scene. It receives a
deliberately simplified experience (reduced geometry/particle budget,
shorter camera travel, no long pinned sections) — see
`NOOR_CINEMATIC_MOBILE_STRATEGY.md`.

### Reduced-motion fallback

`prefers-reduced-motion: reduce` (or the low-power/WebGL-unavailable
paths) renders a static DOM/SVG sequence with identical narrative
content and order, no canvas, no scroll-scrubbing, no camera travel —
see `NOOR_CINEMATIC_FALLBACK_STRATEGY.md`.

### Accessibility constraints

Full semantic DOM story exists independent of the canvas; keyboard
navigation, focus order, and screen-reader reading order all match
narrative order; the canvas never gates comprehension. See
`NOOR_CINEMATIC_ACCESSIBILITY.md` for the verified checklist.

### Why the 3D world is not unlimited-complexity permission

This approval is scoped to exactly one route, one object, and the
budgets recorded in `NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`. It is not
a blanket license for 3D elsewhere in the product, and it does not
relax any of LX-1.0's anti-decoration rules — see §5.4 in the original
LX-1.0 mission, still in force.

---

## LX-1.0 Original Decision (preserved, historical)

Status: **LX-1.0 — Complete** (superseded for the cinematic route only, above)

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
