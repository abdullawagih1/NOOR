# NOOR Cinematic Production Architecture

Status: **LX-1.2 — Complete.** Records how the approved LX-1.1.1 cinematic prototype was extracted into a production-integrated component and wired into the public `/` route.

## Root route architecture

```
apps/web/app/page.tsx  (Server Component, no "use client")
  ├─ getPublicLandingExperience()      → "legacy" | "cinematic" (server-only, fail-closed)
  ├─ resolveLandingCta()                → { href, label } (reads the request's session cookie)
  └─ renders exactly ONE of:
       LegacyPublicLanding(cta)         (apps/web/app/LegacyPublicLanding.tsx)
       CinematicPublicLanding(cta)      (apps/web/app/design/cinematic-landing/CinematicPublicLanding.tsx)
```

Both branches are statically imported at the top of `page.tsx` — this is fine for bundle isolation because Next.js's App Router only ships to the browser the Client Component chunks actually *referenced in the RSC payload for a given response*, not everything statically imported into a Server Component's module graph. Confirmed directly (not assumed) this mission: a real production build's served HTML for `/` never references `three`'s chunk file in either branch, and never references it at all outside `/design/cinematic-landing`'s own bundle — see the Route/Bundle Isolation section below.

## Server/client boundaries

**Server (this mission's new/changed code):**
- `getPublicLandingExperience()` — pure env-var read.
- `resolveLandingCta()` — one Supabase auth check (`getAuthenticatedContext()`) + `resolvePostLoginDestination()`.
- `LegacyPublicLanding.tsx` — plain server JSX, extracted verbatim from the pre-LX-1.2 `page.tsx`.
- `CinematicPublicLanding.tsx` — plain server JSX, extracted verbatim from the pre-LX-1.2 `design/cinematic-landing/page.tsx` body (the 7-scene section markup, headings, status chips, illustrations).
- `apps/web/app/robots.ts`, `apps/web/app/sitemap.ts` — Next.js Metadata Route Handlers, resolved server-side per Next.js convention.

**Client (unchanged from LX-1.1.1, only re-parented to take a `cta` prop):**
- `CinematicExperience.tsx` — quality tier, reduced-motion, WebGL detection, dynamic-imports `CinematicCanvas`.
- `CinematicCanvas.tsx` — the Three.js RAF loop, dynamically imported (`next/dynamic`, `ssr:false`) — this is the actual isolation boundary for `three`/GSAP.
- `overlays/CinematicNav.tsx`, `overlays/FinalCta.tsx` — now receive `cta: PublicLandingCta` as a prop instead of hardcoding `href="/login"`.

## Why `CinematicPublicLanding.tsx` stays inside `app/design/cinematic-landing/`

The mission's suggested component list (§11) implies a dedicated production directory. This mission deliberately kept the extraction inside the existing `cinematic-landing/` directory instead, because every sibling module the extracted markup and its descendants import (`./sceneConfig`, `./CinematicExperience`, `./EvidenceCore/*`, `./overlays/*`, half a dozen `./use*` hooks) is a **relative** import rooted there. Moving the file to a new top-level directory would require rewriting every one of those import paths across roughly 20 already-verified files for zero functional benefit — the actual requirement ("production components, not imports from a dev-only page file") is satisfied by extracting the markup out of the *page file* into a real, reusable component, regardless of which folder that component physically lives in. Both the public root route and the internal `/design/cinematic-landing` route import the exact same `CinematicPublicLanding` component; neither duplicates its markup.

## `/design/cinematic-landing` route today

```tsx
export default async function CinematicLandingPrototypePage() {
  const isProduction = process.env.NODE_ENV === "production";
  const previewEnabled = process.env.NOOR_CINEMATIC_PREVIEW_ENABLED === "true";
  if (isProduction && !previewEnabled) notFound();

  const cta = await resolveLandingCta();
  return <CinematicPublicLanding cta={cta} />;
}
```

Now a thin gate wrapper (LX-1.1.1's Preview-only 404 gate, unchanged) around the same production component the public root can render. `?debug=1` (handled entirely inside `CinematicExperience`, unchanged) still only ever affects this internal route — the public root route never passes or reads a debug flag.

## Canvas loading (unchanged from LX-1.1.1)

Static poster → dynamically-imported canvas → crossfade on first successful render → error boundary falls back to the static poster permanently on failure. No changes were made to this sequence this mission; it was already production-grade. See `NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md` (LX-1.1) and the reduced-motion/fallback docs (LX-1.1.1) for the full original design.

## Error containment

`CanvasErrorBoundary` (a React error boundary, catches render-time throws from the canvas subtree) + a manual `try/catch` around `new EvidenceCoreScene(...)` inside `CinematicCanvas`'s mount effect (catches synchronous WebGL construction failures, which React error boundaries cannot catch since they occur inside a `useEffect`, not during render) + a `webglcontextlost` listener — all three converge on the same `onContextLost()` callback, which flips `canvasFailed=true` in `CinematicExperience`, permanently switching that mount to the static poster. Reviewed this mission (not re-implemented — LX-1.1.1's design already satisfied every mission §32 requirement): nav/CTA render outside the canvas boundary and are never affected by a canvas failure; there is no redirect logic anywhere near the canvas, so no redirect-loop risk exists; the fallback never reruns the failed constructor, so there is no repeated-initialization risk.

## Bundle boundaries — verified this mission, not assumed

Confirmed directly against a real production build (`NOOR_PUBLIC_LANDING_EXPERIENCE=legacy`/`cinematic`, `next build && next start`):

| Check | Method | Result |
| --- | --- | --- |
| `three`'s compiled chunk never appears in `/`'s served HTML (either flag value) | `curl` the real response, grep for the chunk's known filename | 0 references in both |
| `three`'s compiled chunk never appears in `/login`'s served HTML | same | 0 references |
| `/` genuinely renders the selected branch | grep the response for a scene-1-only string (cinematic) vs. the legacy `<h1>` text | Correct branch confirmed present/absent in each response |
| `three` reaches the DOM only when cinematic + motion-active | live GPU/diagnostics readout via `window.__noorCinematicDiagnostics` at real scroll checkpoints | Non-zero draw calls/triangles only once scrolled into the cinematic experience |

No cinematic client module is imported by `apps/web/app/layout.tsx`, `PublicShell.tsx`, `packages/ui`, `AuthShell.tsx`, or any workspace layout — confirmed by the same static-import audit performed at the start of this mission.
