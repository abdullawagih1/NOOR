export * from "./colors";
export * from "./typography";
export * from "./spacing";
export * from "./radius";
export * from "./shadows";

import { brandColors, brandColorsDark, semanticStates, type SemanticStateKey } from "./colors";
import { spacing } from "./spacing";
import { radius } from "./radius";
import { shadows } from "./shadows";

function kebab(key: string): string {
  return key.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
}

function colorVars(colors: Record<string, string>): string {
  return Object.entries(colors)
    .map(([key, value]) => `--noor-color-${kebab(key)}: ${value};`)
    .join("\n  ");
}

function semanticStateVars(prop: "fg" | "bg" | "border"): string {
  return Object.entries(semanticStates)
    .map(([key, token]) => `--noor-state-${kebab(key)}-${prop}: ${token[prop]};`)
    .join("\n  ");
}

function semanticStateVarsDark(prop: "fg" | "bg" | "border"): string {
  const darkProp = `${prop}Dark` as "fgDark" | "bgDark" | "borderDark";
  return Object.entries(semanticStates)
    .map(([key, token]) => `--noor-state-${kebab(key)}-${prop}: ${token[darkProp]};`)
    .join("\n  ");
}

/** CSS var triplet for a semantic state — use in inline styles so color choice stays theme-aware without JS. */
export function semanticStateVarRefs(key: SemanticStateKey) {
  const k = kebab(key);
  return {
    color: `var(--noor-state-${k}-fg)`,
    backgroundColor: `var(--noor-state-${k}-bg)`,
    borderColor: `var(--noor-state-${k}-border)`,
  };
}

/**
 * The single canonical token source (packages/ui/tokens/*) is consumed two
 * ways with zero duplication: Tailwind's config imports these objects
 * directly for utility classes, and this function renders the same values
 * as CSS custom properties for non-Tailwind/inline use and the dark-mode
 * override. There is deliberately no second, hand-maintained copy of any
 * token value anywhere else in the app.
 */
export function tokensToCssVariables(): string {
  const light = `:root {
  ${colorVars(brandColors)}
  ${semanticStateVars("fg")}
  ${semanticStateVars("bg")}
  ${semanticStateVars("border")}
  ${Object.entries(spacing).map(([k, v]) => `--noor-space-${kebab(k)}: ${v};`).join("\n  ")}
  ${Object.entries(radius).map(([k, v]) => `--noor-radius-${kebab(k)}: ${v};`).join("\n  ")}
  ${Object.entries(shadows).map(([k, v]) => `--noor-shadow-${kebab(k)}: ${v};`).join("\n  ")}
}`;

  const darkVars = `${colorVars(brandColorsDark)}
  ${semanticStateVarsDark("fg")}
  ${semanticStateVarsDark("bg")}
  ${semanticStateVarsDark("border")}`;

  const dark = `:root[data-theme="dark"] {
  ${darkVars}
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    ${darkVars}
  }
}`;

  return `${light}\n\n${dark}`;
}
