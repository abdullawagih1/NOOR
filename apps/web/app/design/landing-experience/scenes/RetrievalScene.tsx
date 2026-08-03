"use client";

import { motion } from "framer-motion";
import { MapPin, Search } from "lucide-react";
import { useState } from "react";
import { Badge } from "@noor/ui";
import { PrototypeFrame } from "../PrototypeFrame";
import { useEffectiveReducedMotion } from "../useEffectiveReducedMotion";
import { useStepSequence } from "../useStepSequence";

const CANDIDATES = [
  { label: "Candidate A", relevance: 0.91, source: "Guideline — Hypertension Management, p. 4" },
  { label: "Candidate B", relevance: 0.78, source: "Guideline — Hypertension Management, p. 7" },
  { label: "Candidate C", relevance: 0.64, source: "Guideline — Cardiovascular Risk, p. 2" },
] as const;

const STEPS = [
  "Synthetic query entered",
  "Candidate A ranked",
  "Candidate B ranked",
  "Candidate C ranked — exact source location highlighted for the top result",
] as const;

/**
 * Scene 5 (mission §22.5) — retrieval illustration. Explicitly labeled
 * as an internal evaluation framework (S1-E1/S1-E2), never presented as
 * a finished clinician-facing search feature — see the Capability Truth
 * Matrix row for "Retrieval evaluation foundation".
 */
export function RetrievalScene() {
  const reducedMotion = useEffectiveReducedMotion();
  const [playing, setPlaying] = useState(false);
  const [resetSignal, setResetSignal] = useState(0);
  const [step, setStep] = useStepSequence(playing, STEPS.length, resetSignal, 900);

  const effectiveStep = reducedMotion ? STEPS.length - 1 : step;
  const visibleCount = Math.max(0, effectiveStep);
  const sourceHighlighted = effectiveStep >= STEPS.length - 1;

  return (
    <PrototypeFrame
      id="retrieval-illustration"
      title="5. Retrieval Illustration"
      narrativeMeaning="Retrieval quality is measured before it's trusted. This ranked list is real evaluation-framework behavior (S1-E1 lexical, S1-E2 vector), shown honestly as internal measurement — not a finished clinician-facing search feature."
      implementation="Framer Motion"
      performanceNotes="staggerChildren on list items; transform/opacity only."
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
        <div className="flex items-center justify-between gap-sm">
          <div className="flex items-center gap-xs rounded-sm border border-border bg-canvas px-md py-xs">
            <Search size={16} className="text-muted" aria-hidden="true" />
            <span className="text-sm text-body">&ldquo;initial blood pressure assessment interval&rdquo;</span>
          </div>
          <Badge>Evaluation framework — internal, not yet clinician-facing</Badge>
        </div>

        <ol className="flex flex-col gap-xs" aria-label="Ranked evidence candidates">
          {CANDIDATES.map((candidate, index) => {
            const visible = reducedMotion ? true : index < visibleCount;
            const highlightSource = sourceHighlighted && index === 0;
            return (
              <motion.li
                key={candidate.label}
                initial={false}
                animate={{ opacity: visible ? 1 : 0, y: visible ? 0 : 8 }}
                transition={reducedMotion ? { duration: 0 } : { duration: 0.24, delay: index * 0.06 }}
                className="flex items-center gap-sm rounded-sm border border-border bg-canvas p-md"
              >
                <span className="flex h-7 w-7 flex-none items-center justify-center rounded-pill bg-surface-strong text-xs font-semibold text-ink">
                  {index + 1}
                </span>
                <div className="flex flex-1 flex-col gap-xxs">
                  <span className="text-sm font-medium text-ink">{candidate.label}</span>
                  <span className="text-xs text-muted">relevance {candidate.relevance.toFixed(2)}</span>
                </div>
                {/*
                  Color alone (not opacity) distinguishes the
                  highlighted source location — fading this text via
                  opacity previously blended muted (#59718F) down to a
                  2.01:1 contrast against white, caught by
                  @axe-core/playwright against a 4.5:1 requirement.
                  var(--noor-color-muted) already has its own
                  WCAG-checked contrast at full opacity.
                */}
                <div
                  className="flex items-center gap-xxs text-xs font-medium"
                  style={{ color: highlightSource ? "var(--noor-color-accent-active)" : "var(--noor-color-muted)" }}
                >
                  <MapPin size={14} aria-hidden="true" />
                  {candidate.source}
                </div>
              </motion.li>
            );
          })}
        </ol>
      </div>
    </PrototypeFrame>
  );
}
