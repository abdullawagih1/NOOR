# NOOR Cinematic Camera Map

Status: **LX-1.1.1 — Complete.** Values below match the shipped
implementation in `EvidenceCoreScene.ts`'s `updateCamera()` method and
the keyframe constants in `sceneConfig.ts` exactly — this documents the
real, tested camera path, not a design aspiration written before the
code. Superseded from LX-1.1: the camera is no longer built with
`@react-three/fiber`'s `CameraRig.tsx` (removed — see
`NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md` §"Why raw Three.js"); it's a
plain `THREE.PerspectiveCamera` updated imperatively every frame.

## Coordinate system

World origin `(0,0,0)` sits at the Evidence Core's resting center. `y`
is up. The camera always uses a perspective projection; `fov` is in
degrees. All positions/targets are `[x, y, z]` in Three.js world units.

## Hold-then-move rhythm (LX-1.1.1 revision)

The user's rejection named the acceptance recording as "too fast" —
traced to the camera moving continuously across a scene's *entire*
scroll range, giving no time to read the headline, observe the object,
or register cause-and-effect. Every scene's camera path is now defined
as **three keyframes**: `[holdFrame, holdFrame (repeated), moveFrame]`.
Because `evaluateCameraPath()` lerps proportionally between consecutive
array entries, a repeated keyframe produces a genuine hold — the
camera sits still for the scene's first ~55% of local scroll progress
(while the reader reads and the object transforms), then moves to the
next scene's framing only in the final ~45%, arriving just as the next
section becomes current. This is a real code-level change
(`holdThenMove()` in `sceneConfig.ts`), not a documentation-only
adjustment.

## Damping

The camera never snaps directly to a scroll-derived value. Every
frame, the live position/lookAt/fov is lerped toward the scroll-driven
keyframe value with a damping factor of `0.075` per frame
(`camera.position.lerp(target, DAMPING)`), which is what prevents both
motion sickness from raw scroll jitter and any need for "sudden
direction reversal" — a fast scroll reversal simply reverses the lerp
target smoothly rather than snapping.

## Desktop keyframes

