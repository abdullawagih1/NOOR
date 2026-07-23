/**
 * Minimal elevation (DESIGN.md: "the system has essentially one shadow
 * tier"). Noor uses two: a resting card border-shadow and a raised tier for
 * modals/popovers. No deep, layered enterprise shadow stacks.
 */
export const shadows = {
  none: "none",
  card: "0 1px 2px rgba(23, 33, 33, 0.06), 0 1px 0 rgba(23, 33, 33, 0.04)",
  raised: "0 8px 24px rgba(23, 33, 33, 0.12), 0 2px 6px rgba(23, 33, 33, 0.08)",
} as const;

export type ShadowKey = keyof typeof shadows;
