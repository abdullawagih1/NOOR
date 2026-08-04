import type { Metadata } from "next";
import { LegacyPublicLanding } from "./LegacyPublicLanding";
import { CinematicPublicLanding } from "./design/cinematic-landing/CinematicPublicLanding";
import { getPublicLandingExperience } from "@/lib/publicLanding/getPublicLandingExperience";
import { resolveLandingCta } from "@/lib/publicLanding/resolveLandingCta";

/**
 * LX-1.2 — the public "/" route now selects ONE experience per
 * request, entirely server-side (mission §10):
 *
 *   getPublicLandingExperience() === "cinematic"
 *     → CinematicPublicLanding  (the approved LX-1.1.1 experience)
 *   otherwise ("legacy", or any invalid/missing flag value)
 *     → LegacyPublicLanding     (byte-for-byte the pre-LX-1.2 page)
 *
 * There is no client-side variant switch, no dual render-and-hide, and
 * no loading placeholder while choosing — the decision is made before
 * any HTML is sent, so there is nothing to flash or hydrate
 * inconsistently between server and client. Production stays on
 * "legacy" for the duration of this mission (NOOR_PUBLIC_LANDING_FEATURE_FLAG.md);
 * only a Vercel Preview with NOOR_PUBLIC_LANDING_EXPERIENCE=cinematic
 * renders the cinematic branch.
 *
 * `dynamic = "force-dynamic"`: `resolveLandingCta()` calls `cookies()`
 * internally (via the Supabase SSR client), which already opts this
 * route into per-request dynamic rendering automatically even without
 * this export (confirmed: removing it made no difference to the
 * build output, still `ƒ /`) — kept explicit anyway to match this
 * codebase's existing convention on every other route that depends on
 * request-specific state (see /design/cinematic-landing, /knowledge's
 * layout).
 *
 * Known, investigated, pre-existing limitation (not introduced by
 * this mission): on ANY dynamically-rendered route in this Next.js
 * 15.5.21 app — confirmed on /login too, which this mission never
 * touched — the framework's own "streaming metadata" behavior
 * (`next/dist/server/lib/streaming-metadata.js`) places `<head>`
 * metadata tags as children of `<body>` in the live DOM for ordinary
 * browser/crawler requests, confirmed directly via Playwright even
 * after full network-idle hydration. Neither making `generateMetadata`
 * synchronous nor removing the explicit `force-dynamic` export changed
 * this (both were tried against a real build, not assumed) — the
 * behavior is tied to Next's dynamic-rendering path itself, not to
 * this function. Next.js deliberately exempts known simple/non-JS
 * "HTML-limited" crawler user agents from this path (they get
 * synchronous, correctly head-placed metadata unconditionally,
 * built into the framework, regardless of this route) — the practical
 * risk is narrower than it first appears, but not zero for a
 * JS-executing crawler that reads `document.head` strictly. Recorded
 * honestly in KNOWN_LIMITATIONS.md rather than claimed fixed.
 */
export const dynamic = "force-dynamic";

// Deliberately synchronous (no `async`) — tried making it async during
// investigation of the metadata-placement issue above; it made no
// difference (the behavior is tied to dynamic rendering, not to this
// function's sync/async-ness), but synchronous is still simpler and
// correct here since nothing this function needs is actually
// asynchronous.
export function generateMetadata(): Metadata {
  const experience = getPublicLandingExperience();
  const description =
    experience === "cinematic"
      ? "See how NOOR verifies, reviews, and traces every piece of clinical evidence — from trusted source to reverse-traceable intelligence."
      : "Evidence-grounded clinical decision support for healthcare organizations.";
  return {
    title: "Noor — Clinical Intelligence OS",
    description,
    alternates: { canonical: "/" },
    openGraph: { description },
    twitter: { description },
  };
}

export default async function HomePage() {
  const experience = getPublicLandingExperience();
  const cta = await resolveLandingCta();

  if (experience === "cinematic") {
    return <CinematicPublicLanding cta={cta} />;
  }
  return <LegacyPublicLanding cta={cta} />;
}
