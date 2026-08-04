# NOOR Cinematic Fallback Strategy

Status: **LX-1.1 — In Progress**

## When the static fallback renders

`StaticFallbackExperience` (DOM/SVG, no WebGL) renders whenever any of
the following is true, checked in this order:

1. `prefers-reduced-motion: reduce` (real system preference, or the visible reviewer-facing "Reduce motion" toggle — see below).
2. `useQualityTier()` resolves to `'static'` on first mount (very small viewport, or a coarse low-power signal — see Technical Architecture §Quality tiers).
3. The one-time FPS probe (run only if tier 1/2 didn't already decide `static`) reports sustained sub-30fps even at the `balanced` tier.
4. `WebGLRenderingContext`/`WebGL2RenderingContext` construction throws, or `@react-three/fiber`'s `<Canvas>` reports a context-loss/initialization error (caught by an error boundary — see §Error handling below).
5. The dynamic `import("./CinematicCanvas")` itself rejects (network failure, blocked script, etc.).

## What the static fallback contains

A single vertically-stacked sequence of 7 sections, one per scene, each
containing:
- The same headline, supporting copy, and status label as the motion-enabled version — copied from the same content source, never a separately-maintained shorter copy.
- A lightweight inline SVG illustration for that scene's key visual beat (e.g., Scene 1's layered document icon, Scene 3's lock/unlock glyph, Scene 7's reverse-arrow breadcrumb) — simple, brand-token-colored shapes, not a rendered screenshot of the 3D scene.
- Standard `whileInView` Framer Motion entrance (opacity + small y-offset), respecting reduced motion by rendering the resolved end-state immediately when that's the active reason for being in this path.

Both CTAs appear in their normal position at the end. Nothing is
omitted, shortened, or marked "preview only" — this is a complete,
independently-shippable version of the page.

## Visible reduced-motion control

A small, accessible toggle ("Reduce motion") is present in the minimal
nav on the cinematic route (mission §29's explicit allowance: "Provide
a visible 'Reduce motion' control only if it fits the public experience
and is accessible"). It **never overrides the OS preference by
default** — it only ever offers to go *further* (force static even
when the OS preference is "no preference"); if the OS already requests
reduced motion, the toggle is hidden entirely (there is nothing left
for it to offer).

## Error handling (mission §43)

A React error boundary wraps `CinematicCanvas` specifically. On any
caught error (Three.js init failure, shader compile failure, canvas
context loss, resize error), the boundary:
- Logs a safe, generic development diagnostic (`console.warn` with the
  error's `name` only, gated behind `NODE_ENV !== "production"` — never
  a raw stack trace surfaced to the user, never in production logs).
- Renders `StaticFallbackExperience` in place of the failed canvas,
  automatically, with no user action required.

Context loss specifically is also handled via the `webglcontextlost`
event (calling `event.preventDefault()` and falling back rather than
letting the browser's default "black canvas" behavior show).

## WebGL-unavailable simulation

Verified directly (not assumed) by launching a real Playwright browser
context with `--disable-gpu`/WebGL disabled via Chromium launch args
and confirming: the page does not crash, the poster/static content
renders, every headline and CTA is present, and the page passes the
same accessibility scan as the motion-enabled path. See the
verification report for the actual command and result.
