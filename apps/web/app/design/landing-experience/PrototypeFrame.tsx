"use client";

import { useState, type ReactNode } from "react";
import { Button, Badge } from "@noor/ui";
import { useReducedMotionOverrideControl } from "./useEffectiveReducedMotion";

export type PrototypeImplementation = "Framer Motion" | "GSAP + ScrollTrigger" | "CSS / SVG";

export interface PrototypeFrameProps {
  id: string;
  title: string;
  narrativeMeaning: string;
  implementation: PrototypeImplementation;
  performanceNotes: string;
  stepLabel: string;
  stepIndex: number;
  stepCount: number;
  playing: boolean;
  onPlayingChange: (playing: boolean) => void;
  onReset: () => void;
  children: ReactNode;
}

/**
 * Review-only chrome around every prototype scene (mission §21). None of
 * these controls — play/pause/reset, viewport switch, reduced-motion
 * override, implementation label — ship to the production landing page;
 * they exist so a reviewer can inspect each technical prototype in
 * isolation before LX-1.1 approval.
 */
export function PrototypeFrame({
  id,
  title,
  narrativeMeaning,
  implementation,
  performanceNotes,
  stepLabel,
  stepIndex,
  stepCount,
  playing,
  onPlayingChange,
  onReset,
  children,
}: PrototypeFrameProps) {
  const [viewport, setViewport] = useState<"desktop" | "mobile">("desktop");
  const { override, setOverride } = useReducedMotionOverrideControl();

  return (
    <section
      id={id}
      aria-labelledby={`${id}-heading`}
      className="flex flex-col gap-md rounded-md border border-border bg-canvas p-lg shadow-card"
      data-testid={`prototype-${id}`}
    >
      <div className="flex flex-col gap-xxs">
        <div className="flex flex-wrap items-center gap-xs">
          <h2 id={`${id}-heading`} className="text-lg font-semibold text-ink">
            {title}
          </h2>
          <Badge>{implementation}</Badge>
        </div>
        <p className="text-sm text-muted">{narrativeMeaning}</p>
        <p className="text-xs text-muted">Performance notes: {performanceNotes}</p>
      </div>

      <div className="flex flex-wrap items-center gap-sm border-y border-border py-sm">
        <Button
          type="button"
          size="sm"
          variant={playing ? "secondary" : "primary"}
          onClick={() => onPlayingChange(!playing)}
          data-testid={`${id}-play-pause`}
        >
          {playing ? "Pause" : "Play"}
        </Button>
        <Button type="button" size="sm" variant="secondary" onClick={onReset} data-testid={`${id}-reset`}>
          Reset
        </Button>

        <div className="ml-auto flex items-center gap-xs" role="group" aria-label="Viewport preview width">
          <Button
            type="button"
            size="sm"
            variant={viewport === "desktop" ? "primary" : "secondary"}
            onClick={() => setViewport("desktop")}
            data-testid={`${id}-viewport-desktop`}
          >
            Desktop
          </Button>
          <Button
            type="button"
            size="sm"
            variant={viewport === "mobile" ? "primary" : "secondary"}
            onClick={() => setViewport("mobile")}
            data-testid={`${id}-viewport-mobile`}
          >
            Mobile
          </Button>
        </div>

        <label className="flex items-center gap-xs text-sm text-body">
          <input
            type="checkbox"
            checked={override === true}
            onChange={(event) => setOverride(event.target.checked ? true : null)}
            data-testid={`${id}-reduced-motion-toggle`}
          />
          Reduced-motion preview
        </label>
      </div>

      <div className="flex items-center gap-sm text-xs text-muted" data-testid={`${id}-progress`}>
        <span aria-live="polite">
          Step {stepIndex + 1} of {stepCount}: {stepLabel}
        </span>
      </div>

      <div
        className="overflow-x-auto rounded-sm border border-border bg-surface-soft p-md"
        style={{ maxWidth: viewport === "mobile" ? 390 : undefined }}
        data-testid={`${id}-stage`}
        // Content can legitimately overflow and become horizontally
        // scrollable at narrow widths (a real @axe-core/playwright
        // scrollable-region-focusable violation was caught here at
        // 390px on the Structured Knowledge scene) — tabIndex makes the
        // scrollable region itself keyboard-reachable, matching the
        // fix already applied to the traceability scene's own scroller.
        tabIndex={0}
        role="group"
        aria-label={`${title} — stage area`}
      >
        {children}
      </div>
    </section>
  );
}
