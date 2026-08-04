/**
 * Lightweight branded poster (mission §31) — shown before WebGL
 * initializes, and permanently in the reduced-motion/mobile-static/
 * WebGL-unavailable paths. A CSS gradient built from the same brand
 * tokens as the 3D environment, not a screenshot image, so it costs
 * nothing to load and never causes a layout shift when the canvas
 * (if any) mounts on top of it.
 */
export function StaticPoster() {
  return (
    <div
      className="h-full w-full"
      style={{
        background:
          "radial-gradient(circle at 50% 35%, #0A2A4A 0%, #040F1C 55%, #020A14 100%)",
      }}
    />
  );
}
