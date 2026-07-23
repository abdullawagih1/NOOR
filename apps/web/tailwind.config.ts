import type { Config } from "tailwindcss";
import { spacing, radius, shadows, fontFamilies } from "@noor/ui/tokens";

// Tailwind's utility classes are generated directly from the canonical
// tokens in packages/ui/tokens — there is no second, hand-maintained color
// scale. Dark mode uses the [data-theme] / prefers-color-scheme CSS
// variables emitted by tokensToCssVariables() (see TokensStyleTag), so the
// Tailwind color utilities below reference the CSS variables, not raw hex,
// letting one class (e.g. `bg-canvas`) resolve correctly in both themes.
const config: Config = {
  darkMode: ["class", '[data-theme="dark"]'],
  content: [
    "./app/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
    "../../packages/ui/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: "var(--noor-color-primary)",
        "primary-active": "var(--noor-color-primary-active)",
        "primary-soft": "var(--noor-color-primary-soft)",
        ink: "var(--noor-color-ink)",
        body: "var(--noor-color-body)",
        muted: "var(--noor-color-muted)",
        "muted-soft": "var(--noor-color-muted-soft)",
        canvas: "var(--noor-color-canvas)",
        "surface-soft": "var(--noor-color-surface-soft)",
        "surface-strong": "var(--noor-color-surface-strong)",
        border: "var(--noor-color-border)",
        "border-strong": "var(--noor-color-border-strong)",
        "on-primary": "var(--noor-color-on-primary)",
      },
      spacing: Object.fromEntries(Object.entries(spacing).map(([k, v]) => [k, v])),
      borderRadius: Object.fromEntries(Object.entries(radius).map(([k, v]) => [k, v])),
      boxShadow: Object.fromEntries(Object.entries(shadows).map(([k, v]) => [k, v])),
      fontFamily: {
        sans: [fontFamilies.latin, "system-ui", "sans-serif"],
        arabic: [fontFamilies.arabic, "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
};

export default config;
