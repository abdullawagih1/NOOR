/**
 * Typography — Inter (Latin) / IBM Plex Sans Arabic (RTL), both self-hosted
 * via next/font (no proprietary font dependency, no external font CDN call
 * at request time). Modest heading weights on purpose: this is a clinical
 * reading surface, not marketing type.
 */
export const fontFamilies = {
  latin: "var(--noor-font-latin)",
  arabic: "var(--noor-font-arabic)",
} as const;

export interface TypeScale {
  fontSize: string;
  lineHeight: string;
  fontWeight: number;
  letterSpacing?: string;
}

export const typeScale = {
  display: { fontSize: "1.75rem", lineHeight: "1.3", fontWeight: 600 }, // 28px
  pageTitle: { fontSize: "1.5rem", lineHeight: "1.35", fontWeight: 600 }, // 24px
  sectionTitle: { fontSize: "1.25rem", lineHeight: "1.4", fontWeight: 600 }, // 20px
  cardTitle: { fontSize: "1rem", lineHeight: "1.45", fontWeight: 600 }, // 16px
  body: { fontSize: "1rem", lineHeight: "1.6", fontWeight: 400 }, // 16px
  bodySecondary: { fontSize: "0.875rem", lineHeight: "1.55", fontWeight: 400 }, // 14px
  caption: { fontSize: "0.8125rem", lineHeight: "1.4", fontWeight: 500 }, // 13px
} satisfies Record<string, TypeScale>;

export type TypeScaleKey = keyof typeof typeScale;
