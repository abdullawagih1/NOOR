"use client";

import { useEffect, useRef, useState } from "react";
import { Badge } from "@noor/ui";
import { PrototypeFrame } from "../PrototypeFrame";
import { useEffectiveReducedMotion } from "../useEffectiveReducedMotion";

const STAGES = [
  {
    label: "Intelligence statement",
    status: "Illustrative — product vision",
    title: "“Initial assessment should occur within 2 weeks of diagnosis.”",
    body: "A future, labeled illustrative claim — claim generation does not exist yet.",
  },
  {
    label: "Supporting evidence",
    status: "Available",
    title: "Evidence: Hypertension Management Guideline, relevance 0.91",
    body: "The evaluation framework's top-ranked candidate for this claim.",
  },
  {
    label: "Retrieved chunk",
    status: "Available",
    title: "Chunk 1 — “Initial assessment should occur within…”",
    body: "A deterministic, checksum-bound chunk from S1-D3.",
  },
  {
    label: "Exact source span",
    status: "Available",
    title: "Page 4, characters 210–340",
    body: "The exact span the chunk was derived from, preserved verbatim.",
  },
  {
    label: "Original guideline",
    status: "Available",
    title: "Hypertension Management Guideline v3 — Approved",
    body: "The registered, versioned source this entire chain began with.",
  },
] as const;

const SCROLL_RANGE_PX = 1600;

/**
 * Scene 6 (mission §22.6) — reverse traceability, the landing's
 * signature scene. Desktop: a real GSAP + ScrollTrigger scrub-linked
 * sequence inside a self-contained scroller (so it never hijacks the
 * page's own scroll). Reduced-motion and mobile share one static,
 * manually-advanced fallback with no pinning and no scrubbing —
 * identical content, identical order, nothing hidden.
 */
const DESKTOP_MIN_WIDTH = 768;

