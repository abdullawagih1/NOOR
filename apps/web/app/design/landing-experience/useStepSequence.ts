"use client";

import { useEffect, useState } from "react";

/**
 * Drives a discrete step index (0..stepCount-1) for scenes whose motion
 * is expressed as a sequence of resolved states rather than a
 * scroll-linked timeline (Scene 8's GSAP ScrollTrigger is the one
 * exception with its own driver). Stops at the last step — mission
 * §22.1 explicitly requires prototypes not to loop continuously by
 * default.
 */
export function useStepSequence(
  playing: boolean,
  stepCount: number,
  resetSignal: number,
  intervalMs = 900
): [number, (step: number) => void] {
  const [step, setStep] = useState(0);

  useEffect(() => {
    setStep(0);
  }, [resetSignal]);

  useEffect(() => {
    if (!playing) return;
    if (step >= stepCount - 1) return;
    const timer = setTimeout(() => setStep((current) => Math.min(current + 1, stepCount - 1)), intervalMs);
    return () => clearTimeout(timer);
  }, [playing, step, stepCount, intervalMs]);

  return [step, setStep];
}
