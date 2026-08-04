/** Coarse, one-time WebGL availability check (mission §42) — never
 * assumed, always actually attempted. Returns false on any exception,
 * including a browser that blocks WebGL via extension/policy. */
export function isWebglAvailable(): boolean {
  if (typeof window === "undefined") return false;
  try {
    const canvas = document.createElement("canvas");
    const context = canvas.getContext("webgl2") || canvas.getContext("webgl");
    return Boolean(context);
  } catch {
    return false;
  }
}
