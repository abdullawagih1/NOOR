import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { CinematicPublicLanding } from "./CinematicPublicLanding";
import { resolveLandingCta } from "@/lib/publicLanding/resolveLandingCta";

// Defense-in-depth (mission §25/§33): the production 404 gate below is
// the primary protection, but this route IS reachable on a Preview
// deployment — noindex/nofollow there too, so a crawler that somehow
// reaches a Preview URL never indexes it.
export const metadata: Metadata = { robots: { index: false, follow: false } };

/**
 * Forces per-request rendering rather than a build-time static export.
 * Two real reasons, both found by actually attempting a Preview build
 * (`NOOR_CINEMATIC_PREVIEW_ENABLED=true npm run build`), not assumed:
 *
 * 1. `CinematicExperience` reads `useSearchParams()` (for `?debug=1`),
 *    which Next.js's static exporter refuses to prerender without a
 *    Suspense boundary — a real build failure, not a hypothetical one.
 * 2. A statically-exported page bakes in whatever `NOOR_CINEMATIC_PREVIEW_ENABLED`
 *    was at *build* time, permanently, for every future request —
 *    setting the env var only when *starting* the server (after an
 *    earlier build without it) had no effect, confirmed directly. Real
 *    Vercel Previews do inject env vars at build time per-deployment,
 *    so that alone would still work, but forcing dynamic rendering
 *    here makes the gate a genuine per-request check either way, which
 *    is the more literal reading of mission §5 ("gate at the
 *    server-route level"). LX-1.2: also required now that this route
 *    resolves an auth-aware CTA (reads the request's session cookie).
 */
export const dynamic = "force-dynamic";

/**
 * LX-1.2 — this route is now a thin gate around the same
 * `CinematicPublicLanding` production component the public root route
 * (`app/page.tsx`) can render — see that component's own doc comment
 * for why the two routes share one definition instead of two. This
 * file's only remaining job is the Development/Preview-only gate
 * (mission §33), unchanged from LX-1.1.1:
 *
 *   1. Local development (NODE_ENV !== "production"): always available.
 *   2. A real production build (NODE_ENV === "production") with
 *      NOOR_CINEMATIC_PREVIEW_ENABLED exactly "true": available — this
 *      is how a Vercel Preview deployment (which also builds with
 *      NODE_ENV=production) can host the route for real-GPU/production-
 *      build performance measurement, without touching Vercel's own
 *      Deployment Protection (this env var is orthogonal to it, not a
 *      replacement for it — see docs/landing/
 *      NOOR_CINEMATIC_PREVIEW_DEPLOYMENT.md).
 *   3. Every other production build (the real public site — the env
 *      var absent or not exactly "true"): 404, same as
 *      /design-system and /design/landing-experience.
 *
 * The gate is server-side (this file never renders on the client
 * before the check), so there is no client-side-only hiding to bypass.
 * `?debug=1` (handled inside CinematicExperience, unchanged) affects
 * only this internal route — the public root route below never
 * exposes it (mission §33: "Public root never enables debug UI").
 */
export default async function CinematicLandingPrototypePage() {
  const isProduction = process.env.NODE_ENV === "production";
  const previewEnabled = process.env.NOOR_CINEMATIC_PREVIEW_ENABLED === "true";
  if (isProduction && !previewEnabled) {
    notFound();
  }

  const cta = await resolveLandingCta();
  return <CinematicPublicLanding cta={cta} />;
}
