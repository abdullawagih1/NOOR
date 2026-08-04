# NOOR Cinematic Concept — The Evidence Core

Status: **LX-1.1 — In Progress**

## Repository audit table (mission §9)

| Area | Current State | Reusable | Must Replace | Decision |
| --- | --- | --- | --- | --- |
| LX-1.0 prototype gallery (`/design/landing-experience`) | 6 Framer Motion/GSAP scenes, each a bordered card with Play/Reset/viewport controls, `useStepSequence` advancing discrete states on a timer or click | The narrative content, capability-truth mapping, and copy are fully reusable | The *interaction model* (card → Play → step) must not be reused for the cinematic route | Keep the gallery route as-is (technical state reference, per mission §9); build the new experience at a new route, not by editing the old one |
| Framer Motion | `^12.43.0`, installed, used for 5 of 6 LX-1.0 scenes | Yes | No | Reused for all text overlays/UI in the cinematic route |
| GSAP + ScrollTrigger | `^3.15.0`, installed, used for LX-1.0's traceability scene inside a **self-contained internal scroller** | The library itself, yes | The internal-scroller pattern must not be reused — the cinematic route's master timeline must bind to the page's own scroll | New `ScrollTrigger` instance created against the page body, not a nested container |
| Three.js / R3F | Not installed before this mission | N/A | N/A | Installed this mission: `three@0.185.1`, `@react-three/fiber@8.18.0` (React-18-compatible major — v9 requires React 19), `@react-three/drei@9.122.0`. See the updated `NOOR_LANDING_THREEJS_DECISION.md` |
| Reduced-motion logic | `useEffectiveReducedMotion` (system preference + reviewer override), used per-scene in the gallery | The hook itself, yes | The all-or-nothing "render the resolved end state" pattern is too coarse for a 7-scene cinematic sequence | Extended with a static, fully-narrated DOM/SVG sequence — see `NOOR_CINEMATIC_FALLBACK_STRATEGY.md` |
| Development-route gating | `notFound()` when `NODE_ENV==="production"`, identical on `/design-system` and `/design/landing-experience` | Yes, verbatim | No | Reused exactly for `/design/cinematic-landing` |
| Public `/` route | Unchanged since UX-1.1; confirmed byte-identical again this mission (§ below) | N/A | No | Left untouched |
| Brand tokens | `packages/ui/tokens/colors.ts` — full ramps + semantic states | Yes | No | Cinematic route reads the same tokens; dark environment uses `brandNavy[800]`/`[900]`, never a new palette |
| Playwright / axe tooling | `@playwright/test`, `@axe-core/playwright`, both already installed from LX-1.0; no committed config | Yes | No | Reused; video recording added via Playwright's built-in `recordVideo` context option |
| Bundle/Lighthouse tooling | `npx lighthouse` (on-demand), no CI gate | Yes | No | Reused identically to LX-1.0's baseline methodology |
| Current mobile behavior (LX-1.0 gallery) | Cards stack vertically, traceability scene swaps to a static fallback below 768px | Partial — the *decision to gate on viewport width* is reusable | The visual design itself doesn't apply (no 3D existed) | New mobile-specific simplified scene design, see `NOOR_CINEMATIC_MOBILE_STRATEGY.md` |
| Current RTL preview | Isolated `dir="rtl"` structural demo, matching `/design-system`'s precedent | Yes, pattern reusable | No | New isolated RTL structural check added for the cinematic nav/CTA/labels |

## Why the LX-1.0 gallery was rejected

The user's own words: *"Card → Play button → Step changes → Static or
barely perceptible state transition."* This is an accurate description
of what was built — each scene is functionally correct (real motion,
real accessibility, real reduced-motion handling) but structurally a
**stack of independent demos**, not one continuous world. The
mission's approved direction requires the opposite: one fixed 3D
object, present throughout, whose camera and geometry state is driven
by the page's own scroll — never a button.

