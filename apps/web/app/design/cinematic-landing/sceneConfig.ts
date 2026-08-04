/**
 * Single source of truth for the master timeline's scene boundaries,
 * hold/transform pacing, and camera keyframes — matches
 * docs/landing/NOOR_CINEMATIC_SCENE_TIMELINE.md and
 * docs/landing/NOOR_CINEMATIC_CAMERA_MAP.md exactly. Every consumer
 * (the 3D scene, the DOM text overlays, the mobile visibility system)
 * reads from this one file so documentation, geometry, and text can
 * never silently drift apart.
 *
 * LX-1.1.1 revision: desktop mobile camera paths are no longer derived
 * by scaling the desktop path toward the origin (the exact "desktop
 * choreography merely reduced in size" defect the user rejected) —
 * MOBILE_CAMERA_PATHS is now hand-authored independently, closer and
 * simpler than desktop. Scroll boundaries were widened and re-paced
 * (mission §21) to give each scene a real hold window instead of
 * continuous movement for its entire range.
 */

export type Vec3 = readonly [number, number, number];

export interface CameraKeyframe {
  position: Vec3;
  target: Vec3;
  fov: number;
}

export interface SceneDefinition {
  id: number;
  key: string;
  start: number;
  end: number;
  status: "available" | "internal-evaluation" | "product-vision";
  statusLabel: string;
  headline: string;
  supportingCopy: string;
}

export const SCENES: readonly SceneDefinition[] = [
  {
    id: 1,
    key: "trusted-source",
    start: 0,
    end: 0.13,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Clinical intelligence begins with a source you can trust.",
    supportingCopy:
      "NOOR starts with registered, versioned clinical sources — not anonymous text.",
  },
  {
    id: 2,
    key: "secure-intake",
    start: 0.13,
    end: 0.27,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Trust is established before processing begins.",
    supportingCopy:
      "Source identity, file integrity, access boundaries, and processing state are verified before evidence moves forward.",
  },
  {
    id: 3,
    key: "human-review",
    start: 0.27,
    end: 0.44,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Human review is not friction. It is the safety layer.",
    supportingCopy:
      "Automation prepares the evidence. Human review decides when it is ready.",
  },
  {
    id: 4,
    key: "structured-knowledge",
    start: 0.44,
    end: 0.59,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Structure the knowledge. Keep the provenance.",
    supportingCopy:
      "Every chunk remains bound to its exact page, representation, checksum, and source span.",
  },
  {
    id: 5,
    key: "retrieval",
    start: 0.59,
    end: 0.73,
    status: "internal-evaluation",
    statusLabel: "Internal evaluation foundation",
    headline: "Retrieval quality is measured before it's trusted.",
    supportingCopy:
      "NOOR evaluates ranked evidence against frozen, human-judged datasets before retrieval becomes a product capability.",
  },
  {
    id: 6,
    key: "product-vision",
    start: 0.73,
    end: 0.84,
    status: "product-vision",
    statusLabel: "Product vision",
    headline: "Building toward clinical intelligence that stays connected to evidence.",
    supportingCopy:
      "NOOR's product vision is an evidence-first intelligence workspace where claims remain traceable and human authority remains explicit.",
  },
  {
    id: 7,
    key: "reverse-traceability",
    start: 0.84,
    end: 1.0,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Nothing is lost between intelligence and its source.",
    supportingCopy:
      "Intelligence statement, supporting evidence, retrieved chunk, exact source span, original page, trusted guideline — one connected chain.",
  },
] as const;

export const MOBILE_BREAKPOINT_PX = 768;

/** Real document flow drives scroll distance, not an artificial
 * spacer. Widened from LX-1.1's 6/4.2 — the acceptance recording was
 * "too fast" (mission §3.10); each scene now gets more scroll distance
 * to read, observe the transformation, and hold before the next
 * scene begins. */
export const DESKTOP_VH_MULTIPLIER = 8.5;
export const MOBILE_VH_MULTIPLIER = 6.5;