export function TraceabilityTimelineScene() {
  const reducedMotion = useEffectiveReducedMotion();
  const [playing, setPlaying] = useState(false);
  const [manualStage, setManualStage] = useState(0);
  const [scrubProgress, setScrubProgress] = useState(0);
  // Mission §24/§25: mobile never gets the pinned/scrubbed version,
  // regardless of the reduced-motion preference — this is a genuinely
  // separate gate, not implied by reducedMotion alone (confirmed via a
  // real axe-core/playwright scan at 390px catching a scrollable-region-
  // focusable violation on the desktop-only scroller before this check
  // existed).
  const [isDesktopViewport, setIsDesktopViewport] = useState(true);
  const containerRef = useRef<HTMLDivElement>(null);
  const scrollTriggerRef = useRef<{ kill: () => void } | null>(null);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    const query = window.matchMedia(`(min-width: ${DESKTOP_MIN_WIDTH}px)`);
    setIsDesktopViewport(query.matches);
    const listener = (event: MediaQueryListEvent) => setIsDesktopViewport(event.matches);
    query.addEventListener("change", listener);
    return () => query.removeEventListener("change", listener);
  }, []);

  const useStaticFallback = reducedMotion || !isDesktopViewport;

  const activeStage = useStaticFallback
    ? manualStage
    : Math.min(STAGES.length - 1, Math.floor(scrubProgress * STAGES.length));

  // Real GSAP + ScrollTrigger wiring, desktop / motion-enabled only.
  // Dynamically imported so reduced-motion and mobile visitors never
  // download it (Technical Architecture §Dynamic imports).
  useEffect(() => {
    if (useStaticFallback) return;
    const container = containerRef.current;
    if (!container) return;

    let killed = false;
    let triggerInstance: { kill: () => void } | null = null;

    Promise.all([import("gsap"), import("gsap/ScrollTrigger")]).then(([gsapModule, scrollTriggerModule]) => {
      if (killed) return;
      const gsap = gsapModule.default;
      const ScrollTrigger = scrollTriggerModule.ScrollTrigger;
      gsap.registerPlugin(ScrollTrigger);

      triggerInstance = ScrollTrigger.create({
        trigger: container,
        scroller: container,
        start: "top top",
        end: `+=${SCROLL_RANGE_PX}`,
        scrub: 0.5,
        onUpdate: (self: { progress: number }) => setScrubProgress(self.progress),
      });
      scrollTriggerRef.current = triggerInstance;
    });

    return () => {
      killed = true;
      triggerInstance?.kill();
      scrollTriggerRef.current = null;
    };
  }, [useStaticFallback]);

  const stopAutoScroll = () => {
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
  };

  const handlePlayingChange = (next: boolean) => {
    setPlaying(next);
    if (useStaticFallback) return;
    const container = containerRef.current;
    if (!container) return;

    if (!next) {
      stopAutoScroll();
      return;
    }

    const durationMs = 3200;
    const startScrollTop = container.scrollTop;
    const maxScrollTop = container.scrollHeight - container.clientHeight;
    const startTime = performance.now();

    const step = (now: number) => {
      const elapsed = now - startTime;
      const t = Math.min(1, elapsed / durationMs);
      container.scrollTop = startScrollTop + (maxScrollTop - startScrollTop) * t;
      if (t < 1) {
        rafRef.current = requestAnimationFrame(step);
      } else {
        setPlaying(false);
        rafRef.current = null;
      }
    };
    rafRef.current = requestAnimationFrame(step);
  };

  const handleReset = () => {
    setPlaying(false);
    stopAutoScroll();
    setManualStage(0);
    if (containerRef.current) containerRef.current.scrollTop = 0;
    setScrubProgress(0);
  };

  useEffect(() => stopAutoScroll, []);

  return (
    <PrototypeFrame
      id="reverse-traceability"
      title="6. Reverse Traceability (Signature Scene)"
      narrativeMeaning="NOOR's product signature: starting from a claim and walking it back to its evidence, chunk, exact source span, page, and original guideline — proving nothing is lost between an intelligence-layer statement and its source."
      implementation={useStaticFallback ? "CSS / SVG" : "GSAP + ScrollTrigger"}
      performanceNotes="Isolated, dynamically imported (gsap + ScrollTrigger loaded only when motion is enabled). Highest performance risk on the page — measured independently in the verification report."
      stepLabel={STAGES[activeStage].label}
      stepIndex={activeStage}
      stepCount={STAGES.length}
      playing={playing}
      onPlayingChange={handlePlayingChange}
      onReset={handleReset}
    >
      {/* Breadcrumb — every prior stage stays visible (dimmed), never removed. */}
      <ol className="mb-sm flex flex-wrap items-center gap-xs" aria-label="Traceability breadcrumb">
        {STAGES.map((stage, index) => (
          <li key={stage.label} className="flex items-center gap-xs">
            <span
              className="rounded-pill px-sm py-xxs text-xs font-medium"
              style={{
                color: index <= activeStage ? "var(--noor-color-accent-active)" : "var(--noor-color-muted)",
                backgroundColor: index === activeStage ? "var(--noor-color-accent-soft)" : "transparent",
              }}
            >
              {stage.label}
            </span>
            {index < STAGES.length - 1 ? <span aria-hidden="true" className="text-muted">&rarr;</span> : null}
          </li>
        ))}
      </ol>

      {useStaticFallback ? (
        <div className="flex flex-col gap-sm">
          {STAGES.map((stage, index) => (
            <div
              key={stage.label}
              className="flex flex-col gap-xxs rounded-sm border p-md"
              style={{
                borderColor: index === activeStage ? "var(--noor-color-accent)" : "var(--noor-color-border)",
                backgroundColor: index === activeStage ? "var(--noor-color-accent-soft)" : "var(--noor-color-canvas)",
              }}
            >
              <Badge>{stage.status}</Badge>
              <p className="text-sm font-medium text-ink">{stage.title}</p>
              {/* text-body, not text-muted: this card's background can
                  become accent-soft (teal-100) when active, and
                  text-muted only clears 4.31:1 against it — a real
                  WCAG AA failure caught by @axe-core/playwright. */}
              <p className="text-xs text-body">{stage.body}</p>
            </div>
          ))}
          <div className="flex items-center gap-sm">
            <button
              type="button"
              className="rounded-sm border border-border-strong px-md py-xs text-sm text-ink hover:bg-surface-soft disabled:opacity-50"
              onClick={() => setManualStage((value) => Math.max(0, value - 1))}
              disabled={activeStage === 0}
              data-testid="traceability-prev"
            >
              Previous stage
            </button>
            <button
              type="button"
              className="rounded-sm bg-primary px-md py-xs text-sm text-on-primary hover:bg-primary-active disabled:opacity-50"
              onClick={() => setManualStage((value) => Math.min(STAGES.length - 1, value + 1))}
              disabled={activeStage === STAGES.length - 1}
              data-testid="traceability-next"
            >
              Next stage
            </button>
          </div>
        </div>
      ) : (
        <div
          ref={containerRef}
          className="relative h-[280px] overflow-y-auto rounded-sm border border-border"
          data-testid="traceability-scroller"
          tabIndex={0}
          role="region"
          aria-label="Reverse traceability scroll timeline — scroll within this region to move through the 5 stages"
        >
          <div style={{ height: SCROLL_RANGE_PX + 280 }}>
            <div className="sticky top-0 flex h-[280px] flex-col justify-center gap-xs border-b border-border bg-canvas p-lg">
              <Badge>{STAGES[activeStage].status}</Badge>
              <p className="text-base font-medium text-ink">{STAGES[activeStage].title}</p>
              <p className="text-sm text-muted">{STAGES[activeStage].body}</p>
              <p className="text-xs text-muted" aria-hidden="true">
                Scroll within this frame to scrub the timeline ({Math.round(scrubProgress * 100)}%)
              </p>
            </div>
          </div>
        </div>
      )}
    </PrototypeFrame>
  );
}
