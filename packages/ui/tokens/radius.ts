/** Soft, rounded shapes (DESIGN.md warmth) applied to a denser clinical layout (Better/Carbon influence). */
export const radius = {
  none: "0px",
  sm: "0.5rem", // 8px — inputs, buttons
  md: "0.75rem", // 12px — cards
  lg: "1rem", // 16px — panels, modals
  pill: "9999px", // the clinical question bar, tags
} as const;

export type RadiusKey = keyof typeof radius;
