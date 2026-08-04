"use client";

import { SCENES } from "./sceneConfig";
import { useVisibleSceneId } from "./useVisibleSceneId";
import { ReducedMotionIllustration } from "./ReducedMotionIllustrations";

/**
 * The reduced-motion / WebGL-unavailable / low-power background
 * (mission §23, §31). LX-1.1's version was a plain gradient with no
 * content — the concrete "reduced motion is mostly empty" defect the
 * user rejected. Now renders the current scene's complete
 * illustration (mission §23's full per-scene requirement list),
 * tracked via `useVisibleSceneId` (a plain IntersectionObserver — this
 * path never runs GSAP/ScrollTrigger, mission §23 "no scrub
 * timeline"), positioned in its own visual zone on the opposite side
 * from the text column so neither ever overlaps the other.
 */
export function StaticPoster() {
  const visibleId = useVisibleSceneId(SCENES.length);
  const scene = SCENES.find((s) => s.id === visibleId) ?? SCENES[0];

  return (
    <div
      className="flex h-full w-full items-center justify-center px-lg sm:items-center sm:justify-end sm:pr-xl lg:pr-xxl"
      style={{
        background: "radial-gradient(circle at 65% 40%, #0C3258 0%, #050F1E 60%, #020A14 100%)",
      }}
    >
      <div className="w-full max-w-[220px] sm:max-w-md">
        <ReducedMotionIllustration sceneKey={scene.key} />
      </div>
    </div>
  );
}
