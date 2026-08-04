"use client";

import { createContext, useContext } from "react";

/**
 * Whether the GSAP master timeline is actually running (i.e.
 * `timelineStore.sceneIndex` is a meaningful, advancing value).
 * `SceneSectionReveal` needs this to decide whether single-scene
 * exclusivity applies: when motion is active, `sceneIndex` genuinely
 * tracks scroll position, so exclusivity is correct (mission §9 "one
 * active scene headline at a time"). When motion is inactive (reduced
 * motion, low-power, WebGL-unavailable), `useMasterTimeline` never
 * creates a ScrollTrigger at all, so `sceneIndex` stays permanently 0
 * — applying exclusivity in that state would hide scenes 2–7 forever,
 * exactly the "reduced motion is visually incomplete" defect the
 * mission rejects. Reduced motion instead falls back to the original
 * reveal-once-and-stay behavior, which is correct there: real native
 * scrolling through real static sections needs no exclusivity.
 */
const MotionActiveContext = createContext(false);

export const MotionActiveProvider = MotionActiveContext.Provider;

export function useMotionActive(): boolean {
  return useContext(MotionActiveContext);
}