/**
 * Reverse-traceability layer markers (mission §17/§7.2 Scene 7) — six
 * spatially and narratively distinct stops, each with its own label,
 * not merely a camera drifting past the same objects built going
 * forward. `atProgress` is the reverse scene's own local progress
 * (0..1) at which this layer is the current focus.
 */
export interface TraceabilityLayer {
  key: string;
  label: string;
  atProgress: number;
}

export const TRACEABILITY_LAYERS: readonly TraceabilityLayer[] = [
  { key: "intelligence-statement", label: "Intelligence statement", atProgress: 0.02 },
  { key: "supporting-evidence", label: "Supporting evidence", atProgress: 0.2 },
  { key: "retrieved-chunk", label: "Retrieved chunk", atProgress: 0.4 },
  { key: "source-span", label: "Exact source span", atProgress: 0.6 },
  { key: "original-page", label: "Original page", atProgress: 0.78 },
  { key: "trusted-guideline", label: "Trusted guideline", atProgress: 0.95 },
] as const;

/**
 * Desktop camera keyframes. Every scene's path is [holdFrame,
 * holdFrame (repeated), transformFrame] — the repeated keyframe means
 * the camera holds perfectly still for the scene's first ~55% of
 * local progress (while the object transforms and the reader reads),
 * then moves to the next composition only in the final ~45% — a real
 * "hold, then move" rhythm instead of continuous drift for the
 * scene's entire range (mission §21's copy-in/hold/transform/copy-out
 * structure, expressed at the camera level).
 */
const SCENE1_HOLD: CameraKeyframe = { position: [0, 0.15, 3.3], target: [0, 0.05, 0], fov: 38 };
const SCENE2_HOLD: CameraKeyframe = { position: [0.9, 0.35, 3.0], target: [0.25, 0.1, 0], fov: 38 };
const SCENE3_HOLD: CameraKeyframe = { position: [0.35, 0.55, 2.35], target: [0.35, 0.5, 0], fov: 36 };
const SCENE4_HOLD: CameraKeyframe = { position: [1.5, 0.65, 3.1], target: [0.65, 0.35, 0], fov: 40 };
const SCENE5_HOLD: CameraKeyframe = { position: [0.1, 1.0, 4.0], target: [0.1, 0.65, 0], fov: 40 };
const SCENE6_HOLD: CameraKeyframe = { position: [0, 1.35, 3.4], target: [0, 1.05, 0], fov: 36 };
const FINAL_COMPOSITION: CameraKeyframe = { position: [0, 0.75, 6.4], target: [0, 0.35, 0], fov: 46 };
const SCENE1_START: CameraKeyframe = { position: [0, 0.15, 4.6], target: [0, 0.05, 0], fov: 38 };

function holdThenMove(hold: CameraKeyframe, move: CameraKeyframe): readonly CameraKeyframe[] {
  return [hold, hold, move];
}

export const DESKTOP_CAMERA_PATHS: Record<number, readonly CameraKeyframe[]> = {
  1: [SCENE1_START, SCENE1_START, SCENE1_HOLD],
  2: holdThenMove(SCENE1_HOLD, SCENE2_HOLD),
  3: holdThenMove(SCENE2_HOLD, SCENE3_HOLD),
  4: holdThenMove(SCENE3_HOLD, SCENE4_HOLD),
  5: holdThenMove(SCENE4_HOLD, SCENE5_HOLD),
  6: holdThenMove(SCENE5_HOLD, SCENE6_HOLD),
  // Scene 7 visits the six traceability layers as real, distinct
  // camera stops (mission §17), then settles on the full composition
  // — not a blind reversal of the forward path.
  7: [
    SCENE6_HOLD, // 0.00 intelligence statement (reuses the workspace framing it emerged from)
    SCENE5_HOLD, // 0.20 supporting evidence (the ranked arrangement)
    SCENE4_HOLD, // 0.40 retrieved chunk (the structured blocks)
    SCENE3_HOLD, // 0.60 exact source span (the review-gate page, span-highlighted)
    SCENE2_HOLD, // 0.78 original page (the verification framing, page-centered)
    SCENE1_HOLD, // 0.90 trusted guideline (back at the source stack)
    FINAL_COMPOSITION, // 1.00 full Evidence Core + final CTA
  ],
};

