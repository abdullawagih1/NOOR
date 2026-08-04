"use client";

import { useEffect, useState } from "react";

/**
 * Which scene's real, server-rendered `<section id="scene-N">` is
 * currently most visible — the reduced-motion/static-fallback
 * equivalent of the GSAP-driven timeline (mission §23: "no scrub
 * timeline" in that path, so this uses a plain IntersectionObserver on
 * native scroll instead, never GSAP). `useMasterTimeline` only creates
 * a ScrollTrigger when motion is active, so `timelineStore` never
 * advances in the static path — this hook is how `StaticPoster` still
 * knows which scene's illustration to show as the user scrolls.
 */
export function useVisibleSceneId(sceneCount: number): number {
  const [visibleId, setVisibleId] = useState(1);

  useEffect(() => {
    const sections = Array.from(document.querySelectorAll('section[id^="scene-"]')) as HTMLElement[];
    if (sections.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        let best: { id: number; ratio: number } | null = null;
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const id = Number(entry.target.id.replace("scene-", ""));
          if (!Number.isFinite(id)) continue;
          if (!best || entry.intersectionRatio > best.ratio) best = { id, ratio: entry.intersectionRatio };
        }
        if (best) setVisibleId(best.id);
      },
      { threshold: [0.25, 0.5, 0.75] }
    );
    sections.forEach((section) => observer.observe(section));
    return () => observer.disconnect();
  }, [sceneCount]);

  return visibleId;
}
