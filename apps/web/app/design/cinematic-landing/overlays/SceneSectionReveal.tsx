"use client";

import { useEffect, useRef, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";
import type { ReactNode } from "react";
import { useActiveSceneIndex } from "../useActiveSceneIndex";
import { useMotionActive } from "../MotionActiveContext";
import { MOBILE_BREAKPOINT_PX } from "../sceneConfig";

/**
 * Per-section entrance (mission §23) plus, when the GSAP timeline is
 * actually running, exclusive single-scene visibility (mission §9
 * "One active scene headline at a time" / §3.7 "only one active
 * narrative copy block at a time"). LX-1.1.1's first pass gated
 * exclusivity to mobile only, reasoning desktop had no overlap
 * complaint — a real screenshot at 1440×900 disproved that directly:
 * two tall adjacent sections' already-revealed (`whileInView` fires
 * once and stays forever) text both landed in the same viewport near
 * a scene boundary. Exclusivity now applies on every viewport
 * whenever motion is active; only the transition duration differs by
 * breakpoint (mission §22's 180–260ms guidance for the mobile
 * crossfade, a touch slower on desktop where it reads as a deliberate
 * dissolve rather than a snap).
 *
 * Exclusivity is gated on `useMotionActive()` specifically because
 * `useMasterTimeline` never creates a ScrollTrigger in reduced-motion/
 * static mode — `sceneIndex` would stay permanently 0, and applying
 * exclusivity there would hide scenes 2–7 forever. Reduced motion
 * instead keeps the original reveal-once-and-stay behavior, which is
 * correct for real native scrolling through real static sections.
 *
 * `useReducedMotion()` resolves synchronously on the client's first
 * render while SSR assumes no preference — branching directly on it
 * produced a real hydration mismatch in LX-1.1 (reproduced on all 7
 * sections). `mounted` defers the branch until after hydration, same
 * fix as CinematicNav/CinematicExperience.
 *
 * A real `@axe-core/playwright` scan (mobile viewports specifically —
 * Scene 7's "Sign in to NOOR" / "Explore the evidence journey again"
 * links are the only focusable content inside these wrappers) caught
 * that `aria-hidden` + `pointer-events: none` alone does NOT remove an
 * element from the keyboard tab order — a hidden section's links
 * stayed Tab-reachable, which axe correctly flags (`aria-hidden-focus`):
 * an aria-hidden subtree must never contain focusable content. Fixed
 * with the native `inert` DOM property (not a React prop — this
 * TypeScript/React version's JSX types don't include it — set
 * imperatively via a ref), which is exactly the platform feature built
 * for "hidden and fully non-interactive," removing both focusability
 * and AT exposure in one step.
 */
export function SceneSectionReveal({ children, sceneId }: { children: ReactNode; sceneId: number }) {
  const reducedMotion = useReducedMotion();
  const [mounted, setMounted] = useState(false);
  const [isMobileViewport, setIsMobileViewport] = useState(false);
  const activeSceneIndex = useActiveSceneIndex();
  const motionActive = useMotionActive();
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    const query = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT_PX - 1}px)`);
    setIsMobileViewport(query.matches);
    const listener = (event: MediaQueryListEvent) => setIsMobileViewport(event.matches);
    query.addEventListener("change", listener);
    return () => query.removeEventListener("change", listener);
  }, []);

  const effectiveReducedMotion = mounted && Boolean(reducedMotion);
  const useExclusivity = mounted && motionActive;
  const isCurrent = activeSceneIndex === sceneId - 1;
  const exclusiveVisible = !useExclusivity || isCurrent;
  const transitionDuration = effectiveReducedMotion ? 0 : isMobileViewport ? 0.2 : 0.32;
  const hidden = useExclusivity && !exclusiveVisible;

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    (el as HTMLDivElement & { inert: boolean }).inert = hidden;
  }, [hidden]);

  return (
    <motion.div
      ref={containerRef}
      initial={{ opacity: 0, y: effectiveReducedMotion ? 0 : 16 }}
      animate={useExclusivity ? { opacity: exclusiveVisible ? 1 : 0, y: 0 } : undefined}
      whileInView={useExclusivity ? undefined : { opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-10% 0px -10% 0px" }}
      transition={{ duration: transitionDuration, ease: [0.16, 1, 0.3, 1] }}
      style={{ pointerEvents: exclusiveVisible ? "auto" : "none" }}
      aria-hidden={hidden}
      data-scene-active={useExclusivity ? exclusiveVisible : undefined}
    >
      {children}
    </motion.div>
  );
}
