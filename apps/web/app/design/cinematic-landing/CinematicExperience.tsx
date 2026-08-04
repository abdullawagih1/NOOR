"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import dynamic from "next/dynamic";
import { useSearchParams } from "next/navigation";
import { useMasterTimeline } from "./useMasterTimeline";
import { useInitialQualityTier, probeFrameRate, type QualityTier } from "./useQualityTier";
import { useEffectiveReducedMotion } from "../landing-experience/useEffectiveReducedMotion";
import { isWebglAvailable } from "./webglSupport";
import { CanvasErrorBoundary } from "./CanvasErrorBoundary";
import { CinematicNav } from "./overlays/CinematicNav";
import { DebugOverlay } from "./DebugOverlay";
import { StaticPoster } from "./StaticPoster";
import { MotionActiveProvider } from "./MotionActiveContext";
import type { PublicLandingCta } from "@/lib/publicLanding/PublicLandingCta";

const CinematicCanvas = dynamic(() => import("./CinematicCanvas").then((mod) => mod.CinematicCanvas), {
  ssr: false,
  loading: () => null,
});

export interface CinematicExperienceProps {
  children: ReactNode;
  cta: PublicLandingCta;
}

/**
 * Owns the motion-vs-static decision (mission §30) and the fixed
 * background layer. `children` is the real, server-rendered, fully
 * accessible content passed down from page.tsx — this component never
 * duplicates or replaces it, only decides what renders behind it.
 */
export function CinematicExperience({ children, cta }: CinematicExperienceProps) {
  const contentRef = useRef<HTMLDivElement>(null);
  const reducedMotion = useEffectiveReducedMotion();
  const initialTier = useInitialQualityTier();
  const [tier, setTier] = useState<QualityTier>(initialTier);
  const [webglOk, setWebglOk] = useState(true);
  const [canvasFailed, setCanvasFailed] = useState(false);
  const [probed, setProbed] = useState(false);
  // `reducedMotion` is a client-only media-query read (Framer's
  // useReducedMotion resolves it synchronously on the very first
  // client render, before any effect runs) while the server always
  // renders as if motion is enabled. Branching on it immediately
  // produced a real hydration mismatch (caught via Next's dev overlay
  // + a real hydration error, not inspection) whenever a visitor's OS
  // actually requests reduced motion — the server rendered the canvas
  // branch, the client's first paint rendered the static branch.
  // `mounted` defers the switch until after hydration, matching the
  // server's first-paint output exactly (same fix as CinematicNav's
  // reduced-motion toggle).
  const [mounted, setMounted] = useState(false);
  const searchParams = useSearchParams();
  const debug = searchParams.get("debug") === "1" && process.env.NODE_ENV !== "production";

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    setTier(initialTier);
  }, [initialTier]);

  useEffect(() => {
    setWebglOk(isWebglAvailable());
  }, []);

  const effectiveReducedMotion = mounted && reducedMotion;
  const motionActive = !effectiveReducedMotion && webglOk && tier !== "static" && !canvasFailed;

  useMasterTimeline(motionActive, contentRef);

  useEffect(() => {
    if (!motionActive || probed) return;
    return probeFrameRate(60, (averageFps) => {
      setProbed(true);
      if (tier === "high" && averageFps < 50) {
        setTier("balanced");
      } else if (tier === "balanced" && averageFps < 30) {
        setTier("static");
      }
    });
  }, [motionActive, probed, tier]);

  return (
    <div className="relative bg-[#040F1C]">
      <CinematicNav cta={cta} />

      {/*
        Mobile (mission §22): the visual object lives in its own fixed
        top band (46vh), never full-screen — the concrete fix for the
        rejected "canvas competing with text" defect. page.tsx pushes
        every scene's copy below this band with matching top padding,
        so the two zones never overlap regardless of scroll position.
        Desktop/tablet keep the original full-viewport treatment.
      */}
      <div className="fixed inset-x-0 top-0 z-0 h-[46vh] sm:inset-0 sm:h-auto" aria-hidden="true">
        {motionActive ? (
          <CanvasErrorBoundary fallback={<StaticPoster />}>
            <CinematicCanvas qualityTier={tier} onContextLost={() => setCanvasFailed(true)} />
          </CanvasErrorBoundary>
        ) : (
          <StaticPoster />
        )}
      </div>

      <div ref={contentRef} className="relative z-10">
        <MotionActiveProvider value={motionActive}>{children}</MotionActiveProvider>
      </div>

      {debug ? <DebugOverlay tier={tier} motionActive={motionActive} webglOk={webglOk} reducedMotion={reducedMotion} /> : null}
    </div>
  );
}
