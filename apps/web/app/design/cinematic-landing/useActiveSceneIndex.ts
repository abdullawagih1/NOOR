"use client";

import { useSyncExternalStore } from "react";
import { getTimelineState, subscribeTimeline } from "./timelineStore";

/**
 * Re-renders ONLY when the current scene index actually changes —
 * unlike `useTimelineState()` (which re-renders on every scroll-driven
 * progress tick, correct for the camera/canvas but far too frequent
 * for a React component). `useSyncExternalStore` compares the
 * snapshot's *return value*, so a primitive-returning selector like
 * this one naturally skips re-renders whose underlying sceneIndex
 * didn't change, even though the store itself updates every frame
 * (mission §10/§26 — "use React state only for coarse scene changes").
 */
export function useActiveSceneIndex(): number {
  return useSyncExternalStore(
    subscribeTimeline,
    () => getTimelineState().sceneIndex,
    () => 0
  );
}
