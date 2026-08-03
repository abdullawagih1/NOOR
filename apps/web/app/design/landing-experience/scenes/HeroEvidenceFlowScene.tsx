"use client";

import { motion } from "framer-motion";
import { CheckCircle2, Eye, FileText, GitBranch, Link2 } from "lucide-react";
import { PrototypeFrame } from "../PrototypeFrame";
import { useEffectiveReducedMotion } from "../useEffectiveReducedMotion";
import { useStepSequence } from "../useStepSequence";
import { useState } from "react";

const STAGES = [
  { label: "Source", icon: FileText },
  { label: "Verified", icon: CheckCircle2 },
  { label: "Reviewed", icon: Eye },
  { label: "Structured", icon: GitBranch },
  { label: "Traceable", icon: Link2 },
] as const;

/**
 * Scene 1 (mission §22.1) — the hero's evidence-flow strip. Narrative:
 * evidence becomes intelligence through a visible, ordered process, not
 * a black box. Runs once per Play press; never autoplays continuously.
 */
export function HeroEvidenceFlowScene() {
  const reducedMotion = useEffectiveReducedMotion();
  const [playing, setPlaying] = useState(false);
  const [resetSignal, setResetSignal] = useState(0);
  const [step, setStep] = useStepSequence(playing, STAGES.length, resetSignal);

  const effectiveStep = reducedMotion ? STAGES.length - 1 : step;

  return (
    <PrototypeFrame
      id="hero-evidence-flow"
      title="1. Hero Evidence Flow"
      narrativeMeaning="This is the landing's thesis: evidence becomes intelligence through a visible, ordered process — Source, Verified, Reviewed, Structured, Traceable — not a black box."
      implementation="Framer Motion"
      performanceNotes="Pure CSS/SVG shapes, no images. staggerChildren timing, transform/opacity only."
      stepLabel={STAGES[effectiveStep].label}
      stepIndex={effectiveStep}
      stepCount={STAGES.length}
      playing={playing}
      onPlayingChange={setPlaying}
      onReset={() => {
        setPlaying(false);
        setResetSignal((value) => value + 1);
      }}
    >
      <ol className="flex flex-wrap items-center gap-sm" aria-label="Evidence flow stages">
        {STAGES.map((stage, index) => {
          const resolved = index <= effectiveStep;
          const Icon = stage.icon;
          return (
            <li key={stage.label} className="flex items-center gap-sm">
              {/*
                Opacity/scale motion is applied only to the decorative
                icon circle, never to the text label — dimming label text
                via opacity produced a real WCAG contrast failure (caught
                by @axe-core/playwright: 2.16:1 against a 4.5:1
                requirement) because opacity blends toward the
                background rather than toward a contrast-checked color.
                The "unresolved" state is instead conveyed by the icon's
                border/background color change, which stays a real,
                contrast-checked token switch.
              */}
              <div className="flex flex-col items-center gap-xxs">
                <motion.span
                  className="flex h-11 w-11 items-center justify-center rounded-pill border-2"
                  initial={false}
                  animate={{ scale: resolved ? 1 : 0.92 }}
                  transition={reducedMotion ? { duration: 0 } : { duration: 0.26, ease: [0.16, 1, 0.3, 1] }}
                  style={{
                    borderColor: resolved ? "var(--noor-color-accent)" : "var(--noor-color-border)",
                    backgroundColor: resolved ? "var(--noor-color-accent-soft)" : "transparent",
                    color: resolved ? "var(--noor-color-accent-active)" : "var(--noor-color-muted)",
                  }}
                >
                  <Icon size={20} aria-hidden="true" />
                </motion.span>
                <span className="text-xs font-medium text-body">{stage.label}</span>
              </div>
              {index < STAGES.length - 1 ? (
                <span className="h-px w-8 flex-none bg-border" aria-hidden="true" />
              ) : null}
            </li>
          );
        })}
      </ol>
    </PrototypeFrame>
  );
}
