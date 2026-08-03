"use client";

import { motion } from "framer-motion";
import { FileText, FileX, ShieldCheck } from "lucide-react";
import { useState } from "react";
import { SemanticStatusBadge } from "@noor/ui";
import { PrototypeFrame } from "../PrototypeFrame";
import { useEffectiveReducedMotion } from "../useEffectiveReducedMotion";
import { useStepSequence } from "../useStepSequence";

const STEPS = [
  "Source registered (pending)",
  "Checksum resolves (SHA-256)",
  "Status flips to Verified — valid path continues",
  "Illustrative invalid file — processing stops before the queue",
] as const;

/**
 * Scene 2 (mission §22.2) — combines Sections 2 (Trusted Clinical
 * Sources) and 3 (Secure Intake) from the storyboard into one
 * prototype, matching the mission's own §22.2 description exactly
 * ("Source enters → File identity resolves → Verification indicators
 * appear → Invalid path visibly stops → Valid path continues").
 */
export function SourceVerificationScene() {
  const reducedMotion = useEffectiveReducedMotion();
  const [playing, setPlaying] = useState(false);
  const [resetSignal, setResetSignal] = useState(0);
  const [step, setStep] = useStepSequence(playing, STEPS.length, resetSignal, 1000);

  const effectiveStep = reducedMotion ? STEPS.length - 1 : step;
  const checksumVisible = effectiveStep >= 1;
  const verified = effectiveStep >= 2;
  const invalidShown = effectiveStep >= 3;

  return (
    <PrototypeFrame
      id="source-verification"
      title="2. Source Verification"
      narrativeMeaning="Trust starts before any AI is involved: a registered, versioned source resolves a real checksum and a visible verification state. The invalid path is shown stopping, not just the happy path."
      implementation="Framer Motion"
      performanceNotes="Transform/opacity only; no layout-triggering properties."
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
      <div className="flex flex-col gap-md">
        <div className="flex flex-col gap-xs rounded-sm border border-border bg-canvas p-md">
          <div className="flex items-center gap-sm">
            <FileText size={20} className="text-muted" aria-hidden="true" />
            <span className="text-sm font-medium text-ink">clinical-guideline-2026-v3.pdf</span>
            <span className="ml-auto">
              <SemanticStatusBadge state={verified ? "verified" : "processing"} labelOverride={verified ? undefined : "Pending"} />
            </span>
          </div>
          <motion.div
            initial={false}
            animate={{ opacity: checksumVisible ? 1 : 0, height: checksumVisible ? "auto" : 0 }}
            transition={reducedMotion ? { duration: 0 } : { duration: 0.26 }}
            className="overflow-hidden"
          >
            <div className="flex items-center gap-xs text-xs text-muted">
              <ShieldCheck size={14} aria-hidden="true" />
              <span className="font-mono" style={{ direction: "ltr" }}>
                sha256:8f3a…c19e (checksum resolved)
              </span>
            </div>
          </motion.div>
        </div>

        <div className="flex flex-col gap-xs rounded-sm border border-dashed border-border bg-canvas p-md">
          <span className="text-xs font-semibold uppercase tracking-wide text-muted">Invalid path (illustrative)</span>
          {/*
            Text stays at full opacity in both states — only the icon's
            color switches (muted → critical). Fading the label/status
            text via opacity previously failed WCAG contrast (1.77:1 and
            1.78:1 against a 4.5:1 requirement), caught by
            @axe-core/playwright.
          */}
          <div className="flex items-center gap-sm">
            <motion.span
              initial={false}
              animate={{ opacity: invalidShown ? 1 : 0.5 }}
              transition={reducedMotion ? { duration: 0 } : { duration: 0.26 }}
            >
              <FileX
                size={20}
                className={invalidShown ? "text-[var(--noor-state-critical-fg)]" : "text-muted"}
                aria-hidden="true"
              />
            </motion.span>
            <span className="text-sm text-body">unsigned-attachment.pdf</span>
            <span
              className="ml-auto text-xs font-medium"
              style={{ color: invalidShown ? "var(--noor-state-critical-fg)" : "var(--noor-color-muted)" }}
            >
              {invalidShown ? "Invalid — processing does not continue" : "Waiting"}
            </span>
          </div>
        </div>
      </div>
    </PrototypeFrame>
  );
}