## The Evidence Core

### Central object and visual metaphor

The Evidence Core is a single procedural 3D construct that is
**always the same object**, never swapped for a different model
between scenes. It reads, in order, as:

1. A compact stack of thin, rounded document planes (the source).
2. The same planes, now edge-lit and encircled by a thin verification
   ring (verified).
3. The planes fanning open to reveal one page in focus, with a locked
   indicator that resolves to unlocked (reviewed).
4. Highlighted regions on that page detaching into small connected
   blocks, each still tethered to the page by a visible thread
   (structured knowledge).
5. Those blocks reorganizing into a shallow ranked arrangement in
   front of the camera (retrieval).
6. A small crystalline panel condensing in front of the ranked blocks,
   linked back to them by the same thread material (the product-vision
   workspace).
7. The camera pulling back through every stage in reverse, ending on
   the full assembly (reverse traceability).

The geometric language draws from NOOR's own brand: the ribbon curves
that form the "N" symbol's own stroke reappear as the provenance
threads; the document-plane stack is a literal, non-metaphorical
rendering of "a page"; the ranked-candidate arrangement borrows the
brand's horizontal rhythm (the same left-to-right reading order the
brand gradient itself uses). It is explicitly **not** a brain, DNA
strand, medical cross, generic AI sphere, globe, blockchain network,
particle cloud, or chatbot — see `NOOR_EVIDENCE_CORE_DESIGN.md` for the
full geometry specification and the explicit rejection list.

### Narrative arc

```
Source document → Verified object → Reviewed layers → Structured
evidence → Retrieval network → Intelligence workspace →
Reverse traceability → Unified Evidence Core
```

Every arrow above is a real, camera- and geometry-driven
transformation, not a cut. The object's identity persists — a viewer
should be able to point at any frame and say "that's still the same
thing I saw at the start, just further along."

### Color system

Reused verbatim from `packages/ui/tokens/colors.ts` — no new palette:

- Environment/ambient: `brandNavy[800]`/`[900]` (deep, calm, not black)
- Key/interaction light: `brandBlue[500]` (Clinical Blue)
- Provenance threads: `brandTeal[500]` (Primary Teal)
- Verified-state pulse: `brandEmerald[500]`
- Atmospheric fill/highlights: `brandCyan[300]`
- Typography: white/near-white DOM text over a contrast-guaranteed
  surface, never raw canvas-background contrast

### Lighting system

Three lights, all with real narrative roles (mission §25):
- A cool, muted Deep-Navy-tinted ambient/hemisphere light present at all times (the environment).
- A directional Clinical-Blue key light whose intensity/angle shifts per scene to imply forward progress.
- A restrained Emerald point light that pulses along the provenance thread exactly once, at the moment Scene 3's review is accepted — never a constant glow. No other scene uses emerald as an ambient tone, so its appearance always means "just verified."

### Particle role

A single low-density point field (see `NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`
for exact counts and device tiers) represents **evidence connections
in transit** — active only in Scene 5 (retrieval) and Scene 7 (reverse
traceability), where "flow between connected things" is the literal
content being communicated. It does not run continuously in every
scene; a particle field with no representational job is decoration,
which the mission explicitly forbids.

### Provenance visualization

A single reusable "thread" material (a thin, additive-blended teal
line with a soft glow, built from `three`'s `TubeGeometry` along a
`CatmullRomCurve3`, not an imported asset) connects every stage to the
one before it. The thread is present from Scene 4 onward and is the
literal object the camera follows backward in Scene 7 — the reverse
traceability sequence is, mechanically, the camera retracing this
exact curve in the opposite direction.

### Final composition

At 100% scroll, the full assembly is visible in one frame: the
original source planes, the review-gate ring, the structured blocks,
the ranked arrangement, the workspace panel, and the unbroken thread
connecting all of them back to the source — the literal image of "one
connected evidence lifecycle," not a stated claim.
