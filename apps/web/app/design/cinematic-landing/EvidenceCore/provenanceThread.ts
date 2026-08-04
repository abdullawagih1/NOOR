import * as THREE from "three";

/**
 * The one reusable "provenance connection" primitive (docs/landing/
 * NOOR_EVIDENCE_CORE_DESIGN.md §5) — a thin additive-blended tube swept
 * along a Catmull-Rom curve between two world points. Plain Three.js
 * (no framework wrapper) — see NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md
 * §"Why raw Three.js" for why this module isn't a React component.
 */
export function buildProvenanceThreadMesh(
  from: readonly [number, number, number],
  to: readonly [number, number, number],
  opacity = 0.7,
  color = "#078A88",
  radius = 0.012
): THREE.Mesh {
  const start = new THREE.Vector3(...from);
  const end = new THREE.Vector3(...to);
  const mid = start.clone().lerp(end, 0.5).add(new THREE.Vector3(0, 0.15, 0));
  const curve = new THREE.CatmullRomCurve3([start, mid, end]);
  const geometry = new THREE.TubeGeometry(curve, 24, radius, 6, false);
  const material = new THREE.MeshBasicMaterial({
    color,
    transparent: true,
    opacity,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
  });
  return new THREE.Mesh(geometry, material);
}
