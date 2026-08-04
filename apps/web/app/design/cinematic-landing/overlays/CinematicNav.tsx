"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { useReducedMotion as useSystemReducedMotion } from "framer-motion";
import { SCENES } from "../sceneConfig";
import { useActiveSceneIndex } from "../useActiveSceneIndex";
import { useVisibleSceneId } from "../useVisibleSceneId";
import { useMotionActive } from "../MotionActiveContext";
import { useReducedMotionOverrideControl } from "../../landing-experience/useEffectiveReducedMotion";

/**
 * Minimal nav (mission §24/§35) — the navigation-safe NOOR symbol
 * combined with a real text wordmark (mission §3.9/§24: "the tiny
 * detailed logo" complaint, fixed by pairing the symbol with legible
 * text rather than relying on the image alone at a larger size), a
 * scene-progress indicator, sign in, and a "Reduce motion" control
 * that only ever offers to go *further* than the OS preference
 * (mission §29 — never overrides the OS default by default, and is
 * hidden entirely when the OS already requests reduced motion, since
 * there's nothing left for it to offer).
 *
 * Reads `useActiveSceneIndex()` (re-renders only when the scene
 * actually changes), not the full per-frame timeline state — the
 * scene-progress dots don't need every scroll-frame's progress value,
 * and subscribing to it would re-render this nav up to 60×/sec while
 * scrolling (mission §10/§26 "React state only for coarse scene
 * changes").
 *
 * In reduced-motion mode, `timelineStore.sceneIndex` never advances
 * (the GSAP ScrollTrigger it depends on is never created), so the
 * dots and the `aria-live` scene announcement would stay stuck
 * announcing "Scene 1" forever regardless of real scroll position — a
 * real accessibility inaccuracy caught by comparing a screenshot's
 * dots against its own visibly-correct static illustration (which
 * uses the separate `useVisibleSceneId` IntersectionObserver signal).
 * Falls back to that same signal here whenever motion is inactive.
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
  const timelineSceneIndex = useActiveSceneIndex();
  const visibleSceneId = useVisibleSceneId(SCENES.length);
  const motionActive = useMotionActive();
  const sceneIndex = motionActive ? timelineSceneIndex : visibleSceneId - 1;
  const systemReducedMotion = useSystemReducedMotion();
  const { override, setOverride } = useReducedMotionOverrideControl();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <nav
      className="pointer-events-none fixed inset-x-0 top-0 z-30 flex items-center justify-between px-lg py-md sm:px-xl"
      style={{ paddingTop: "max(env(safe-area-inset-top), 1rem)" }}
    >
      <Link
        href="/"
        className="pointer-events-auto inline-flex items-center gap-xs rounded-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        aria-label="Noor home"
      >
        <Image src="/brand/noor-logo-navigation.png" alt="" width={121} height={100} className="h-9 w-auto sm:h-10" priority />
        <span className="hidden flex-col leading-none sm:flex">
          <span className="text-sm font-semibold tracking-wide text-white">NOOR</span>
          <span className="text-[10px] uppercase tracking-[0.14em] text-white/55">Clinical Intelligence OS</span>
        </span>
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
          <label className="hidden items-center gap-xs text-xs text-white/80 sm:flex">
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
