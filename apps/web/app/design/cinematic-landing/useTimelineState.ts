"use client";

import { useSyncExternalStore } from "react";
import { getTimelineState, subscribeTimeline, type TimelineState } from "./timelineStore";

/** React-reactive read of the timeline store — for DOM text overlays.
 * The R3F camera rig reads the store directly inside useFrame instead
 * (a per-frame imperative read, not a React re-render). */
export function useTimelineState(): TimelineState {
  return useSyncExternalStore(subscribeTimeline, getTimelineState, getTimelineState);
}
