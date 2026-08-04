"use client";

import { forwardRef, useImperativeHandle, useRef } from "react";
import type { ScreenAnchor } from "./EvidenceCore/EvidenceCoreScene";

export interface AnchorLabelsHandle {
  setAnchors: (anchors: Record<string, ScreenAnchor>, traceabilityLabel?: string) => void;
}

const RANK_LABELS = ["1", "2", "3"];

/**
 * DOM rank-number badges and the reverse-traceability layer label
 * (mission §15 "Visible rank numbers: 1, 2, 3" / §17 "every layer
 * readable without relying on body copy"), positioned via
 * `Vector3.project(camera)` and written directly to these ref'd nodes
 * every frame — no React state, no per-frame re-render (mission §26
 * "DOM anchors" guidance).
 */
export const AnchorLabels = forwardRef<AnchorLabelsHandle>(function AnchorLabels(_props, ref) {
  const elRefs = useRef<Record<string, HTMLDivElement | null>>({});

  useImperativeHandle(ref, () => ({
    setAnchors(anchors, traceabilityLabel) {
      for (const [key, anchor] of Object.entries(anchors)) {
        const el = elRefs.current[key];
        if (!el) continue;
        el.style.left = `${anchor.x}%`;
        el.style.top = `${anchor.y}%`;
        el.style.opacity = anchor.visible ? "1" : "0";
      }
      const labelEl = elRefs.current["traceability-label"];
      if (labelEl && traceabilityLabel !== undefined && labelEl.textContent !== traceabilityLabel) {
        labelEl.textContent = traceabilityLabel;
      }
    },
  }));

  return (
    <div className="pointer-events-none absolute inset-0 z-20 overflow-hidden" aria-hidden="true">
      {RANK_LABELS.map((label, index) => (
        <div
          key={label}
          ref={(el) => {
            elRefs.current[`rank-${index + 1}`] = el;
          }}
          className="absolute flex h-7 w-7 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-pill border border-white/30 bg-[#050F1E]/70 text-xs font-semibold text-white opacity-0 transition-opacity duration-200"
          style={{ left: "50%", top: "50%" }}
        >
          {label}
        </div>
      ))}
      <div
        ref={(el) => {
          elRefs.current["traceability-label"] = el;
        }}
        className="absolute -translate-x-1/2 -translate-y-[calc(100%+14px)] whitespace-nowrap rounded-pill border border-[#2FE8B8]/50 bg-[#050F1E]/80 px-sm py-xxs text-xs font-medium text-[#8FF0DA] opacity-0 transition-opacity duration-200"
        style={{ left: "50%", top: "50%" }}
      />
    </div>
  );
});
