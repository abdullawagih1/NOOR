import { ReducedMotionOverrideProvider } from "../landing-experience/useEffectiveReducedMotion";
import { CinematicExperience } from "./CinematicExperience";
import { SceneSectionReveal } from "./overlays/SceneSectionReveal";
import { SceneIllustration } from "./overlays/SceneIllustration";
import { StatusChip } from "./overlays/StatusChip";
import { FinalCta } from "./overlays/FinalCta";
import { SCENES, DESKTOP_VH_MULTIPLIER, MOBILE_VH_MULTIPLIER, MOBILE_BREAKPOINT_PX } from "./sceneConfig";
import type { PublicLandingCta } from "@/lib/publicLanding/PublicLandingCta";

export interface CinematicPublicLandingProps {
  cta: PublicLandingCta;
}

/**
 * The approved LX-1.1.1 cinematic experience, extracted into a real
 * production component (LX-1.2 mission §11) — this is the ONLY place
 * the seven-scene narrative markup is defined. Both the production
 * root route (`app/page.tsx`, gated by `getPublicLandingExperience()`)
 * and the internal design/Preview route
 * (`app/design/cinematic-landing/page.tsx`, gated by
 * `NOOR_CINEMATIC_PREVIEW_ENABLED`) render this same component — the
 * design route is a thin gate wrapper around it, never a duplicate
 * copy of its markup (the literal "cinematic landing uses production
 * components, not imports from a dev-only page file" requirement).
 *
 * Kept in this directory rather than a separate top-level "production"
 * folder: every sibling module it and its children import
 * (`./sceneConfig`, `./CinematicExperience`, `./EvidenceCore/*`, the
 * various `./use*` hooks) is a relative import rooted here — moving
 * just this one file elsewhere would not change what it does, only
 * how many import paths need rewriting across ~20 already-verified
 * files for no functional benefit. Documented in
 * NOOR_CINEMATIC_PRODUCTION_ARCHITECTURE.md as a deliberate scoping
 * decision, not an oversight.
 *
 * No visual/narrative change from LX-1.1.1 — this is a structural
 * extraction only. `cta` is the one new prop threaded through to the
 * nav and the final CTA (mission §22/§24): resolved server-side per
 * request, never a hardcoded "/login".
 */
export function CinematicPublicLanding({ cta }: CinematicPublicLandingProps) {
  return (
    <main className="text-white">
      <style>{`
        :root { --noor-cinematic-vh: ${DESKTOP_VH_MULTIPLIER}; }
        @media (max-width: ${MOBILE_BREAKPOINT_PX - 1}px) {
          :root { --noor-cinematic-vh: ${MOBILE_VH_MULTIPLIER}; }
        }
      `}</style>

      <ReducedMotionOverrideProvider>
        <CinematicExperience cta={cta}>
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
                        <FinalCta cta={cta} />
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
