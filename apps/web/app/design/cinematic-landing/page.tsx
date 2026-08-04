import { notFound } from "next/navigation";
import { SCENES, DESKTOP_VH_MULTIPLIER, MOBILE_VH_MULTIPLIER, MOBILE_BREAKPOINT_PX } from "./sceneConfig";
import { ReducedMotionOverrideProvider } from "../landing-experience/useEffectiveReducedMotion";
import { CinematicExperience } from "./CinematicExperience";
import { SceneSectionReveal } from "./overlays/SceneSectionReveal";
import { SceneIllustration } from "./overlays/SceneIllustration";
import { StatusChip } from "./overlays/StatusChip";
import { FinalCta } from "./overlays/FinalCta";

/**
 * LX-1.1 — Development-only cinematic prototype. Same gating pattern
 * as /design-system and /design/landing-experience: 404s outside
 * development, never linked from public navigation, no real clinical
 * content, no secrets. Does not replace the production `/` landing —
 * see docs/landing/NOOR_LANDING_PRODUCTION_PLAN.md.
 *
 * Every scene's headline, supporting copy, and status label below is
 * real, server-rendered HTML present unconditionally — the fixed 3D
 * canvas (mounted client-side, only when motion is enabled) renders
 * BEHIND this content, it never replaces or duplicates it. See
 * docs/landing/NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md.
 */
export default function CinematicLandingPrototypePage() {
  if (process.env.NODE_ENV === "production") {
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
              className="flex items-center px-lg sm:px-xl"
              style={{ minHeight: `calc((${scene.end} - ${scene.start}) * var(--noor-cinematic-vh) * 100vh)` }}
            >
              <SceneSectionReveal>
                <div className="max-w-xl rounded-md p-lg" style={{ backgroundColor: "rgba(4,15,28,0.55)", backdropFilter: "blur(6px)" }}>
                  <SceneIllustration sceneKey={scene.key} />
                  <p className="mt-sm text-xs font-semibold uppercase tracking-wide text-white/60">
                    Scene {scene.id} of {SCENES.length}
                  </p>
                  <h2 id={`scene-${scene.id}-heading`} className="mt-xs text-2xl font-semibold text-white sm:text-3xl">
                    {scene.headline}
                  </h2>
                  <p className="mt-sm max-w-md text-base text-white/80">{scene.supportingCopy}</p>
                  <div className="mt-md">
                    <StatusChip status={scene.status} label={scene.statusLabel} />
                  </div>
                  {scene.key === "product-vision" ? (
                    <p className="mt-sm text-xs text-white/50">Synthetic demonstration — not clinical guidance.</p>
                  ) : null}
                  {scene.key === "reverse-traceability" ? (
                    <div className="mt-lg">
                      <FinalCta />
                    </div>
                  ) : null}
                </div>
              </SceneSectionReveal>
            </section>
          ))}
        </CinematicExperience>
      </ReducedMotionOverrideProvider>
    </main>
  );
}
