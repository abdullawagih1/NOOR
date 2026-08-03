"use client";

import { createContext, useContext, useState, type ReactNode } from "react";
import { useReducedMotion as useSystemReducedMotion } from "framer-motion";

/**
 * Effective reduced-motion state = the real OS preference, unless a
 * reviewer has explicitly overridden it via the prototype gallery's
 * "Reduced-motion preview" toggle (mission §21). Production scenes
 * (LX-1.2+) will only ever read the system preference — this override
 * layer exists solely so reviewers (and Playwright) can inspect the
 * reduced-motion path without changing OS settings.
 */
const ReducedMotionOverrideContext = createContext<{
  override: boolean | null;
  setOverride: (value: boolean | null) => void;
}>({ override: null, setOverride: () => {} });

export function ReducedMotionOverrideProvider({ children }: { children: ReactNode }) {
  const [override, setOverride] = useState<boolean | null>(null);
  return (
    <ReducedMotionOverrideContext.Provider value={{ override, setOverride }}>
      {children}
    </ReducedMotionOverrideContext.Provider>
  );
}

export function useReducedMotionOverrideControl() {
  return useContext(ReducedMotionOverrideContext);
}

export function useEffectiveReducedMotion(): boolean {
  const systemPreference = useSystemReducedMotion();
  const { override } = useContext(ReducedMotionOverrideContext);
  return override !== null ? override : Boolean(systemPreference);
}
