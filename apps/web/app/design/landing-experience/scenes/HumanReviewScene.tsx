"use client";

import { motion } from "framer-motion";
import { CheckCircle2, FileSearch, FileText, Lock, Unlock, UserCheck } from "lucide-react";
import { useState } from "react";
import { SemanticStatusBadge } from "@noor/ui";
import { PrototypeFrame } from "../PrototypeFrame";
import { useEffectiveReducedMotion } from "../useEffectiveReducedMotion";
import { useStepSequence } from "../useStepSequence";

const STEPS = [
  "Source and extracted representation aligned",
  "Finding highlighted",
  "Reviewer decision: Accepted",
  "Downstream path unlocks",
] as const;

/**
 * Scene 3 (mission §22.3) — the human review gate. Narrative: automation
 * prepares the evidence, but a human reviewer decides when it's ready —
 * the downstream unlock is shown as an explicit, visible state change.
 */
export function HumanReviewScene() {
  const reducedMotion = useEffectiveReducedMotion();
  const [playing, setPlaying] = useState(false);
  const [resetSignal, setResetSignal] = useState(0);
  const [step, setStep] = useStepSequence(playing, STEPS.length, resetSignal, 1000);

  const effectiveStep = reducedMotion ? STEPS.length - 1 : step;
  const findingHighlighted = effectiveStep >= 1;
  const accepted = effectiveStep >= 2;
  const unlocked = effectiveStep >= 3;

  const columns = [
    { label: "Source page", icon: FileText, body: "Page 4 — original scanned text" },
    { label: "Extracted representation", icon: FileSearch, body: "Deterministic page-level text" },
    { label: "Finding", icon: FileSearch, body: "Low-confidence table region", emphasize: findingHighlighted },
    { label: "Reviewer decision", icon: UserCheck, body: accepted ? "Accepted" : "Pending", emphasize: accepted },
  ];

  return (
    <PrototypeFrame
      id="human-review-gate"
      title="3. Human Review Gate"
      narrativeMeaning="Automation prepares the evidence. Human review decides when it's ready — the downstream path visibly unlocks only after an explicit reviewer decision, never automatically."
      implementation="Framer Motion"
      performanceNotes="Layout animation across 4 columns; transform/opacity only, no reflow-triggering properties."
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
        <div className="grid gap-sm sm:grid-cols-4">
          {columns.map((column) => {
            const Icon = column.icon;
            return (
              <motion.div
                key={column.label}
                layout
                initial={false}
                animate={{
                  borderColor: column.emphasize ? "var(--noor-color-accent)" : "var(--noor-color-border)",
                  backgroundColor: column.emphasize ? "var(--noor-color-accent-soft)" : "var(--noor-color-canvas)",
                }}
                transition={reducedMotion ? { duration: 0 } : { duration: 0.26 }}
                className="flex flex-col gap-xs rounded-sm border p-md"
              >
                <div className="flex items-center gap-xs">
                  <Icon size={16} className="text-muted" aria-hidden="true" />
                  {/* text-body, not text-muted: this column's background
                      becomes accent-soft (teal-100) when emphasized, and
                      text-muted only clears 4.31:1 against it — a real
                      WCAG AA failure caught by @axe-core/playwright. */}
                  <span className="text-xs font-semibold uppercase tracking-wide text-body">{column.label}</span>
                </div>
                <p className="text-sm text-ink">{column.body}</p>
              </motion.div>
            );
          })}
        </div>

        <motion.div
          initial={false}
          animate={{
            borderColor: unlocked ? "var(--noor-color-accent)" : "var(--noor-color-border)",
            backgroundColor: unlocked ? "var(--noor-color-accent-soft)" : "var(--noor-color-surface-strong)",
          }}
          transition={reducedMotion ? { duration: 0 } : { duration: 0.26, ease: [0.34, 1.16, 0.64, 1] }}
          className="flex items-center gap-sm rounded-sm border p-md"
          aria-live="polite"
        >
          {unlocked ? (
            <Unlock size={18} className="text-[var(--noor-color-accent-active)]" aria-hidden="true" />
          ) : (
            <Lock size={18} className="text-muted" aria-hidden="true" />
          )}
          <span className="text-sm font-medium text-ink">
            {unlocked ? "Downstream stage unlocked — this page can now proceed to chunking" : "Downstream stage locked until review is accepted"}
          </span>
          {accepted ? (
            <span className="ml-auto">
              <SemanticStatusBadge state="humanApproved" />
            </span>
          ) : null}
        </motion.div>
      </div>
    </PrototypeFrame>
  );
}
