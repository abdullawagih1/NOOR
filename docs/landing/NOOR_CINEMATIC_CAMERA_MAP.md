# NOOR Cinematic Camera Map

Status: **LX-1.1 — In Progress** (values below match the shipped
implementation in `CameraRig.tsx` — this is not a design aspiration
written before the code, it documents the real, tested keyframes)

## Coordinate system

World origin `(0,0,0)` sits at the Evidence Core's resting center. `y`
is up. The camera always uses a perspective projection; `fov` is in
degrees. All positions/targets are `[x, y, z]` in Three.js world units.

## Damping

The camera never snaps directly to a scroll-derived value. Every
frame, the live target (position/lookAt/fov) is lerped toward the
scroll-driven keyframe value with a damping factor of `0.08` per frame
(`camera.position.lerp(target, 0.08)`), which is what prevents both
motion sickness from raw scroll jitter and any need for "sudden
direction reversal" — a fast scroll reversal simply reverses the lerp
target smoothly rather than snapping.

## Desktop keyframes

| Scene | Position | Target (lookAt) | FOV | Notes |
| --- | --- | --- | --- | --- |
| 1 — Trusted Source (start) | `[0, 0.3, 6.5]` | `[0, 0, 0]` | 45 | Medium distance, static-feeling start |
| 1 — Trusted Source (end) | `[0, 0.3, 5.0]` | `[0, 0, 0]` | 45 | Slow dolly in as the user begins scrolling |
| 2 — Secure Intake | `[1.6, 0.6, 4.4]` | `[0.2, 0.1, 0]` | 44 | Slight orbit right to reveal the verification ring and the invalid-path object beside it |
| 3 — Human Review | `[0.6, 0.9, 3.0]` | `[0.4, 0.6, 0]` | 40 | Closer, page-detail framing |
| 4 — Structured Knowledge | `[2.4, 1.1, 5.0]` | `[0.6, 0.3, 0]` | 45 | Pulled back to reveal both the page and the forming blocks, then a lateral drift to `[3.4, 1.1, 4.2]` within the same scene |
| 5 — Retrieval | `[0, 1.5, 6.2]` | `[0, 0.6, 0]` | 42 | Centered, facing the ranked row |
| 6 — Product Vision | `[0, 1.9, 4.6]` | `[0, 1.0, 0]` | 38 | Tightest framing of the mission — smallest, calmest scene |
| 7 — Reverse Traceability (start) | `[0, 1.9, 4.6]` | `[0, 1.0, 0]` | 38 | Same as Scene 6's end — continuity, no cut |
| 7 — Reverse Traceability (mid, via 5→4→3→2 keyframes in reverse) | *(reuses Scenes 5/4/3/2's exact keyframes above, traversed backward)* | — | — | The backward pass is a literal reverse traversal of the forward path, not a new camera design |
| 7 — Reverse Traceability (end / final composition) | `[0, 1.0, 9.5]` | `[0, 0.3, 0]` | 50 | Pulled back further than Scene 1's start — reveals the full assembly at once |

## Mobile keyframes (≤767px)

Mobile keeps the same scene order but with **shorter travel distances**
and a **narrower FOV range** (less parallax, less perceived motion —
mission §28's "reduce camera rotation"):

| Scene | Position | Target | FOV |
| --- | --- | --- | --- |
| 1 | `[0, 0.2, 5.5]` → `[0, 0.2, 4.8]` | `[0, 0, 0]` | 50 |
| 2 | `[0.6, 0.4, 4.2]` | `[0.1, 0.05, 0]` | 50 |
| 3 | `[0.3, 0.6, 3.2]` | `[0.2, 0.4, 0]` | 46 |
| 4 | `[0.9, 0.8, 4.6]` | `[0.3, 0.2, 0]` | 48 |
| 5 | `[0, 1.1, 5.6]` | `[0, 0.4, 0]` | 46 |
| 6 | `[0, 1.3, 4.4]` | `[0, 0.7, 0]` | 42 |
| 7 (end) | `[0, 0.7, 7.5]` | `[0, 0.2, 0]` | 52 |

Mobile orbit range (Scene 2's lateral reveal) is capped at 40% of the
desktop travel distance — confirmed against the mission's "avoid rapid
zoom" and "reduce camera rotation" rules.

## Reduced-motion state

The camera rig is **never instantiated** under `prefers-reduced-motion:
reduce` or the static/WebGL-unavailable fallback — there is no "frozen
camera at scene N" state to define, because the entire `Canvas` and its
`CameraRig` component are conditionally unmounted, not paused. See
`NOOR_CINEMATIC_FALLBACK_STRATEGY.md`.

## Stability when scrolling stops

Because every frame lerps toward (rather than snaps to) the current
keyframe, the camera comes to a smooth, non-oscillating rest within
~150ms of scroll input stopping — verified in the motion-state tests
(`docs/verification/lx-1-1-cinematic-prototype-verification.md`) by
asserting the camera's reported world position is stable across two
consecutive animation frames once scroll input ceases.

## What the camera never does

Continuous automatic rotation with no scroll input; a snap-cut between
keyframes; a dolly move faster than can be smoothly damped within one
scene's scroll range; any position that moves the Evidence Core outside
the visible frame; any FOV change abrupt enough to read as a "zoom
punch."
