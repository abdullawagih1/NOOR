# NOOR Evidence Core — Geometry Design

Status: **LX-1.1 — Complete.** Every geometry/material/lighting
decision below shipped exactly as designed. The one change from the
original plan is *how* it's built and updated — plain, imperative
`three` code (a class with an `update()` method called from a
`requestAnimationFrame` loop) rather than `@react-three/fiber`
components — see `NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md`
§"Why raw Three.js" for the real upstream compatibility issue that
caused the switch. Every "docs/landing/NOOR_EVIDENCE_CORE_DESIGN.md §N"
cross-reference in the codebase still points at the same design
described here.

## Construction principle

Everything is procedural — built in code from primitive geometry
(`PlaneGeometry`, `TorusGeometry`, `TubeGeometry`, `IcosahedronGeometry`
for low-poly blocks, `BufferGeometry` for particles) and standard
materials (`MeshStandardMaterial`/`MeshPhysicalMaterial` used
sparingly). **No imported GLB/GLTF asset is used anywhere in this
mission.** This keeps the bundle small, keeps the object's identity
fully within NOOR's own control (no third-party license to track), and
matches the mission's explicit preference for code-built geometry over
imported models.

## Explicit rejection list (mission §3, restated as a build constraint)

The Evidence Core is never rendered as: a human brain, a DNA strand, a
medical cross, a generic AI sphere, a rotating globe, a blockchain
network, a generic particle cloud with no representational role, a
chatbot avatar, or a copy of any object from the supplied reference
video. Every element below was chosen specifically because it maps to
a real NOOR concept, not because it "looks advanced."

## Component inventory

### 1. Document planes (`DocumentStack`)

- 5 thin (`0.02` depth) rounded-corner planes, stacked with a `0.06`
  unit gap, slightly rotated (±1.5°) off-axis so the stack reads as
  physical, not a perfect digital slab.
- Material: `MeshStandardMaterial`, low roughness, a faint procedural
  "page marking" achieved with a `CanvasTexture` of thin horizontal
  lines generated at runtime (not an imported image) at low opacity —
  suggests text density without rendering any real or fabricated
  clinical content.
- This is the object present from Scene 1 onward; nothing else
  replaces it — everything else forms *around* it.

### 2. Verification ring (`VerificationRing`)

- A thin `TorusGeometry` encircling the document stack on the
  horizontal plane, appearing in Scene 2.
- Starts fully transparent/`brandBlue[300]`-tinted (pending), animates
  to a solid `brandTeal[500]` stroke with a short emissive pulse when
  verification resolves.
- The **invalid-path object** (Scene 2's rejected file) is a second,
  smaller, duller copy of the document-stack geometry that approaches
  the ring on a separate path and visibly stops — its material never
  reaches the "verified" color and its position tweens to a dead stop
  outside the ring's radius, never crossing it.

### 3. Review gate (`ReviewGate`)

- One page plane detaches from the stack and enlarges toward the
  camera (Scene 3).
- A small lock glyph (a simple procedural shackle-and-body shape built
  from two `TorusGeometry`/`BoxGeometry` primitives, not an imported
  icon) sits in front of it, rotated open when the review resolves.
- A `finding` marker: a small `brandBlue[300]`-tinted rectangle
  overlaid on one region of the enlarged page, present before
  resolution and fading out at acceptance (it has done its job once
  the reviewer decision has been made).

### 4. Structured blocks (`StructuredBlocks`)

- 3 small rounded-box primitives, each spawned from a highlighted
  region on the enlarged page (Scene 4), each connected back to its
  origin point on the page by a `ProvenanceThread` (below).
- Blocks are visually identical in shape/material to keep attention on
  the *connection*, not on decorative variety.

### 5. Provenance thread (`ProvenanceThread`)

- A `TubeGeometry` swept along a `CatmullRomCurve3` between two world
  positions, additive-blended `brandTeal[500]` material with a subtle
  emissive core.
- One thread per structured block (Scene 4+), plus one long
  "spine" thread that the camera follows during Scene 7's reverse
  traceability — the spine thread's control points are exactly the
  world positions of the source stack, the review-gate page, the
  first structured block, and the ranked-candidate arrangement, so the
  backward camera move is a literal traversal of already-existing
  geometry, not a separate animation.

### 6. Ranked arrangement (`RankedCandidates`)

- The 3 structured blocks reposition into a shallow, camera-facing
  row with graduated spacing/scale (Scene 5) — the closest/largest
  reads as "most relevant," matching the mission's 3-tier ranking
  requirement.
- A thin `brandCyan[300]` beam (a flattened, low-opacity plane, not a
  particle effect) represents the "query signal" arriving from off-
  camera and terminating at the top candidate.

### 7. Workspace panel (`WorkspacePanel`)

- A single flat, semi-transparent rounded panel (Scene 6) condensing
  in front of the ranked row, connected to it by the same thread
  material.
- Carries **no readable text inside the canvas** — its DOM overlay
  (see `NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md`) supplies the actual
  synthetic statement/status label. The 3D panel itself is a plain
  surface with a soft edge glow, communicating "a workspace exists,"
  not the workspace's content.

### 8. Particle field (`EvidenceParticles`)

- A single `BufferGeometry` point cloud, instanced once, visibility/
  opacity toggled per-scene rather than recreated. See
  `NOOR_CINEMATIC_PERFORMANCE_BUDGET.md` for exact counts.

## Materials summary

| Element | Material | Color source |
| --- | --- | --- |
| Document planes | `MeshStandardMaterial`, roughness 0.6 | `brandNavy[100]` tint on `brandNavy[900]` ground |
| Verification ring | `MeshStandardMaterial`, emissive | `brandBlue[300]` → `brandTeal[500]` |
| Review lock | `MeshStandardMaterial`, low roughness | `brandBlue[400]` |
| Structured blocks | `MeshStandardMaterial` | `brandTeal[300]` |
| Provenance threads | `MeshBasicMaterial`, additive blending | `brandTeal[500]`, emissive core `brandEmerald[400]` only during the Scene 3 pulse |
| Ranked-candidate beam | `MeshBasicMaterial`, transparent | `brandCyan[300]` |
| Workspace panel | `MeshPhysicalMaterial`, transmission (used once, sparingly) | `brandCyan[300]`/white edge |
| Particles | `PointsMaterial`, additive, low opacity | `brandTeal[300]`/`brandCyan[300]` mix |

## No external asset was used

Confirmed: zero `.glb`/`.gltf`/`.hdr`/texture-image files were added to
this repository for LX-1.1. The one runtime-generated `CanvasTexture`
(page markings) is produced by code, not loaded from a file, so there
is no license, size, or fallback concern to document for it beyond
what's already covered by the geometry budget in
`NOOR_CINEMATIC_PERFORMANCE_BUDGET.md`.
