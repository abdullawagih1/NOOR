/** Smoothstep between two progress values — every Evidence Core
 * component derives its own "how resolved am I" state from the single
 * overall scroll progress this way, which is what makes scroll
 * reversal work correctly for free (it's a pure function of progress,
 * not a one-shot triggered animation). */
export function activation(progress: number, start: number, end: number): number {
  if (end <= start) return progress >= start ? 1 : 0;
  const t = Math.min(1, Math.max(0, (progress - start) / (end - start)));
  return t * t * (3 - 2 * t);
}
