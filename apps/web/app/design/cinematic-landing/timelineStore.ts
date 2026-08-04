/**
 * A tiny external store (React 18 useSyncExternalStore pattern) bridging
 * GSAP's ScrollTrigger onUpdate callback to both React (the DOM text
 * overlays) and React Three Fiber's render loop (the camera rig). No
 * new state-management dependency was added for this — GSAP already
 * runs outside React's render cycle, so a subscribable plain object is
 * the correct minimal tool, not a reason to reach for Zustand/Redux.
 */

export interface TimelineState {
  progress: number;
  sceneIndex: number;
  sceneLocalProgress: number;
}

const initialState: TimelineState = { progress: 0, sceneIndex: 0, sceneLocalProgress: 0 };

let state: TimelineState = initialState;
const listeners = new Set<() => void>();

export function getTimelineState(): TimelineState {
  return state;
}

export function setTimelineState(next: TimelineState): void {
  state = next;
  // Test-safe global (mission §37 — "expose test-safe scene-state
  // markers where needed"): harmless scroll-progress numbers, no
  // secrets, no PII. Needed because the `?debug=1` overlay is
  // correctly hard-disabled whenever NODE_ENV==="production" (mission
  // §25) — including on a Preview deployment used specifically for
  // this kind of automated verification, so this is the only way an
  // external test script can read real scene/progress state there.
  if (typeof window !== "undefined") {
    (window as unknown as { __noorCinematicTimeline?: TimelineState }).__noorCinematicTimeline = next;
  }
  listeners.forEach((listener) => listener());
}

export function resetTimelineState(): void {
  setTimelineState(initialState);
}

export function subscribeTimeline(callback: () => void): () => void {
  listeners.add(callback);
  return () => listeners.delete(callback);
}
