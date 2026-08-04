"use client";

import { useEffect, useRef } from "react";
import { EvidenceCoreScene } from "./EvidenceCore/EvidenceCoreScene";
import type { QualityTier } from "./useQualityTier";

export interface CinematicCanvasProps {
  qualityTier: QualityTier;
  onContextLost: () => void;
}

/**
 * The single Three.js canvas for the whole route (mission §7/§33) — a
 * plain <canvas> owned by a ref, with its own requestAnimationFrame
 * loop, never @react-three/fiber. See docs/landing/
 * NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md §"Why raw Three.js" for the
 * real, documented, upstream @react-three/fiber v8 + Next.js 15
 * incompatibility this avoids entirely — imperative Three.js has no
 * react-reconciler dependency, so the bug class this route hit cannot
 * occur here. Imported only via next/dynamic from
 * CinematicExperience.tsx, never from a shared layout, so `three`
 * never reaches any other route's bundle.
 */
export function CinematicCanvas({ qualityTier, onContextLost }: CinematicCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sceneRef = useRef<EvidenceCoreScene | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const container = canvas?.parentElement;
    if (!canvas || !container) return;

    let scene: EvidenceCoreScene;
    try {
      scene = new EvidenceCoreScene(canvas, qualityTier);
    } catch (error) {
      if (process.env.NODE_ENV !== "production") {
        console.warn("[cinematic-landing] EvidenceCoreScene construction failed:", error);
      }
      onContextLost();
      return;
    }
    sceneRef.current = scene;

    const handleContextLost = (event: Event) => {
      event.preventDefault();
      onContextLost();
    };
    canvas.addEventListener("webglcontextlost", handleContextLost, false);

    scene.resize(container.clientWidth, container.clientHeight);
    const resizeObserver = new ResizeObserver(() => {
      scene.resize(container.clientWidth, container.clientHeight);
    });
    resizeObserver.observe(container);

    let rafId = 0;
    let lastTime = performance.now();
    const loop = (time: number) => {
      const deltaSeconds = Math.min(0.1, (time - lastTime) / 1000);
      lastTime = time;
      scene.update(deltaSeconds);
      rafId = requestAnimationFrame(loop);
    };
    rafId = requestAnimationFrame(loop);

    return () => {
      cancelAnimationFrame(rafId);
      resizeObserver.disconnect();
      canvas.removeEventListener("webglcontextlost", handleContextLost, false);
      scene.dispose();
      sceneRef.current = null;
    };
    // qualityTier changes are applied via the effect below, not by
    // re-running this whole setup effect (which would recreate the
    // WebGL context unnecessarily).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onContextLost]);

  useEffect(() => {
    sceneRef.current?.setQualityTier(qualityTier);
  }, [qualityTier]);

  return <canvas ref={canvasRef} className="h-full w-full" aria-hidden="true" />;
}
