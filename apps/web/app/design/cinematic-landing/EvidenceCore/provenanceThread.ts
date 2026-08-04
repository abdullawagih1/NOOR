import * as THREE from "three";

/**
 * The one reusable "provenance connection" primitive (docs/landing/
 * NOOR_EVIDENCE_CORE_DESIGN.md §5) — a thin additive-blended tube swept
 * along a Catmull-Rom curve between two world points. Plain Three.js
 * (no framework wrapper) — see NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md
 * §"Why raw Three.js" for why this module isn't a React component.
 *
 * LX-1.2 Scene 5 performance pass (mission §16): tube resolution
 * dropped from (24 tubular, 6 radial) to (14, 5) segments — real,
 * measured triangle-count reduction (~45% fewer triangles per thread)
 * with no visible difference at this camera distance for a thread
 * this thin. `sharedMaterial` lets callers building several threads
 * with identical color/opacity/radius (e.g. the 5 structured-block
 * threads in EvidenceCoreScene) reuse one material instance instead of
 * constructing an equivalent one per thread, cutting redundant
 * material/shader-program bindings during Scenes 4-5's busiest frames.
 */
export function buildProvenanceThreadMesh(
  from: readonly [number, number, number],
  to: readonly [number, number, number],
  opacity = 0.7,
  color = "#078A88",
  radius = 0.012,
  sharedMaterial?: THREE.MeshBasicMaterial
): THREE.Mesh {
  const start = new THREE.Vector3(...from);
  const end = new THREE.Vector3(...to);
  const mid = start.clone().lerp(end, 0.5).add(new THREE.Vector3(0, 0.15, 0));
  const curve = new THREE.CatmullRomCurve3([start, mid, end]);
  const geometry = new THREE.TubeGeometry(curve, 14, radius, 5, false);
  const material =
    sharedMaterial ??
    new THREE.MeshBasicMaterial({
      color,
      transparent: true,
      opacity,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
  return new THREE.Mesh(geometry, material);
}
