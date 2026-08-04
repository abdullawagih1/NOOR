"use client";

import { useEffect, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";
import type { ReactNode } from "react";

/**
 * Per-section entrance (mission §23) — used identically in the
 * motion-enabled and reduced-motion paths; Framer Motion's own
 * `useReducedMotion` already collapses this to an instant, no-offset
 * reveal when the system preference requests it, so one component
 * correctly serves both.
 *
 * `useReducedMotion()` resolves synchronously on the client's first
 * render (before any effect runs), while the server always renders as
 * if there's no preference — branching the `initial`/`transition`
 * values on it directly produced a real hydration attribute mismatch
 * (opacity/transform, caught via Next's dev overlay), reproducible on
 * every one of the 7 scene sections. `mounted` defers to the server's
 * assumption for exactly the first client render, same fix as
 * CinematicNav and CinematicExperience. The very brief window before
 * mount is not user-visible in practice: `whileInView` doesn't fire
 * until a section scrolls into the viewport, so only Scene 1 (already
 * in view at load) is even in play, and mounting happens well within
 * a single animation frame of hydration completing.
 */
export function SceneSectionReveal({ children }: { children: ReactNode }) {
  const reducedMotion = useReducedMotion();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  const effectiveReducedMotion = mounted && Boolean(reducedMotion);

  return (
    <motion.div
      initial={{ opacity: 0, y: effectiveReducedMotion ? 0 : 16 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-10% 0px -10% 0px" }}
      transition={{ duration: effectiveReducedMotion ? 0 : 0.5, ease: [0.16, 1, 0.3, 1] }}
    >
      {children}
    </motion.div>
  );
}
