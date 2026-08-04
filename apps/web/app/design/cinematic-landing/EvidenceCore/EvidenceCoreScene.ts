import * as THREE from "three";
import { getTimelineState } from "../timelineStore";
import { activation } from "./easing";
import {
  SCENES,
  MOBILE_BREAKPOINT_PX,
  DESKTOP_CAMERA_PATHS,
  MOBILE_CAMERA_PATHS,
  TRACEABILITY_LAYERS,
  evaluateCameraPath,
} from "../sceneConfig";
import { buildProvenanceThreadMesh } from "./provenanceThread";
import type { QualityTier } from "../useQualityTier";

const SCENE2 = SCENES[1];
const SCENE3 = SCENES[2];
const SCENE4 = SCENES[3];
const SCENE5 = SCENES[4];
const SCENE6 = SCENES[5];
const SCENE7 = SCENES[6];

const ACCEPT_THRESHOLD = SCENE3.start + (SCENE3.end - SCENE3.start) * 0.68;
const DAMPING = 0.075;
const LAYER_COUNT = 5;

// N-spine geometry constants — see docs/landing/NOOR_EVIDENCE_CORE_DESIGN.md
// §"The NOOR-N spine" for the full rationale. Two page-layer towers +
// one diagonal evidence bridge = one persistent object, always the
// same silhouette, that both scene 1's source document AND the
// N-mark identity ARE — not two separate objects.
const TOWER_X = 0.62;
const TOWER_BOTTOM_Y = -0.85;
const TOWER_TOP_Y = 0.85;
const LEFT_TOWER_POS: readonly [number, number, number] = [-TOWER_X, 0, 0];
const RIGHT_TOWER_POS: readonly [number, number, number] = [TOWER_X, 0, 0];
const APERTURE_POS: readonly [number, number, number] = [0, 0.05, 0.35];

const VERIFICATION_NODES = [
  { key: "file-identity", pos: [-0.62, -0.95, 0.25] },
  { key: "sha256", pos: [-0.3, -1.05, 0.35] },
  { key: "tenant-boundary", pos: [0.02, -1.05, 0.35] },
  { key: "private-registration", pos: [0.32, -0.95, 0.25] },
] as const;

const BLOCKS = [
  { origin: [-0.35, 0.35, 0.5] as const, rest: [-0.2, 0.55, 1.25] as const, ranked: [0.55, 0.95, 2.35] as const, delay: 0, rankedScale: 1.2, candidate: true },
  { origin: [-0.15, 0.1, 0.5] as const, rest: [0.15, 0.15, 1.15] as const, ranked: [0.55, 0.35, 2.15] as const, delay: 0.04, rankedScale: 0.95, candidate: true },
  { origin: [-0.4, -0.15, 0.5] as const, rest: [0.05, -0.25, 1.05] as const, ranked: [0.55, -0.25, 1.95] as const, delay: 0.08, rankedScale: 0.78, candidate: true },
  { origin: [-0.1, -0.35, 0.5] as const, rest: [0.35, -0.55, 0.95] as const, ranked: [1.4, -0.5, 1.3] as const, delay: 0.12, rankedScale: 0.55, candidate: false },
  { origin: [-0.3, 0.55, 0.5] as const, rest: [0.4, 0.7, 0.9] as const, ranked: [1.4, 0.75, 1.25] as const, delay: 0.16, rankedScale: 0.5, candidate: false },
];
const RANKED_CANDIDATES = BLOCKS.filter((b) => b.candidate);
const TOP_CANDIDATE = RANKED_CANDIDATES[0].ranked;
const PANEL_POSITION = [TOWER_X + 0.3, 1.15, 1.6] as const;

const PENDING_KEY = new THREE.Color("#7FA6D4");
const VERIFIED_KEY = new THREE.Color("#1FD6D2");
const ACCEPTED_KEY = new THREE.Color("#2FE8B8");
const VISION_KEY = new THREE.Color("#D7F0F3");

