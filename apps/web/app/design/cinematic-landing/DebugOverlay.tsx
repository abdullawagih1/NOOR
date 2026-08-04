"use client";

import { useEffect, useState } from "react";
import { SCENES } from "./sceneConfig";
import { useTimelineState } from "./useTimelineState";
import type { QualityTier } from "./useQualityTier";

export interface DebugOverlayProps {
  tier: QualityTier;
  motionActive: boolean;
  webglOk: boolean;
  reducedMotion: boolean;
}

/**
 * `?debug=1`-only readout (mission §36) — never rendered in
 * production (the parent gates on NODE_ENV already), no secrets, no
 * link from the normal experience.
 */
export function DebugOverlay({ tier, motionActive, webglOk, reducedMotion }: DebugOverlayProps) {
  const { progress, sceneIndex, sceneLocalProgress } = useTimelineState();
  const [fps, setFps] = useState(0);

  useEffect(() => {
    let frames = 0;
    let last = performance.now();
    let raf = 0;
    const tick = (time: number) => {
      frames += 1;
      if (time - last >= 500) {
        setFps(Math.round((frames * 1000) / (time - last)));
        frames = 0;
        last = time;
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  const scene = SCENES[sceneIndex];

  return (
    <div
      className="fixed bottom-4 right-4 z-50 w-72 rounded-sm border border-white/20 bg-black/80 p-sm font-mono text-xs text-white"
      data-testid="cinematic-debug-overlay"
    >
      <div>scene: {scene.id} — {scene.key}</div>
      <div>progress: {progress.toFixed(3)}</div>
      <div>sceneLocalProgress: {sceneLocalProgress.toFixed(3)}</div>
      <div>fps: {fps}</div>
      <div>qualityTier: {tier}</div>
      <div>motionActive: {String(motionActive)}</div>
      <div>webglOk: {String(webglOk)}</div>
      <div>reducedMotion: {String(reducedMotion)}</div>
    </div>
  );
}
