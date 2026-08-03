import { notFound } from "next/navigation";
import { PageHeader } from "@noor/ui";
import { ReducedMotionOverrideProvider } from "./useEffectiveReducedMotion";
import { HeroEvidenceFlowScene } from "./scenes/HeroEvidenceFlowScene";
import { SourceVerificationScene } from "./scenes/SourceVerificationScene";
import { HumanReviewScene } from "./scenes/HumanReviewScene";
import { StructuredKnowledgeScene } from "./scenes/StructuredKnowledgeScene";
import { RetrievalScene } from "./scenes/RetrievalScene";
import { TraceabilityTimelineScene } from "./scenes/TraceabilityTimelineScene";
import { RtlStructuralPreview } from "./scenes/RtlStructuralPreview";

/**
 * LX-1.0 — Development-only landing motion prototype gallery. Same
 * gating pattern as apps/web/app/design-system/page.tsx: 404s outside
 * development, so it is never reachable in a Preview/Production
 * deployment. Renders synthetic, non-clinical mock content only — no
 * live query, no auth bypass, no secret ever touches this page.
 *
 * This route validates narrative and motion feasibility for the future
 * `/` landing redesign (see docs/landing/NOOR_LANDING_PRODUCTION_PLAN.md,
 * phase LX-1.2). It does not replace the production landing page.
 */
export default function LandingExperiencePrototypePage() {
  if (process.env.NODE_ENV === "production") {
    notFound();
  }

  return (
    <main className="mx-auto flex max-w-5xl flex-col gap-xxl p-xl">
      <PageHeader
        eyebrow="Internal — development only — LX-1.0"
        title="Noor Landing Experience — Motion Prototype Gallery"
        description="Isolated technical prototypes for the future immersive landing narrative. This route 404s in production builds and is not linked from any public page. See docs/landing/ for the full narrative, storyboard, and motion system this gallery validates."
      />

      <ReducedMotionOverrideProvider>
        <div className="flex flex-col gap-xl">
          <HeroEvidenceFlowScene />
          <SourceVerificationScene />
          <HumanReviewScene />
          <StructuredKnowledgeScene />
          <RetrievalScene />
          <TraceabilityTimelineScene />
          <RtlStructuralPreview />
        </div>
      </ReducedMotionOverrideProvider>
    </main>
  );
}
