"use client";

import { useEffect, useState } from "react";
import { MOBILE_BREAKPOINT_PX } from "./sceneConfig";

export type QualityTier = "high" | "balanced" | "static";

interface NavigatorWithCapabilityHints extends Navigator {
  deviceMemory?: number;
}

/**
 * Coarse, non-fingerprinting device-capability tiering (mission §30) —
 * viewport width, hardwareConcurrency/deviceMemory where the browser
 * exposes them, and a short FPS probe once the canvas actually mounts.
 * Never used to identify a specific user, only to pick a rendering
 * budget.
 */
export function useInitialQualityTier(): QualityTier {
  const [tier, setTier] = useState<QualityTier>("balanced");

  useEffect(() => {
    if (typeof window === "undefined") return;

    const nav = navigator as NavigatorWithCapabilityHints;
    const isMobileViewport = window.innerWidth < MOBILE_BREAKPOINT_PX;
    const lowConcurrency = typeof nav.hardwareConcurrency === "number" && nav.hardwareConcurrency <= 4;
    const lowMemory = typeof nav.deviceMemory === "number" && nav.deviceMemory <= 4;

    if (isMobileViewport || lowConcurrency || lowMemory) {
      setTier("balanced");
    } else {
      setTier("high");
    }
  }, []);

  return tier;
}

/**
 * Runs a short requestAnimationFrame probe and reports the average FPS
 * over `sampleFrames` frames. Used once, right after the canvas mounts,
 * to decide whether to downgrade the initial tier — never re-run
 * continuously (that would itself cost performance).
 */
export function probeFrameRate(sampleFrames: number, onDone: (averageFps: number) => void): () => void {
  let frameCount = 0;
  let startTime = 0;
  let rafId = 0;
  let cancelled = false;

  const step = (time: number) => {
    if (cancelled) return;
    if (startTime === 0) startTime = time;
    frameCount += 1;
    if (frameCount >= sampleFrames) {
      const elapsedSeconds = (time - startTime) / 1000;
      onDone(elapsedSeconds > 0 ? frameCount / elapsedSeconds : 60);
      return;
    }
    rafId = requestAnimationFrame(step);
  };
  rafId = requestAnimationFrame(step);

  return () => {
    cancelled = true;
    cancelAnimationFrame(rafId);
  };
}
