import * as THREE from "three";
import { getTimelineState } from "../timelineStore";
import { activation } from "./easing";
import { SCENES, MOBILE_BREAKPOINT_PX, DESKTOP_CAMERA_PATHS, MOBILE_CAMERA_PATHS, evaluateCameraPath } from "../sceneConfig";
import { buildProvenanceThreadMesh } from "./provenanceThread";
import type { QualityTier } from "../useQualityTier";

const SCENE2 = SCENES[1];
const SCENE3 = SCENES[2];
const SCENE4 = SCENES[3];
const SCENE5 = SCENES[4];
const SCENE6 = SCENES[5];

const ACCEPT_THRESHOLD = SCENE3.start + (SCENE3.end - SCENE3.start) * 0.72;
const DAMPING = 0.08;
const LAYER_COUNT = 5;

const BLOCKS = [
  { origin: [0.05, 0.55, 0.86] as const, rest: [1.35, 0.55, 1.15] as const, ranked: [1.0, 0.9, 2.2] as const, delay: 0, rankedScale: 1.15 },
  { origin: [0.25, 0.35, 0.86] as const, rest: [1.65, 0.1, 1.0] as const, ranked: [0.0, 0.55, 2.0] as const, delay: 0.05, rankedScale: 0.9 },
  { origin: [0.1, 0.15, 0.86] as const, rest: [1.4, -0.3, 1.3] as const, ranked: [-1.0, 0.4, 1.8] as const, delay: 0.1, rankedScale: 0.72 },
];
const TOP_CANDIDATE = BLOCKS[0].ranked;
const PANEL_POSITION = [0, 1.35, 1.4] as const;

const PENDING_RING_COLOR = new THREE.Color("#598CB7");
const VERIFIED_RING_COLOR = new THREE.Color("#078A88");
const PENDING_KEY = new THREE.Color("#598CB7");
const VERIFIED_KEY = new THREE.Color("#078A88");
const ACCEPTED_KEY = new THREE.Color("#09B993");
const VISION_KEY = new THREE.Color("#B6DAE0");

