import { tokensToCssVariables } from "../tokens";

/**
 * Renders the canonical design tokens as CSS custom properties. This is the
 * only place tokensToCssVariables() is called — one runtime source, no
 * hand-copied duplicate of any token value in a stylesheet.
 */
export function TokensStyleTag() {
  return <style id="noor-tokens" dangerouslySetInnerHTML={{ __html: tokensToCssVariables() }} />;
}