function pageMarkingTexture(): THREE.CanvasTexture {
  const canvas = document.createElement("canvas");
  canvas.width = 160;
  canvas.height = 208;
  const ctx = canvas.getContext("2d");
  if (ctx) {
    ctx.fillStyle = "#0C3258";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.strokeStyle = "rgba(200, 228, 232, 0.4)";
    ctx.lineWidth = 2.5;
    for (let y = 20; y < canvas.height - 16; y += 14) {
      ctx.beginPath();
      ctx.moveTo(14, y);
      ctx.lineTo(canvas.width - 14 - Math.random() * 36, y);
      ctx.stroke();
    }
    ctx.strokeStyle = "rgba(9, 185, 147, 0.55)";
    ctx.lineWidth = 3;
    ctx.strokeRect(6, 6, canvas.width - 12, canvas.height - 12);
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.needsUpdate = true;
  return texture;
}

const PARTICLE_COUNTS: Record<QualityTier, number> = { high: 850, balanced: 380, static: 0 };

export interface ScreenAnchor {
  x: number;
  y: number;
  visible: boolean;
}

/**
 * The Evidence Core (docs/landing/NOOR_EVIDENCE_CORE_DESIGN.md), built
 * and updated with plain, imperative Three.js — not
 * @react-three/fiber. See NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md
 * §"Why raw Three.js" for the documented upstream incompatibility this
 * works around.
 *
 * LX-1.1.1 redesign: the document-stack and the "N-mark spine" are no
 * longer two separate ideas — the two towers ARE stacks of page
 * layers, connected by one diagonal "evidence bridge" thread and one
 * central "aperture" that plays a different narrative role in every
 * scene (review lock in Scene 3, query entry in Scene 5, workspace
 * anchor in Scene 6) — one persistent object throughout, per mission
 * §7.2, not a set of independently-arriving props.
 */
export class EvidenceCoreScene {
  readonly scene = new THREE.Scene();
  readonly camera: THREE.PerspectiveCamera;
  readonly renderer: THREE.WebGLRenderer;

  private readonly spineGroup = new THREE.Group();
  private readonly leftTowerPages: THREE.Mesh[] = [];
  private readonly rightTowerPages: THREE.Mesh[] = [];
  private readonly bridge: THREE.Mesh;
  private readonly aperture: THREE.Mesh;
  private readonly apertureShackle: THREE.Mesh;
  private readonly nodeMeshes: THREE.Mesh[] = [];
  private readonly verificationNodeMeshes: THREE.Mesh[] = [];
  private readonly invalidObject: THREE.Group;
  private readonly findingMarker: THREE.Mesh;
  private readonly pulseLight: THREE.PointLight;
  private readonly blocksGroup = new THREE.Group();
  private readonly blockMeshes: THREE.Group[] = [];
  private readonly beam: THREE.Mesh;
  private readonly panelGroup = new THREE.Group();
  private readonly panel: THREE.Mesh;
  private readonly traceabilityMarker: THREE.Mesh;
  private particles: THREE.Points | null = null;
  private particlesVisible = false;
  private currentTraceabilityLabel = "";
  private readonly keyLight: THREE.DirectionalLight;
  private readonly rimLight: THREE.DirectionalLight;
  private readonly ambientLight: THREE.HemisphereLight;
  private readonly targetPosition: THREE.Vector3;
  private readonly targetLookAt: THREE.Vector3;
  private readonly currentLookAt: THREE.Vector3;
  private qualityTier: QualityTier;
  private disposed = false;
  private readonly projectionVec = new THREE.Vector3();

  constructor(canvas: HTMLCanvasElement, qualityTier: QualityTier) {
    this.qualityTier = qualityTier;
    this.scene.background = new THREE.Color("#050F1E");
    this.scene.fog = new THREE.Fog(0x050f1e, 5, 14);

    this.camera = new THREE.PerspectiveCamera(38, canvas.clientWidth / Math.max(1, canvas.clientHeight), 0.1, 30);
    this.camera.position.set(0, 0.15, 4.6);
    this.targetPosition = this.camera.position.clone();
    this.targetLookAt = new THREE.Vector3(0, 0.05, 0);
    this.currentLookAt = this.targetLookAt.clone();

    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: qualityTier === "high",
      alpha: false,
      powerPreference: "high-performance",
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, qualityTier === "high" ? 2 : 1.5));

    // Lighting — brighter and higher-contrast than LX-1.1's first pass
    // (user feedback: "core too small and too dark"). See
    // docs/landing/NOOR_CINEMATIC_ART_DIRECTION.md §Lighting.
    this.ambientLight = new THREE.HemisphereLight("#12406B", "#050F1E", 0.85);
    this.keyLight = new THREE.DirectionalLight("#7FA6D4", 1.9);
    this.keyLight.position.set(2.2, 3.2, 4.2);
    this.rimLight = new THREE.DirectionalLight("#1FD6D2", 0.85);
    this.rimLight.position.set(-3, 1.2, -2);
    const fillLight = new THREE.PointLight("#D7F0F3", 0.5, 8);
    fillLight.position.set(0, 0.5, 3);
    this.scene.add(this.ambientLight, this.keyLight, this.rimLight, fillLight);

    const texture = pageMarkingTexture();
    const pageGeometry = new THREE.PlaneGeometry(0.92, 1.7);
    const buildTower = (baseX: number, target: THREE.Mesh[]) => {
      for (let i = 0; i < LAYER_COUNT; i++) {
        const mesh = new THREE.Mesh(
          pageGeometry,
          new THREE.MeshStandardMaterial({ map: texture, roughness: 0.55, metalness: 0.08, side: THREE.DoubleSide, emissive: "#0A2A4A", emissiveIntensity: 0.15 })
        );
        mesh.position.set(baseX, 0, i * 0.05);
        mesh.rotation.z = (i % 2 === 0 ? 1 : -1) * 0.01;
        this.spineGroup.add(mesh);
        target.push(mesh);
      }
    };
    buildTower(LEFT_TOWER_POS[0], this.leftTowerPages);
    buildTower(RIGHT_TOWER_POS[0], this.rightTowerPages);

    // The evidence bridge — the N's diagonal stroke, built from the
    // same reusable provenance-thread primitive used everywhere else,
    // so the spine's diagonal and every later "provenance line" read
    // as the same visual language.
    this.bridge = buildProvenanceThreadMesh(
      [LEFT_TOWER_POS[0], TOWER_BOTTOM_Y, 0.1],
      [RIGHT_TOWER_POS[0], TOWER_TOP_Y, 0.1],
      0.85,
      "#1FD6D2",
      0.022
    );
    this.spineGroup.add(this.bridge);

    // The aperture — the N's controlled central clinical-data aperture
    // (mission §7.1). Plays the review lock (Scene 3), the query entry
    // (Scene 5), and the workspace anchor (Scene 6) — one recurring
    // object, not three different props.
    this.aperture = new THREE.Mesh(
      new THREE.TorusGeometry(0.24, 0.028, 20, 48),
      new THREE.MeshStandardMaterial({ color: "#D7F0F3", emissive: PENDING_KEY, emissiveIntensity: 0.6, roughness: 0.3, metalness: 0.3 })
    );
    this.aperture.position.set(...APERTURE_POS);
    this.apertureShackle = new THREE.Mesh(
      new THREE.TorusGeometry(0.1, 0.02, 12, 32, Math.PI),
      new THREE.MeshStandardMaterial({ color: "#D7F0F3", roughness: 0.3, metalness: 0.3 })
    );
    this.apertureShackle.position.set(APERTURE_POS[0], APERTURE_POS[1] + 0.14, APERTURE_POS[2]);
    this.apertureShackle.rotation.x = Math.PI / 2;
    this.pulseLight = new THREE.PointLight("#2FE8B8", 0, 3.2);
    this.pulseLight.position.set(...APERTURE_POS);
    this.spineGroup.add(this.aperture, this.apertureShackle, this.pulseLight);

    // Verified nodes embedded in the geometry (mission §7.2) — light up
    // at three real narrative moments: source registered, review
    // accepted, ranking complete.
    for (const pos of [LEFT_TOWER_POS, APERTURE_POS, RIGHT_TOWER_POS] as const) {
      const node = new THREE.Mesh(
        new THREE.IcosahedronGeometry(0.045, 1),
        new THREE.MeshBasicMaterial({ color: "#2FE8B8", transparent: true, opacity: 0 })
      );
      node.position.set(pos[0], pos[1] - 0.02, pos[2] + 0.4);
      this.spineGroup.add(node);
      this.nodeMeshes.push(node);
    }

    this.scene.add(this.spineGroup);

    // Scene 2 — 4 sequential verification nodes + invalid-path object.
    for (const node of VERIFICATION_NODES) {
      const mesh = new THREE.Mesh(
        new THREE.TorusGeometry(0.07, 0.014, 10, 28),
        new THREE.MeshStandardMaterial({ color: "#7FA6D4", emissive: PENDING_KEY, emissiveIntensity: 0.4, transparent: true, opacity: 0 })
      );
      mesh.position.set(node.pos[0], node.pos[1], node.pos[2]);
      mesh.rotation.x = Math.PI / 2;
      this.scene.add(mesh);
      this.verificationNodeMeshes.push(mesh);
    }
    this.invalidObject = new THREE.Group();
    const invalidPlate = new THREE.Mesh(
      new THREE.BoxGeometry(0.5, 0.66, 0.06),
      new THREE.MeshStandardMaterial({ color: "#6E9DA8", transparent: true, opacity: 0.7, roughness: 0.8 })
    );
    this.invalidObject.add(invalidPlate);
    this.invalidObject.position.set(1.9, -0.3, 0.6);
    this.invalidObject.scale.setScalar(0.5);
    this.scene.add(this.invalidObject);

    // Scene 3 — finding marker on the left tower's front page.
    this.findingMarker = new THREE.Mesh(
      new THREE.PlaneGeometry(0.45, 0.2),
      new THREE.MeshBasicMaterial({ color: "#7FA6D4", transparent: true, opacity: 0 })
    );
    this.findingMarker.position.set(LEFT_TOWER_POS[0] + 0.1, 0.25, (LAYER_COUNT - 1) * 0.05 + 0.02);
    this.scene.add(this.findingMarker);

    // Scenes 4–5 — structured blocks + provenance threads + ranking.
    for (const block of BLOCKS) {
      const group = new THREE.Group();
      group.position.set(block.origin[0], block.origin[1], block.origin[2]);
      const mesh = new THREE.Mesh(
        new THREE.BoxGeometry(0.26, 0.19, 0.055),
        new THREE.MeshStandardMaterial({ color: "#5BE0DC", roughness: 0.45, emissive: "#0E4A48", emissiveIntensity: 0.3 })
      );
      group.add(mesh);
      this.blocksGroup.add(group);
      this.blockMeshes.push(group);
      this.blocksGroup.add(buildProvenanceThreadMesh(block.origin, block.rest, 0.65, "#1FD6D2", 0.01));
    }
    this.scene.add(this.blocksGroup);

    this.beam = new THREE.Mesh(
      new THREE.PlaneGeometry(0.07, 1.4),
      new THREE.MeshBasicMaterial({ color: "#D7F0F3", transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide })
    );
    this.beam.rotation.x = Math.PI / 2;
    this.scene.add(this.beam);

    this.panel = new THREE.Mesh(
      new THREE.PlaneGeometry(1.35, 0.8),
      new THREE.MeshPhysicalMaterial({ color: "#D7F0F3", transparent: true, opacity: 0, roughness: 0.12, transmission: 0.55, thickness: 0.1, side: THREE.DoubleSide })
    );
    this.panelGroup.add(this.panel);
    this.panelGroup.add(
      buildProvenanceThreadMesh(
        [0, 0, 0],
        [APERTURE_POS[0] - PANEL_POSITION[0], APERTURE_POS[1] - PANEL_POSITION[1], APERTURE_POS[2] - PANEL_POSITION[2]],
        0.5,
        "#D7F0F3",
        0.01
      )
    );
    this.panelGroup.position.set(...PANEL_POSITION);
    this.scene.add(this.panelGroup);

    // Scene 7 — the traceability layer marker: one bright ring that
    // moves between the six TRACEABILITY_LAYERS anchor positions,
    // giving each reverse-traversal stop a distinct, readable visual
    // focus independent of camera position alone (mission §17).
    this.traceabilityMarker = new THREE.Mesh(
      new THREE.RingGeometry(0.12, 0.15, 32),
      new THREE.MeshBasicMaterial({ color: "#2FE8B8", transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide })
    );
    this.scene.add(this.traceabilityMarker);

    this.setParticleTier(qualityTier);
  }

  setQualityTier(tier: QualityTier) {
    if (tier === this.qualityTier) return;
    this.qualityTier = tier;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, tier === "high" ? 2 : 1.5));
    this.setParticleTier(tier);
  }

  private setParticleTier(tier: QualityTier) {
    if (this.particles) {
      this.scene.remove(this.particles);
      this.particles.geometry.dispose();
      (this.particles.material as THREE.Material).dispose();
      this.particles = null;
    }
    const count = PARTICLE_COUNTS[tier];
    if (count <= 0) return;
    const positions = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
      const theta = Math.random() * Math.PI * 2;
      const r = 2.2 * (0.4 + Math.random() * 0.6);
      const y = (Math.random() - 0.5) * 1.8;
      positions[i * 3] = Math.cos(theta) * r;
      positions[i * 3 + 1] = y;
      positions[i * 3 + 2] = Math.sin(theta) * r * 0.6;
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    const material = new THREE.PointsMaterial({
      size: 0.028,
      color: "#1FD6D2",
      transparent: true,
      opacity: 0.5,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      sizeAttenuation: true,
    });
    this.particles = new THREE.Points(geometry, material);
    this.particles.visible = this.particlesVisible;
    this.scene.add(this.particles);
  }

  resize(width: number, height: number) {
    this.camera.aspect = width / Math.max(1, height);
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height, false);
  }

  /** Called once per animation frame by CinematicCanvas's RAF loop. */
  update(deltaSeconds: number) {
    const { progress } = getTimelineState();
    this.updateCamera();
    this.updateSpineNodes(progress);
    this.updateVerification(progress);
    this.updateReviewGate(progress, deltaSeconds);
    this.updateBlocks(progress);
    this.updateBeam(progress);
    this.updatePanel(progress);
    this.updateTraceabilityMarker(progress);
    this.updateLighting(progress);
    this.updateParticles(progress, deltaSeconds);
    this.renderer.render(this.scene, this.camera);
  }

  private updateCamera() {
    const { sceneIndex, sceneLocalProgress } = getTimelineState();
    const isMobile = window.innerWidth < MOBILE_BREAKPOINT_PX;
    const paths = isMobile ? MOBILE_CAMERA_PATHS : DESKTOP_CAMERA_PATHS;
    const sceneId = sceneIndex + 1;
    const path = paths[sceneId] ?? paths[1];
    const keyframe = evaluateCameraPath(path, sceneLocalProgress);

    this.targetPosition.set(...keyframe.position);
    this.targetLookAt.set(...keyframe.target);
    this.camera.position.lerp(this.targetPosition, DAMPING);
    this.currentLookAt.lerp(this.targetLookAt, DAMPING);
    this.camera.lookAt(this.currentLookAt);
    this.camera.fov += (keyframe.fov - this.camera.fov) * DAMPING;
    this.camera.updateProjectionMatrix();
  }

  /** Source-registered node (left tower base) lights on Scene 1 entry. */
  private updateSpineNodes(progress: number) {
    const sourceLit = activation(progress, 0, 0.06);
    const reviewLit = activation(progress, ACCEPT_THRESHOLD, ACCEPT_THRESHOLD + 0.02);
    const rankLit = activation(progress, SCENE5.end - 0.03, SCENE5.end);
    const opacities = [sourceLit, reviewLit, rankLit];
    this.nodeMeshes.forEach((mesh, i) => {
      (mesh.material as THREE.MeshBasicMaterial).opacity = opacities[i];
      mesh.scale.setScalar(0.8 + opacities[i] * 0.6);
    });

    const spread = 1 - activation(progress, 0, 0.08);
    [...this.leftTowerPages, ...this.rightTowerPages].forEach((mesh, index) => {
      const layerIndex = index % LAYER_COUNT;
      mesh.position.z = layerIndex * 0.05 + spread * (layerIndex - LAYER_COUNT / 2) * 0.35;
    });
  }

  private updateVerification(progress: number) {
    const invalidApproach = activation(progress, SCENE2.start + 0.02, SCENE2.start + 0.5);
    const invalidRejected = activation(progress, SCENE2.start + 0.45, SCENE2.start + 0.55);
    const stillActive = activation(progress, SCENE2.start, SCENE2.end + 0.1);

    this.verificationNodeMeshes.forEach((mesh, index) => {
      const nodeStart = SCENE2.start + 0.03 + index * 0.045;
      const lit = activation(progress, nodeStart, nodeStart + 0.03);
      const material = mesh.material as THREE.MeshStandardMaterial;
      material.opacity = lit * (0.85 * stillActive + 0.15);
      material.color.copy(PENDING_KEY).lerp(VERIFIED_KEY, lit);
      material.emissive.copy(PENDING_KEY).lerp(VERIFIED_KEY, lit);
      material.emissiveIntensity = 0.4 + lit * 0.8;
      mesh.visible = stillActive > 0.01;
    });

    const stoppedX = 0.85;
    const startX = 1.9;
    this.invalidObject.position.x = startX - (startX - stoppedX) * Math.min(1, invalidApproach);
    this.invalidObject.visible = invalidApproach > 0.01 && progress < SCENE2.end + 0.05;
    const invalidMaterial = (this.invalidObject.children[0] as THREE.Mesh).material as THREE.MeshStandardMaterial;
    invalidMaterial.color.set(invalidRejected > 0.5 ? "#C4574A" : "#6E9DA8");
    invalidMaterial.opacity = 0.7 - invalidRejected * 0.3;
  }

  private updateReviewGate(progress: number, deltaSeconds: number) {
    const detach = activation(progress, SCENE3.start, SCENE3.start + 0.1);
    const accepted = activation(progress, ACCEPT_THRESHOLD, ACCEPT_THRESHOLD + 0.02);
    const stillRelevant = activation(progress, SCENE3.start - 0.02, 1);

    this.findingMarker.visible = stillRelevant > 0.01;
    const findingMaterial = this.findingMarker.material as THREE.MeshBasicMaterial;
    findingMaterial.opacity = detach * 0.7 * (1 - accepted);

    this.apertureShackle.rotation.z = accepted * (Math.PI * 0.55);
    this.apertureShackle.position.y = APERTURE_POS[1] + 0.14 + accepted * 0.1;

    const apertureMaterial = this.aperture.material as THREE.MeshStandardMaterial;
    apertureMaterial.emissive.copy(PENDING_KEY).lerp(ACCEPTED_KEY, accepted);
    apertureMaterial.emissiveIntensity = 0.6 + accepted * 1.2;

    const pulseAge = Math.min(1, Math.max(0, (progress - ACCEPT_THRESHOLD) / 0.05));
    const pulseVisible = progress >= ACCEPT_THRESHOLD && pulseAge < 1;
    this.pulseLight.intensity = pulseVisible ? (1 - pulseAge) * 6 : 0;
    this.pulseLight.position.x = APERTURE_POS[0] + (pulseVisible ? pulseAge * TOWER_X * 1.3 : 0);
    void deltaSeconds;
  }

  private updateBlocks(progress: number) {
    const overallActive = activation(progress, SCENE4.start, SCENE7.start);
    this.blocksGroup.visible = overallActive > 0.01;

    BLOCKS.forEach((block, index) => {
      const group = this.blockMeshes[index];
      const toRest = activation(progress, SCENE4.start + block.delay, SCENE4.start + block.delay + 0.09);
      const toRanked = activation(progress, SCENE5.start + block.delay, SCENE5.start + block.delay + 0.11);

      const midX = block.origin[0] + (block.rest[0] - block.origin[0]) * toRest;
      const midY = block.origin[1] + (block.rest[1] - block.origin[1]) * toRest;
      const midZ = block.origin[2] + (block.rest[2] - block.origin[2]) * toRest;

      group.position.set(
        midX + (block.ranked[0] - midX) * toRanked,
        midY + (block.ranked[1] - midY) * toRanked,
        midZ + (block.ranked[2] - midZ) * toRanked
      );
      const restScale = 0.45 + toRest * 0.55;
      group.scale.setScalar(restScale + (block.rankedScale - restScale) * toRanked);
    });
  }

  private updateBeam(progress: number) {
    const arrive = activation(progress, SCENE5.start + 0.02, SCENE5.start + 0.16);
    const stillActive = activation(progress, SCENE5.start, SCENE7.start);
    this.beam.visible = stillActive > 0.01;
    const material = this.beam.material as THREE.MeshBasicMaterial;
    material.opacity = 0.5 * arrive;
    const startZ = 6.2;
    const endZ = APERTURE_POS[2];
    this.beam.position.set(APERTURE_POS[0], APERTURE_POS[1], startZ + (endZ - startZ) * arrive);
  }

  private updatePanel(progress: number) {
    const condense = activation(progress, SCENE6.start, SCENE6.start + 0.1);
    const stillActive = activation(progress, SCENE6.start, SCENE7.start + 0.05);
    this.panelGroup.visible = stillActive > 0.01;
    this.panelGroup.scale.setScalar(0.5 + condense * 0.5);
    const material = this.panel.material as THREE.MeshPhysicalMaterial;
    material.opacity = 0.25 + condense * 0.35;
  }

  /** Moves the reverse-traceability marker between the 6 layer anchors
   * as Scene 7's local progress advances (mission §17's "six visibly
   * distinct spatial layers"). */
  private updateTraceabilityMarker(progress: number) {
    if (progress < SCENE7.start) {
      this.traceabilityMarker.visible = false;
      return;
    }
    const local = (progress - SCENE7.start) / (SCENE7.end - SCENE7.start);
    let layerIndex = 0;
    for (let i = 0; i < TRACEABILITY_LAYERS.length; i++) {
      if (local >= TRACEABILITY_LAYERS[i].atProgress) layerIndex = i;
    }
    const anchors: Record<string, readonly [number, number, number]> = {
      "intelligence-statement": PANEL_POSITION,
      "supporting-evidence": TOP_CANDIDATE,
      "retrieved-chunk": BLOCKS[0].rest,
      "source-span": [LEFT_TOWER_POS[0] + 0.1, 0.25, (LAYER_COUNT - 1) * 0.05 + 0.02],
      "original-page": [APERTURE_POS[0], APERTURE_POS[1], APERTURE_POS[2]],
      "trusted-guideline": LEFT_TOWER_POS,
    };
    const anchor = anchors[TRACEABILITY_LAYERS[layerIndex].key] ?? LEFT_TOWER_POS;
    this.traceabilityMarker.position.set(anchor[0], anchor[1] + 0.05, anchor[2] + 0.5);
    this.traceabilityMarker.visible = local < 0.98;
    const material = this.traceabilityMarker.material as THREE.MeshBasicMaterial;
    material.opacity = 0.85;
    this.traceabilityMarker.lookAt(this.camera.position);
    this.currentTraceabilityLabel = TRACEABILITY_LAYERS[layerIndex].label;
  }

  getCurrentTraceabilityLabel(): string {
    return this.currentTraceabilityLabel;
  }

  private updateLighting(progress: number) {
    const toVerified = activation(progress, SCENE2.start, SCENE2.end);
    const toAccepted = activation(progress, SCENE3.start, SCENE3.end);
    const toVision = activation(progress, SCENE6.start, SCENE6.end);
    const color = PENDING_KEY.clone().lerp(VERIFIED_KEY, toVerified).lerp(ACCEPTED_KEY, toAccepted).lerp(VISION_KEY, toVision);
    this.keyLight.color.copy(color);

    const warm = activation(progress, SCENE7.start, 1);
    this.ambientLight.intensity = 0.85 + warm * 0.25;
    this.rimLight.intensity = 0.85 + warm * 0.3;
  }

  private updateParticles(progress: number, deltaSeconds: number) {
    const shouldShow = (progress >= SCENE5.start - 0.01 && progress < SCENE6.end) || progress >= SCENE7.start;
    this.particlesVisible = shouldShow;
    if (this.particles) {
      this.particles.visible = shouldShow;
      if (shouldShow) this.particles.rotation.y += deltaSeconds * 0.025;
    }
  }

  /** Screen-space anchors for DOM overlays (rank badges, traceability
   * layer label) — projected once per frame, read by CinematicCanvas
   * and written directly to ref'd DOM nodes (no React state per
   * frame), per mission §26 "DOM anchors" guidance. */
  getScreenAnchors(): Record<string, ScreenAnchor> {
    const anchors: Record<string, ScreenAnchor> = {};
    const project = (worldPos: readonly [number, number, number], zOffset = 0.5): ScreenAnchor => {
      this.projectionVec.set(worldPos[0], worldPos[1], worldPos[2] + zOffset);
      this.projectionVec.project(this.camera);
      const visible = this.projectionVec.z < 1 && Math.abs(this.projectionVec.x) < 1.15 && Math.abs(this.projectionVec.y) < 1.15;
      return { x: (this.projectionVec.x * 0.5 + 0.5) * 100, y: (1 - (this.projectionVec.y * 0.5 + 0.5)) * 100, visible };
    };
    const { progress } = getTimelineState();
    const rankVisible = progress >= SCENE5.start && progress < SCENE7.start;
    RANKED_CANDIDATES.forEach((block, index) => {
      const anchor = project(this.blockMeshes[BLOCKS.indexOf(block)].position.toArray() as [number, number, number], 0.15);
      anchors[`rank-${index + 1}`] = { ...anchor, visible: anchor.visible && rankVisible };
    });
    if (progress >= SCENE7.start) {
      anchors["traceability-label"] = project(this.traceabilityMarker.position.toArray() as [number, number, number], 0.1);
    } else {
      anchors["traceability-label"] = { x: 50, y: 50, visible: false };
    }
    return anchors;
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.scene.traverse((object: THREE.Object3D) => {
      if (object instanceof THREE.Mesh || object instanceof THREE.Points) {
        object.geometry.dispose();
        const material = object.material;
        if (Array.isArray(material)) material.forEach((m) => m.dispose());
        else material.dispose();
      }
    });
    this.renderer.dispose();
  }
}
