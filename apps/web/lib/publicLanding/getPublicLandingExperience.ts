export type PublicLandingExperience = "legacy" | "cinematic";

/**
 * Resolves which experience the public "/" route renders, server-side
 * only (LX-1.2 mission §8). Read directly via `process.env`, the same
 * pattern established for `NOOR_CINEMATIC_PREVIEW_ENABLED` in LX-1.1.1
 * (a raw inline check, not routed through the Zod-validated env
 * modules, which are reserved for values the app cannot run without).
 *
 * Deliberately NOT a `NEXT_PUBLIC_` variable — this must never be
 * resolvable or overridable from the browser, and there must be no
 * client-side variant switch (mission §8/§10). Any value other than
 * exactly "cinematic" fails closed to "legacy", including missing,
 * empty, malformed, or misspelled values — the public production
 * landing must never silently switch on due to a typo.
 */
export function getPublicLandingExperience(): PublicLandingExperience {
  const raw = process.env.NOOR_PUBLIC_LANDING_EXPERIENCE;
  return raw === "cinematic" ? "cinematic" : "legacy";
}
