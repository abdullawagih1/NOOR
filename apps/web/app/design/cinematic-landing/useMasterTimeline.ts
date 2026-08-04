"use client";

import { useEffect, useRef } from "react";
import { SCENES, findSceneIndex, sceneLocalProgress } from "./sceneConfig";
import { setTimelineState, resetTimelineState } from "./timelineStore";

interface ScrollTriggerInstance {
  kill: () => void;
}

/**
 * The one master timeline (mission §11/§22): a single ScrollTrigger
 * bound to the real content wrapper's own natural height in the
 * page's normal document scroll — never a nested scroller, never
 * scroll-hijacked, never an artificial empty spacer. `end: "bottom
 * bottom"` means progress 0..1 maps exactly to the wrapper scrolling
 * from its top to its bottom, so the 7 real, accessible <section>
 * elements (sized in vh proportional to their scene fraction) are
 * what actually defines scroll distance.
 */
export function useMasterTimeline(active: boolean, contentRef: React.RefObject<HTMLDivElement>) {
  const triggerRef = useRef<ScrollTriggerInstance | null>(null);

  useEffect(() => {
    if (!active) return;
    const content = contentRef.current;
    if (!content) return;

    let killed = false;

    Promise.all([import("gsap"), import("gsap/ScrollTrigger")]).then(([gsapModule, scrollTriggerModule]) => {
      if (killed) return;
      const gsap = gsapModule.default;
      const ScrollTrigger = scrollTriggerModule.ScrollTrigger;
      gsap.registerPlugin(ScrollTrigger);

      const instance = ScrollTrigger.create({
        trigger: content,
        start: "top top",
        end: "bottom bottom",
        scrub: 0.5,
        onUpdate: (self: { progress: number }) => {
          const progress = self.progress;
          const sceneIndex = findSceneIndex(progress);
          setTimelineState({
            progress,
            sceneIndex,
            sceneLocalProgress: sceneLocalProgress(progress, SCENES[sceneIndex]),
          });
        },
      });
      triggerRef.current = instance;
      // Recalculates trigger start/end after fonts/layout settle and on resize —
      // ScrollTrigger.refresh() is idempotent and cheap.
      window.addEventListener("resize", () => ScrollTrigger.refresh());
    });

    return () => {
      killed = true;
      triggerRef.current?.kill();
      triggerRef.current = null;
      resetTimelineState();
    };
  }, [active, contentRef]);
}
