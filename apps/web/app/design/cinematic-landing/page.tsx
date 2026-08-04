import { notFound } from "next/navigation";
import { SCENES, DESKTOP_VH_MULTIPLIER, MOBILE_VH_MULTIPLIER, MOBILE_BREAKPOINT_PX } from "./sceneConfig";

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
 *    server-route level").
 */
export const dynamic = "force-dynamic";
import { ReducedMotionOverrideProvider } from "../landing-experience/useEffectiveReducedMotion";
import { CinematicExperience } from "./CinematicExperience";
import { SceneSectionReveal } from "./overlays/SceneSectionReveal";
import { SceneIllustration } from "./overlays/SceneIllustration";
import { StatusChip } from "./overlays/StatusChip";
import { FinalCta } from "./overlays/FinalCta";

/**
 * LX-1.1.1 — Development-only cinematic prototype, with a narrow
 * Preview exception (mission §5). Gating, in order:
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
 *
 * Every scene's headline, supporting copy, and status label below is
 * real, server-rendered HTML present unconditionally — the fixed 3D
 * canvas (mounted client-side, only when motion is enabled) renders
 * BEHIND this content, it never replaces or duplicates it. See
 * docs/landing/NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md.
 *
 * Typography (mission §9/§3.4): editorial scale (a fluid clamp() up to
 * 72px for scene headlines), no small floating backdrop-blur card —
 * text sits directly over the scene with a soft directional gradient
 * wash behind it for contrast, never boxed.
 */
export default function CinematicLandingPrototypePage() {
  const isProduction = process.env.NODE_ENV === "production";
  const previewEnabled = process.env.NOOR_CINEMATIC_PREVIEW_ENABLED === "true";
  if (isProduction && !previewEnabled) {
    notFound();
  }

  return (
    <main className="text-white">
      <style>{`
        :root { --noor-cinematic-vh: ${DESKTOP_VH_MULTIPLIER}; }
        @media (max-width: ${MOBILE_BREAKPOINT_PX - 1}px) {
          :root { --noor-cinematic-vh: ${MOBILE_VH_MULTIPLIER}; }
        }
      `}</style>

      <ReducedMotionOverrideProvider>
        <CinematicExperience>
          {SCENES.map((scene) => (
            <section
              key={scene.id}
              id={`scene-${scene.id}`}
              aria-labelledby={`scene-${scene.id}-heading`}
              className="relative px-lg pt-[calc(46vh+1.5rem)] sm:px-xl sm:pt-32 lg:px-xxl"
              style={{ minHeight: `calc((${scene.end} - ${scene.start}) * var(--noor-cinematic-vh) * 100vh)` }}
            >
              {/*
                position: sticky, not flex-centering a point inside a
                very tall section — the real bug a screenshot caught
                (not assumed): a centered block inside an 8+-viewport-
                tall flex container is only fully in frame for a brief
                middle window of that section's scroll range; for most
                of it, the block is clipped by the viewport edge or
                off-screen entirely. Sticky keeps the copy in a stable,
                fully-visible position for the section's ENTIRE scroll
                duration — the standard scrollytelling technique, and
                the actual fix "hold, then move" pacing needed.

                The section's own top padding (matching the sticky
                `top` offset below) matters specifically for Scene 1:
                before any scrolling happens, a sticky element sits at
                its natural flow position, not yet at its stuck offset
                — without this padding, Scene 1's content starts flush
                against the page top and collides with the fixed nav
                for the first few percent of scroll (caught in a real
                screenshot, not assumed).
              */}
              <div className="sticky top-[calc(46vh+1.5rem)] flex min-h-[calc(54vh-2.5rem)] items-center sm:top-32 sm:min-h-[calc(100vh-8rem)]">
                <SceneSectionReveal sceneId={scene.id}>
                  <div
                    className="relative max-w-2xl py-lg pr-lg sm:pr-xxl"
                    style={{
                      background:
                        "linear-gradient(105deg, rgba(5,15,30,0.86) 0%, rgba(5,15,30,0.62) 65%, rgba(5,15,30,0.2) 100%)",
                    }}
                  >
                    <SceneIllustration sceneKey={scene.key} />
                    <p className="mt-md text-xs font-semibold uppercase tracking-[0.16em] text-white/55">
                      Scene {scene.id} of {SCENES.length}
                    </p>
                    {/*
                      Scene 1's headline is the page's single required
                      <h1> (a real axe scan flagged "page-has-heading-one"
                      — every scene used <h2>, leaving the page with
                      none) — it IS the page's thesis statement, so this
                      is also the semantically correct choice, not just
                      a rule-satisfying workaround. Scenes 2-7 stay <h2>.
                    */}
                    {scene.id === 1 ? (
                      <h1
                        id={`scene-${scene.id}-heading`}
                        className="mt-sm font-semibold leading-[1.05] text-white text-[clamp(2.1rem,4.6vw,4rem)]"
                      >
                        {scene.headline}
                      </h1>
                    ) : (
                      <h2
                        id={`scene-${scene.id}-heading`}
                        className="mt-sm font-semibold leading-[1.05] text-white text-[clamp(2.1rem,4.6vw,4rem)]"
                      >
                        {scene.headline}
                      </h2>
                    )}
                    <p className="mt-md max-w-md text-[clamp(1.05rem,1.3vw,1.25rem)] leading-relaxed text-white/85">
                      {scene.supportingCopy}
                    </p>
                    <div className="mt-lg">
                      <StatusChip status={scene.status} label={scene.statusLabel} />
                    </div>
                    {scene.key === "product-vision" ? (
                      <p className="mt-sm text-xs text-white/50">Synthetic demonstration — not clinical guidance.</p>
                    ) : null}
                    {scene.key === "reverse-traceability" ? (
                      <div className="mt-xxl">
                        <FinalCta />
                      </div>
                    ) : null}
                  </div>
                </SceneSectionReveal>
              </div>
            </section>
          ))}
        </CinematicExperience>
      </ReducedMotionOverrideProvider>
    </main>
  );
}