function pageMarkingTexture(): THREE.CanvasTexture {
  const canvas = document.createElement("canvas");
  canvas.width = 128;
  canvas.height = 160;
  const ctx = canvas.getContext("2d");
  if (ctx) {
    ctx.fillStyle = "#0A2A4A";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.strokeStyle = "rgba(182, 218, 224, 0.35)";
    ctx.lineWidth = 2;
    for (let y = 16; y < canvas.height - 12; y += 12) {
      ctx.beginPath();
      ctx.moveTo(10, y);
      ctx.lineTo(canvas.width - 10 - Math.random() * 30, y);
      ctx.stroke();
    }
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.needsUpdate = true;
  return texture;
}

const PARTICLE_COUNTS: Record<QualityTier, number> = { high: 900, balanced: 400, static: 0 };

/**
 * The Evidence Core (docs/landing/NOOR_EVIDENCE_CORE_DESIGN.md), built
 * and updated with plain, imperative Three.js — not
 * @react-three/fiber. See NOOR_CINEMATIC_TECHNICAL_ARCHITECTURE.md
 * §"Why raw Three.js" for the real, documented, upstream
 * @react-three/fiber v8 + Next.js 15 incompatibility this works around
 * (confirmed via multiple reproductions on this exact React 18.3.1 +
 * Next 15.x + r3f 8.17–8.18 combination — not a guess). Every scene's
 * geometry, camera keyframes, lighting logic, and particle role match
 * the original design exactly; only the rendering technique changed.
 */
export class EvidenceCoreScene {
  readonly scene = new THREE.Scene();
  readonly camera: THREE.PerspectiveCamera;
  readonly renderer: THREE.WebGLRenderer;

  private readonly documentGroup = new THREE.Group();
  private readonly verificationGroup = new THREE.Group();
  private readonly ring: THREE.Mesh;
  private readonly invalidObject: THREE.Mesh;
  private readonly reviewGroup = new THREE.Group();
  private readonly reviewPage: THREE.Mesh;
  private readonly findingMarker: THREE.Mesh;
  private readonly shackle: THREE.Mesh;
  private readonly pulseLight: THREE.PointLight;
  private readonly blocksGroup = new THREE.Group();
  private readonly blockMeshes: THREE.Group[] = [];
  private readonly beam: THREE.Mesh;
  private readonly panelGroup = new THREE.Group();
  private readonly panel: THREE.Mesh;
  private particles: THREE.Points | null = null;
  private particlesVisible = false;
  private readonly keyLight: THREE.DirectionalLight;
  private readonly ambientLight: THREE.HemisphereLight;
  private readonly targetPosition = new THREE.Vector3(0, 0.3, 6.5);
  private readonly targetLookAt = new THREE.Vector3(0, 0, 0);
  private readonly currentLookAt = new THREE.Vector3(0, 0, 0);
  private qualityTier: QualityTier;
  private disposed = false;

  constructor(canvas: HTMLCanvasElement, qualityTier: QualityTier) {
    this.qualityTier = qualityTier;
    this.scene.background = new THREE.Color("#040F1C");
    this.scene.fog = new THREE.Fog(0x040f1c, 6, 16);

    this.camera = new THREE.PerspectiveCamera(45, canvas.clientWidth / Math.max(1, canvas.clientHeight), 0.1, 30);
    this.camera.position.set(0, 0.3, 6.5);

    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: qualityTier === "high",
      alpha: false,
      powerPreference: "high-performance",
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, qualityTier === "high" ? 2 : 1.5));

    // Lighting — see docs/landing/NOOR_CINEMATIC_CONCEPT.md §Lighting system.
    this.ambientLight = new THREE.HemisphereLight("#0A2A4A", "#040F1C", 0.55);
    this.keyLight = new THREE.DirectionalLight("#598CB7", 1.1);
    this.keyLight.position.set(2, 3, 4);
    const rimLight = new THREE.DirectionalLight("#078A88", 0.35);
    rimLight.position.set(-3, 1, -2);
    this.scene.add(this.ambientLight, this.keyLight, rimLight);

    // Scene 1 — document stack (persistent object).
    const texture = pageMarkingTexture();
    for (let i = 0; i < LAYER_COUNT; i++) {
      const mesh = new THREE.Mesh(
        new THREE.PlaneGeometry(1.1, 1.5),
        new THREE.MeshStandardMaterial({ map: texture, roughness: 0.7, metalness: 0.05, side: THREE.DoubleSide })
      );
      mesh.position.set(0, 0, i * 0.065);
      mesh.rotation.z = (i % 2 === 0 ? 1 : -1) * 0.012;
      this.documentGroup.add(mesh);
    }
    this.scene.add(this.documentGroup);

    // Scene 2 — verification ring + invalid-path object.
    this.ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.95, 0.02, 16, 64),
      new THREE.MeshStandardMaterial({ transparent: true, opacity: 0, emissive: PENDING_RING_COLOR, emissiveIntensity: 0.3 })
    );
    this.ring.rotation.x = Math.PI / 2;
    this.invalidObject = new THREE.Mesh(
      new THREE.BoxGeometry(0.7, 0.9, 0.1),
      new THREE.MeshStandardMaterial({ color: "#6E9DA8", transparent: true, opacity: 0.55, roughness: 0.8 })
    );
    this.invalidObject.position.set(1.6, -0.1, 0.3);
    this.invalidObject.scale.setScalar(0.4);
    this.verificationGroup.add(this.ring, this.invalidObject);
    this.scene.add(this.verificationGroup);

    // Scene 3 — review gate.
    this.reviewPage = new THREE.Mesh(
      new THREE.PlaneGeometry(1.15, 1.55),
      new THREE.MeshStandardMaterial({ color: "#0F3A61", roughness: 0.65, side: THREE.DoubleSide })
    );
    this.reviewPage.position.set(0, 0, 0.3);
    this.findingMarker = new THREE.Mesh(
      new THREE.PlaneGeometry(0.4, 0.18),
      new THREE.MeshBasicMaterial({ color: "#598CB7", transparent: true, opacity: 0 })
    );
    this.findingMarker.position.set(0.15, 0.2, 0.32);
    const lockBody = new THREE.Mesh(
      new THREE.BoxGeometry(0.16, 0.12, 0.05),
      new THREE.MeshStandardMaterial({ color: "#B6DAE0", roughness: 0.4, metalness: 0.2 })
    );
    lockBody.position.set(0, 0.45, 0.6);
    this.shackle = new THREE.Mesh(
      new THREE.TorusGeometry(0.07, 0.015, 8, 24, Math.PI),
      new THREE.MeshStandardMaterial({ color: "#B6DAE0", roughness: 0.4, metalness: 0.2 })
    );
    this.shackle.position.set(0, 0.55, 0.6);
    this.shackle.rotation.x = Math.PI / 2;
    this.pulseLight = new THREE.PointLight("#09B993", 0, 2);
    this.pulseLight.position.set(-0.3, 0.3, 0.6);
    this.reviewGroup.add(this.reviewPage, this.findingMarker, lockBody, this.shackle, this.pulseLight);
    this.reviewGroup.position.set(0.2, 0.35, 0);
    this.scene.add(this.reviewGroup);

    // Scenes 4–5 — structured blocks + provenance threads + ranking.
    for (const block of BLOCKS) {
      const group = new THREE.Group();
      group.position.set(block.origin[0], block.origin[1], block.origin[2]);
      const mesh = new THREE.Mesh(
        new THREE.BoxGeometry(0.28, 0.2, 0.05),
        new THREE.MeshStandardMaterial({ color: "#97CECD", roughness: 0.5 })
      );
      group.add(mesh);
      this.blocksGroup.add(group);
      this.blockMeshes.push(group);
      this.blocksGroup.add(buildProvenanceThreadMesh(block.origin, block.rest, 0.55));
    }
    this.scene.add(this.blocksGroup);

    // Scene 5 — retrieval beam.
    this.beam = new THREE.Mesh(
      new THREE.PlaneGeometry(0.06, 1.2),
      new THREE.MeshBasicMaterial({
        color: "#B6DAE0",
        transparent: true,
        opacity: 0,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        side: THREE.DoubleSide,
      })
    );
    this.beam.rotation.x = Math.PI / 2;
    this.scene.add(this.beam);

    // Scene 6 — workspace panel.
    this.panel = new THREE.Mesh(
      new THREE.PlaneGeometry(1.3, 0.75),
      new THREE.MeshPhysicalMaterial({
        color: "#B6DAE0",
        transparent: true,
        opacity: 0,
        roughness: 0.1,
        transmission: 0.6,
        thickness: 0.1,
        side: THREE.DoubleSide,
      })
    );
    this.panelGroup.add(this.panel);
    this.panelGroup.add(
      buildProvenanceThreadMesh(
        [0, 0, 0],
        [TOP_CANDIDATE[0] - PANEL_POSITION[0], TOP_CANDIDATE[1] - PANEL_POSITION[1], TOP_CANDIDATE[2] - PANEL_POSITION[2]],
        0.4,
        "#B6DAE0"
      )
    );
    this.panelGroup.position.set(...PANEL_POSITION);
    this.scene.add(this.panelGroup);

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
      const r = 2.6 * (0.4 + Math.random() * 0.6);
      const y = (Math.random() - 0.5) * 1.6;
      positions[i * 3] = Math.cos(theta) * r;
      positions[i * 3 + 1] = y;
      positions[i * 3 + 2] = Math.sin(theta) * r;
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    const material = new THREE.PointsMaterial({
      size: 0.03,
      color: "#B6DAE0",
      transparent: true,
      opacity: 0.45,
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
    this.updateDocumentStack(progress);
    this.updateVerification(progress);
    this.updateReviewGate(progress, deltaSeconds);
    this.updateBlocks(progress);
    this.updateBeam(progress);
    this.updatePanel(progress);
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

  private updateDocumentStack(progress: number) {
    const resolved = activation(progress, 0, 0.1);
    this.documentGroup.children.forEach((child: THREE.Object3D, index: number) => {
      const spread = (1 - resolved) * 0.25;
      child.position.z = index * 0.065 + spread * (index - LAYER_COUNT / 2) * 0.4;
      child.position.y = spread * (index % 2 === 0 ? 0.05 : -0.05);
    });
  }

  private updateVerification(progress: number) {
    const ringIn = activation(progress, SCENE2.start, SCENE2.start + 0.03);
    const verified = activation(progress, SCENE2.start + 0.05, SCENE2.end - 0.01);
    const invalidApproach = activation(progress, SCENE2.start + 0.02, SCENE2.start + 0.09);

    this.verificationGroup.visible = ringIn > 0.01;
    this.verificationGroup.scale.setScalar(0.6 + ringIn * 0.4);

    const ringMaterial = this.ring.material as THREE.MeshStandardMaterial;
    ringMaterial.color.copy(PENDING_RING_COLOR).lerp(VERIFIED_RING_COLOR, verified);
    ringMaterial.emissive.copy(PENDING_RING_COLOR).lerp(VERIFIED_RING_COLOR, verified);
    ringMaterial.emissiveIntensity = 0.3 + verified * 0.9;
    ringMaterial.opacity = 0.35 + ringIn * 0.65;

    const stoppedX = 0.55;
    const startX = 1.6;
    this.invalidObject.position.x = startX - (startX - stoppedX) * Math.min(1, invalidApproach * 1.05);
    this.invalidObject.visible = invalidApproach > 0.01 && progress < SCENE2.end + 0.02;
  }

  private updateReviewGate(progress: number, deltaSeconds: number) {
    const detach = activation(progress, SCENE3.start, SCENE3.start + 0.04);
    const accepted = activation(progress, ACCEPT_THRESHOLD, ACCEPT_THRESHOLD + 0.02);
    const stillRelevant = activation(progress, SCENE3.start, SCENE3.end + 0.05);

    this.reviewGroup.visible = stillRelevant > 0.01;
    this.reviewPage.position.z = 0.3 + detach * 0.55;
    this.reviewPage.scale.setScalar(1 + detach * 0.35);

    const findingMaterial = this.findingMarker.material as THREE.MeshBasicMaterial;
    findingMaterial.opacity = detach * 0.55 * (1 - accepted);

    this.shackle.rotation.z = accepted * (Math.PI * 0.4);
    this.shackle.position.y = 0.55 + accepted * 0.08;

    const pulseAge = Math.min(1, (progress - ACCEPT_THRESHOLD) / 0.03);
    const pulseVisible = progress >= ACCEPT_THRESHOLD && pulseAge < 1;
    this.pulseLight.intensity = pulseVisible ? (1 - pulseAge) * 4 : 0;
    this.pulseLight.position.x += deltaSeconds * (pulseVisible ? 0.6 : 0);
  }

  private updateBlocks(progress: number) {
    const overallActive = activation(progress, SCENE4.start, SCENE5.end + 0.3);
    this.blocksGroup.visible = overallActive > 0.01;

    BLOCKS.forEach((block, index) => {
      const group = this.blockMeshes[index];
      const toRest = activation(progress, SCENE4.start + block.delay, SCENE4.start + block.delay + 0.08);
      const toRanked = activation(progress, SCENE5.start + block.delay, SCENE5.start + block.delay + 0.1);

      const midX = block.origin[0] + (block.rest[0] - block.origin[0]) * toRest;
      const midY = block.origin[1] + (block.rest[1] - block.origin[1]) * toRest;
      const midZ = block.origin[2] + (block.rest[2] - block.origin[2]) * toRest;

      group.position.set(
        midX + (block.ranked[0] - midX) * toRanked,
        midY + (block.ranked[1] - midY) * toRanked,
        midZ + (block.ranked[2] - midZ) * toRanked
      );
      const restScale = 0.4 + toRest * 0.6;
      group.scale.setScalar(restScale + (block.rankedScale - restScale) * toRanked);
    });
  }

  private updateBeam(progress: number) {
    const arrive = activation(progress, SCENE5.start + 0.02, SCENE5.start + 0.14);
    const stillActive = activation(progress, SCENE5.start, SCENE5.end + 0.3);
    this.beam.visible = stillActive > 0.01;
    const material = this.beam.material as THREE.MeshBasicMaterial;
    material.opacity = 0.4 * arrive;
    const startZ = 6.5;
    const endZ = TOP_CANDIDATE[2];
    this.beam.position.set(TOP_CANDIDATE[0], TOP_CANDIDATE[1], startZ + (endZ - startZ) * arrive);
  }

  private updatePanel(progress: number) {
    const condense = activation(progress, SCENE6.start, SCENE6.start + 0.08);
    const stillActive = activation(progress, SCENE6.start, SCENE6.end + 0.3);
    this.panelGroup.visible = stillActive > 0.01;
    this.panelGroup.scale.setScalar(0.5 + condense * 0.5);
    const material = this.panel.material as THREE.MeshPhysicalMaterial;
    material.opacity = 0.22 + condense * 0.28;
  }

  private updateLighting(progress: number) {
    const toVerified = activation(progress, 0.14, 0.28);
    const toAccepted = activation(progress, 0.28, 0.43);
    const toVision = activation(progress, 0.73, 0.86);
    const color = PENDING_KEY.clone().lerp(VERIFIED_KEY, toVerified).lerp(ACCEPTED_KEY, toAccepted).lerp(VISION_KEY, toVision);
    this.keyLight.color.copy(color);

    const warm = activation(progress, 0.86, 1);
    this.ambientLight.intensity = 0.55 + warm * 0.15;
  }

  private updateParticles(progress: number, deltaSeconds: number) {
    const shouldShow = (progress >= 0.58 && progress < 0.86) || progress >= 0.86;
    this.particlesVisible = shouldShow;
    if (this.particles) {
      this.particles.visible = shouldShow;
      if (shouldShow) this.particles.rotation.y += deltaSeconds * 0.03;
    }
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
