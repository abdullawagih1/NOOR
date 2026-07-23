/** 4px base unit. Generous section spacing, denser inside data/tables (Carbon influence). */
export const spacing = {
  xxs: "0.25rem", // 4px
  xs: "0.5rem", // 8px
  sm: "0.75rem", // 12px
  md: "1rem", // 16px
  lg: "1.5rem", // 24px
  xl: "2rem", // 32px
  xxl: "3rem", // 48px
  section: "4rem", // 64px
} as const;

export type SpacingKey = keyof typeof spacing;