/**
 * Mobile camera keyframes — hand-authored independently (never scaled
 * from desktop, mission §3.7/§22): closer and simpler framing, less
 * lateral travel, no wide orbiting, shorter effective path per scene
 * so the object stays legible in a narrow, tall viewport.
 */
const M_SCENE1_START: CameraKeyframe = { position: [0, 0.15, 3.6], target: [0, 0.05, 0], fov: 42 };
const M_SCENE1_HOLD: CameraKeyframe = { position: [0, 0.15, 2.7], target: [0, 0.05, 0], fov: 42 };
const M_SCENE2_HOLD: CameraKeyframe = { position: [0.35, 0.3, 2.55], target: [0.1, 0.1, 0], fov: 42 };
const M_SCENE3_HOLD: CameraKeyframe = { position: [0.15, 0.5, 2.0], target: [0.2, 0.45, 0], fov: 40 };
const M_SCENE4_HOLD: CameraKeyframe = { position: [0.55, 0.6, 2.6], target: [0.3, 0.3, 0], fov: 44 };
const M_SCENE5_HOLD: CameraKeyframe = { position: [0.05, 0.9, 3.3], target: [0.05, 0.6, 0], fov: 44 };
const M_SCENE6_HOLD: CameraKeyframe = { position: [0, 1.15, 2.8], target: [0, 0.95, 0], fov: 40 };
const M_FINAL: CameraKeyframe = { position: [0, 0.6, 5.2], target: [0, 0.3, 0], fov: 50 };

export const MOBILE_CAMERA_PATHS: Record<number, readonly CameraKeyframe[]> = {
  1: [M_SCENE1_START, M_SCENE1_START, M_SCENE1_HOLD],
  2: holdThenMove(M_SCENE1_HOLD, M_SCENE2_HOLD),
  3: holdThenMove(M_SCENE2_HOLD, M_SCENE3_HOLD),
  4: holdThenMove(M_SCENE3_HOLD, M_SCENE4_HOLD),
  5: holdThenMove(M_SCENE4_HOLD, M_SCENE5_HOLD),
  6: holdThenMove(M_SCENE5_HOLD, M_SCENE6_HOLD),
  7: [M_SCENE6_HOLD, M_SCENE5_HOLD, M_SCENE4_HOLD, M_SCENE3_HOLD, M_SCENE2_HOLD, M_SCENE1_HOLD, M_FINAL],
};

export function lerpVec3(a: Vec3, b: Vec3, t: number): Vec3 {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}

/** Evaluates a camera path (an array of >=2 keyframes) at normalized
 * progress t in [0,1], lerping within whichever segment t falls into. */
export function evaluateCameraPath(path: readonly CameraKeyframe[], t: number): CameraKeyframe {
  const clamped = Math.min(1, Math.max(0, t));
  const segmentCount = path.length - 1;
  if (segmentCount <= 0) return path[0];
  const segmentIndex = Math.min(segmentCount - 1, Math.floor(clamped * segmentCount));
  const segmentT = clamped * segmentCount - segmentIndex;
  const from = path[segmentIndex];
  const to = path[segmentIndex + 1];
  return {
    position: lerpVec3(from.position, to.position, segmentT),
    target: lerpVec3(from.target, to.target, segmentT),
    fov: from.fov + (to.fov - from.fov) * segmentT,
  };
}

export function findSceneIndex(progress: number): number {
  const clamped = Math.min(1, Math.max(0, progress));
  for (let i = 0; i < SCENES.length; i++) {
    if (clamped < SCENES[i].end || i === SCENES.length - 1) return i;
  }
  return SCENES.length - 1;
}

export function sceneLocalProgress(progress: number, scene: SceneDefinition): number {
  const span = scene.end - scene.start;
  if (span <= 0) return 0;
  return Math.min(1, Math.max(0, (progress - scene.start) / span));
}