Camera framing was brought substantially closer for LX-1.1.1 (user
feedback: "core too small and too dark, increase the Evidence Core's
screen-space presence... approximately 40–60% of the useful viewport")
— compare `z: 6.5` (LX-1.1 Scene 1 start) to `z: 4.6` below.

| Scene | Hold position | Hold target | Move-to position | Move-to target | FOV |
| --- | --- | --- | --- | --- | --- |
| 1 — Trusted Source | `[0, 0.15, 4.6]` (start) | `[0, 0.05, 0]` | `[0, 0.15, 3.3]` | `[0, 0.05, 0]` | 38 |
| 2 — Secure Intake | `[0, 0.15, 3.3]` | `[0, 0.05, 0]` | `[0.9, 0.35, 3.0]` | `[0.25, 0.1, 0]` | 38 |
| 3 — Human Review | `[0.9, 0.35, 3.0]` | `[0.25, 0.1, 0]` | `[0.35, 0.55, 2.35]` | `[0.35, 0.5, 0]` | 36 |
| 4 — Structured Knowledge | `[0.35, 0.55, 2.35]` | `[0.35, 0.5, 0]` | `[1.5, 0.65, 3.1]` | `[0.65, 0.35, 0]` | 40 |
| 5 — Retrieval | `[1.5, 0.65, 3.1]` | `[0.65, 0.35, 0]` | `[0.1, 1.0, 4.0]` | `[0.1, 0.65, 0]` | 40 |
| 6 — Product Vision | `[0.1, 1.0, 4.0]` | `[0.1, 0.65, 0]` | `[0, 1.35, 3.4]` | `[0, 1.05, 0]` | 36 |
| 7 — Reverse Traceability | 6 real stops, below | | | | |

### Scene 7 — six distinct camera stops (LX-1.1.1 rebuild)

LX-1.1's Scene 7 was a blind reversal of the forward path with no
distinct visual marker per layer — the user's rejection named this
directly ("does not make the chain visually obvious... camera and
objects must physically reveal the chain"). The camera path is
unchanged in *shape* (it still revisits the earlier scenes' framings
in reverse, since that framing already correctly shows each stage's
object) but is now paired with a **traceability marker** — a bright
ring rendered at the exact world position of whichever of the 6 named
layers is current, driven by `TRACEABILITY_LAYERS` in `sceneConfig.ts`
independent of camera position — so every stop is identified by more
than "the camera happens to be near it":

| Local progress | Layer | Camera frame reused | Marker anchor |
| --- | --- | --- | --- |
| 0.00 | Intelligence statement | Scene 6's hold frame | Workspace panel position |
| 0.20 | Supporting evidence | Scene 5's hold frame | Top-ranked candidate position |
| 0.40 | Retrieved chunk | Scene 4's hold frame | First structured block's rest position |
| 0.60 | Exact source span | Scene 3's hold frame | The finding-marker's page coordinate |
| 0.78 | Original page | Scene 2's hold frame | The verification aperture position |
| 0.95 | Trusted guideline | Scene 1's hold frame | The left document tower |
| 1.00 | Final composition | `[0, 0.75, 6.4]` / target `[0, 0.35, 0]`, FOV 46 | — full assembly, marker fades out |

## Mobile keyframes (≤767px) — independently authored, not scaled

LX-1.1's mobile path was mechanically derived by scaling the desktop
keyframes toward the origin — exactly the "desktop choreography merely
reduced in size" defect named in the rejection. LX-1.1.1's mobile path
is hand-authored: closer starting distance, less lateral travel, a
narrower FOV range (mission §28 "reduce camera rotation").

| Scene | Hold position | Hold target | Move-to position | Move-to target | FOV |
| --- | --- | --- | --- | --- | --- |
| 1 | `[0, 0.15, 3.6]` (start) | `[0, 0.05, 0]` | `[0, 0.15, 2.7]` | `[0, 0.05, 0]` | 42 |
| 2 | `[0, 0.15, 2.7]` | `[0, 0.05, 0]` | `[0.35, 0.3, 2.55]` | `[0.1, 0.1, 0]` | 42 |
| 3 | `[0.35, 0.3, 2.55]` | `[0.1, 0.1, 0]` | `[0.15, 0.5, 2.0]` | `[0.2, 0.45, 0]` | 40 |
| 4 | `[0.15, 0.5, 2.0]` | `[0.2, 0.45, 0]` | `[0.55, 0.6, 2.6]` | `[0.3, 0.3, 0]` | 44 |
| 5 | `[0.55, 0.6, 2.6]` | `[0.3, 0.3, 0]` | `[0.05, 0.9, 3.3]` | `[0.05, 0.6, 0]` | 44 |
| 6 | `[0.05, 0.9, 3.3]` | `[0.05, 0.6, 0]` | `[0, 1.15, 2.8]` | `[0, 0.95, 0]` | 40 |
| 7 | Same 6-stop reversal as desktop, mobile keyframes | | `[0, 0.6, 5.2]` final | `[0, 0.3, 0]` | 50 |

Note: on mobile, the 3D camera path above only ever renders inside the
fixed 46vh visual zone (`NOOR_CINEMATIC_MOBILE_CHOREOGRAPHY.md`) — the
copy zone below it is unaffected by camera position.

## Reduced-motion state

The camera rig is **never instantiated** under `prefers-reduced-motion:
reduce`, on a narrow viewport combined with low quality tier, or the
static/WebGL-unavailable fallback — `CinematicExperience`'s
`motionActive` decision gates the entire `CinematicCanvas` mount, so
there is no "frozen camera at scene N" state to define. See
`NOOR_CINEMATIC_REDUCED_MOTION_SYSTEM.md`.

## Stability when scrolling stops

Because every frame lerps toward (rather than snaps to) the current
keyframe, the camera comes to a smooth, non-oscillating rest shortly
after scroll input stops — confirmed by the real motion-state
checkpoints in `docs/verification/lx-1-1-1-cinematic-polish-verification.md`,
each independently re-derived via a binary-search calibration against
the app's own reported scroll progress rather than assumed from a
fixed wait time.

## What the camera never does

Continuous automatic rotation with no scroll input; a snap-cut between
keyframes; a dolly move faster than can be smoothly damped within the
hold-then-move window; any position that moves the Evidence Core
outside the visible frame; any FOV change abrupt enough to read as a
"zoom punch."
