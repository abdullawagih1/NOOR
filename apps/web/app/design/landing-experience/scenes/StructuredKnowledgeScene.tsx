"use client";

import { motion } from "framer-motion";
import { FileText } from "lucide-react";
import { useState } from "react";
import { PrototypeFrame } from "../PrototypeFrame";
import { useEffectiveReducedMotion } from "../useEffectiveReducedMotion";
import { useStepSequence } from "../useStepSequence";

const REGIONS = [
  { id: "chunk-1", label: "Chunk 1", source: "Page 4, chars 0–340", text: "Screening criteria for adult patients presenting with…" },
  { id: "chunk-2", label: "Chunk 2", source: "Page 4, chars 341–812", text: "Recommended assessment interval following initial…" },
] as const;

// Step 0 = nothing highlighted. Steps alternate: highlight region N, then connect chunk N.
const STEPS = [
  "Page shown, no spans highlighted",
  "Span 1 highlighted",
  "Chunk 1 formed — provenance line connects it to span 1",
  "Span 2 highlighted",
  "Chunk 2 formed — provenance line connects it to span 2",
] as const;

/**
 * Scene 4 (mission §22.4) — structured knowledge. Narrative: structure is
 * derived from the page and never disconnected from it. The connector
 * line between a highlighted span and its chunk is the whole point —
 * chunks never render as disconnected floating cards.
 */
export function StructuredKnowledgeScene() {
  const reducedMotion = useEffectiveReducedMotion();
  const [playing, setPlaying] = useState(false);
  const [resetSignal, setResetSignal] = useState(0);
  const [step, setStep] = useStepSequence(playing, STEPS.length, resetSignal, 900);

  const effectiveStep = reducedMotion ? STEPS.length - 1 : step;

  return (
    <PrototypeFrame
      id="structured-knowledge"
      title="4. Structured Knowledge"
      narrativeMeaning="Reviewed pages become provenance-preserving knowledge — each chunk keeps a visible line back to the exact page region it came from. Chunks never appear as disconnected floating cards."
      implementation="Framer Motion"
      performanceNotes="SVG pathLength animation, one path per region; transform/opacity for the rest."
      stepLabel={STEPS[effectiveStep]}
      stepIndex={effectiveStep}
      stepCount={STEPS.length}
      playing={playing}
      onPlayingChange={setPlaying}
      onReset={() => {
        setPlaying(false);
        setResetSignal((value) => value + 1);
      }}
    >
      <div className="flex flex-col gap-sm">
        {REGIONS.map((region, index) => {
          const regionHighlightStep = index * 2 + 1;
          const chunkFormedStep = index * 2 + 2;
          const spanHighlighted = effectiveStep >= regionHighlightStep;
          const chunkFormed = effectiveStep >= chunkFormedStep;

          return (
            <div key={region.id} className="flex items-center gap-sm">
              <motion.div
                initial={false}
                animate={{
                  borderColor: spanHighlighted ? "var(--noor-color-accent)" : "var(--noor-color-border)",
                  backgroundColor: spanHighlighted ? "var(--noor-color-accent-soft)" : "var(--noor-color-canvas)",
                }}
                transition={reducedMotion ? { duration: 0 } : { duration: 0.26 }}
                className="flex flex-1 items-start gap-xs rounded-sm border p-md"
              >
                <FileText size={16} className="mt-xxs flex-none text-muted" aria-hidden="true" />
                <p className="text-sm text-body">{region.text}</p>
              </motion.div>

              <svg width="40" height="24" viewBox="0 0 40 24" aria-hidden="true" className="flex-none">
                <motion.line
                  x1="2"
                  y1="12"
                  x2="38"
                  y2="12"
                  stroke="var(--noor-color-accent)"
                  strokeWidth="2"
                  initial={false}
                  animate={{ pathLength: chunkFormed ? 1 : 0, opacity: chunkFormed ? 1 : 0 }}
                  transition={reducedMotion ? { duration: 0 } : { duration: 0.32 }}
                />
              </svg>

              {/*
                Scale (not opacity) conveys the "not yet formed" state —
                fading the chunk label/checksum text via opacity
                previously failed WCAG contrast (as low as 1.36:1
                against a 4.5:1 requirement), caught by
                @axe-core/playwright. Text stays at full, token-checked
                contrast in every state.
              */}
              <motion.div
                initial={false}
                animate={{ scale: chunkFormed ? 1 : 0.96 }}
                transition={reducedMotion ? { duration: 0 } : { duration: 0.26 }}
                className="flex flex-1 flex-col gap-xxs rounded-sm border border-border p-md"
                style={{
                  backgroundColor: chunkFormed ? "var(--noor-color-surface-soft)" : "var(--noor-color-canvas)",
                }}
              >
                <span className="text-xs font-semibold text-ink">{region.label}</span>
                <span className="font-mono text-xs text-muted" style={{ direction: "ltr" }}>
                  {region.source}
                </span>
              </motion.div>
            </div>
          );
        })}
      </div>
    </PrototypeFrame>
  );
}
