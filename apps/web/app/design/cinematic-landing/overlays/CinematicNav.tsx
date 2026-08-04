"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { useReducedMotion as useSystemReducedMotion } from "framer-motion";
import { SCENES } from "../sceneConfig";
import { useTimelineState } from "../useTimelineState";
import { useReducedMotionOverrideControl } from "../../landing-experience/useEffectiveReducedMotion";

/**
 * Minimal nav (mission §35) — logo, scene-progress indicator, sign in,
 * and a "Reduce motion" control that only ever offers to go *further*
 * than the OS preference (mission §29 — never overrides the OS default
 * by default, and is hidden entirely when the OS already requests
 * reduced motion, since there's nothing left for it to offer).
 *
 * `systemReducedMotion` is a client-only media-query read — the server
 * always renders as if there's no preference, so hiding the checkbox
 * immediately from `systemReducedMotion` produced a real hydration
 * mismatch (caught via Next's dev overlay + a real console error, not
 * inspection) whenever a visitor's OS actually requests reduced
 * motion. `mounted` defers the conditional hide until after hydration
 * completes, matching the server's first-paint output exactly.
 */
export function CinematicNav() {
  const { sceneIndex } = useTimelineState();
  const systemReducedMotion = useSystemReducedMotion();
  const { override, setOverride } = useReducedMotionOverrideControl();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <nav className="pointer-events-none fixed inset-x-0 top-0 z-30 flex items-center justify-between px-lg py-md sm:px-xl">
      <Link href="/" className="pointer-events-auto inline-flex items-center rounded-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent" aria-label="Noor home">
        <Image src="/brand/noor-logo-navigation.png" alt="Noor" width={121} height={100} className="h-8 w-auto sm:h-9" priority />
      </Link>

      <ol className="hidden items-center gap-xs sm:flex" aria-label="Scene progress">
        {SCENES.map((scene, index) => (
          <li key={scene.id}>
            <span
              className="block h-1.5 w-5 rounded-pill transition-colors"
              style={{ backgroundColor: index === sceneIndex ? "#09B993" : "rgba(255,255,255,0.25)" }}
              aria-hidden="true"
            />
          </li>
        ))}
      </ol>
      <span className="sr-only" aria-live="polite">
        Scene {sceneIndex + 1} of {SCENES.length}: {SCENES[sceneIndex].headline}
      </span>

      <div className="pointer-events-auto flex items-center gap-md">
        {!mounted || !systemReducedMotion ? (
          <label className="flex items-center gap-xs text-xs text-white/80">
            <input type="checkbox" checked={override === true} onChange={(event) => setOverride(event.target.checked ? true : null)} />
            Reduce motion
          </label>
        ) : null}
        <Link
          href="/login"
          className="rounded-sm bg-primary px-md py-xs text-sm font-medium text-on-primary transition-colors hover:bg-primary-active focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          Sign in
        </Link>
      </div>
    </nav>
  );
}
