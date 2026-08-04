/**
 * Single source of truth for the master timeline's scene boundaries and
 * camera keyframes — matches docs/landing/NOOR_CINEMATIC_SCENE_TIMELINE.md
 * and docs/landing/NOOR_CINEMATIC_CAMERA_MAP.md exactly. Both the R3F
 * camera rig and the DOM text overlays read from this one file so the
 * documentation, the 3D scene, and the text never drift apart.
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
    end: 0.14,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Clinical intelligence begins with a source you can trust.",
    supportingCopy:
      "NOOR starts with registered, versioned clinical sources — not anonymous text.",
  },
  {
    id: 2,
    key: "secure-intake",
    start: 0.14,
    end: 0.28,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Trust is established before processing begins.",
    supportingCopy:
      "Source identity, file integrity, access boundaries, and processing state are verified before evidence moves forward.",
  },
  {
    id: 3,
    key: "human-review",
    start: 0.28,
    end: 0.43,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Human review is not friction. It is the safety layer.",
    supportingCopy:
      "NOOR does not allow automated processing to silently become trusted knowledge.",
  },
  {
    id: 4,
    key: "structured-knowledge",
    start: 0.43,
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
    end: 0.86,
    status: "product-vision",
    statusLabel: "Product vision",
    headline: "Building toward clinical intelligence that stays connected to evidence.",
    supportingCopy:
      "NOOR's product vision is an evidence-first intelligence workspace where claims remain traceable and human authority remains explicit.",
  },
  {
    id: 7,
    key: "reverse-traceability",
    start: 0.86,
    end: 1.0,
    status: "available",
    statusLabel: "Available foundation",
    headline: "Nothing is lost between intelligence and its source.",
    supportingCopy:
      "Intelligence statement, supporting evidence, retrieved chunk, exact source span, original page, trusted guideline — one connected chain.",
  },
] as const;

export const MOBILE_BREAKPOINT_PX = 768;

/** Each scene's DOM section is sized to this many viewport-heights
 * times its (end-start) scroll fraction — real document flow drives
 * the scroll distance, not an artificial spacer. Mobile gets a
 * shorter total journey (~70% of desktop), matching
 * docs/landing/NOOR_CINEMATIC_MOBILE_STRATEGY.md. */
export const DESKTOP_VH_MULTIPLIER = 6;
export const MOBILE_VH_MULTIPLIER = 4.2;

/** End-of-scene camera keyframes (desktop). Scene N's path runs from
 * scene (N-1)'s end keyframe to its own end keyframe (or an internal
 * array of sub-keyframes for scenes with a lateral drift). Scene 7's
 * path is built separately, below, as a literal reversal of these. */
const SCENE1_END: CameraKeyframe = { position: [0, 0.3, 5.0], target: [0, 0, 0], fov: 45 };
const SCENE2_END: CameraKeyframe = { position: [1.6, 0.6, 4.4], target: [0.2, 0.1, 0], fov: 44 };
const SCENE3_END: CameraKeyframe = { position: [0.6, 0.9, 3.0], target: [0.4, 0.6, 0], fov: 40 };
const SCENE4_MID: CameraKeyframe = { position: [2.4, 1.1, 5.0], target: [0.6, 0.3, 0], fov: 45 };
const SCENE4_END: CameraKeyframe = { position: [3.4, 1.1, 4.2], target: [0.6, 0.3, 0], fov: 45 };
const SCENE5_END: CameraKeyframe = { position: [0, 1.5, 6.2], target: [0, 0.6, 0], fov: 42 };
const SCENE6_END: CameraKeyframe = { position: [0, 1.9, 4.6], target: [0, 1.0, 0], fov: 38 };
const SCENE1_START: CameraKeyframe = { position: [0, 0.3, 6.5], target: [0, 0, 0], fov: 45 };
const FINAL_COMPOSITION: CameraKeyframe = { position: [0, 1.0, 9.5], target: [0, 0.3, 0], fov: 50 };

export const DESKTOP_CAMERA_PATHS: Record<number, readonly CameraKeyframe[]> = {
  1: [SCENE1_START, SCENE1_END],
  2: [SCENE1_END, SCENE2_END],
  3: [SCENE2_END, SCENE3_END],
  4: [SCENE3_END, SCENE4_MID, SCENE4_END],
  5: [SCENE4_END, SCENE5_END],
  6: [SCENE5_END, SCENE6_END],
  // Scene 7 is a literal reverse traversal of the forward path, per
  // docs/landing/NOOR_CINEMATIC_CAMERA_MAP.md — not a separately
  // designed camera move.
  7: [SCENE6_END, SCENE5_END, SCENE4_END, SCENE3_END, SCENE2_END, SCENE1_END, FINAL_COMPOSITION],
};

const scale = (kf: CameraKeyframe, factor: number, fovDelta: number): CameraKeyframe => ({
  position: [kf.position[0] * factor, kf.position[1] * factor, kf.position[2] * factor],
  target: [kf.target[0] * factor, kf.target[1] * factor, kf.target[2] * factor],
  fov: kf.fov + fovDelta,
});

/** Mobile keyframes are shorter-travel, narrower-parallax versions of
 * the desktop path — see NOOR_CINEMATIC_MOBILE_STRATEGY.md. Derived
 * mechanically (scaled toward the origin, FOV widened) rather than
 * hand-authored twice, so the two paths can never silently diverge in
 * narrative meaning — only in travel distance. */
export const MOBILE_CAMERA_PATHS: Record<number, readonly CameraKeyframe[]> = Object.fromEntries(
  Object.entries(DESKTOP_CAMERA_PATHS).map(([sceneId, path]) => [
    sceneId,
    path.map((kf) => scale(kf, 0.82, 5)),
  ])
);

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
