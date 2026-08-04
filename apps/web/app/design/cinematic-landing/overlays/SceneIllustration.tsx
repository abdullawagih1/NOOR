import type { SceneDefinition } from "../sceneConfig";

/**
 * Lightweight inline SVG per scene for the static/reduced-motion path
 * (mission §29: "Use lightweight SVG or static Canvas snapshot") — no
 * rendered screenshot of the 3D scene, simple brand-token-colored
 * shapes only.
 */
export function SceneIllustration({ sceneKey }: { sceneKey: SceneDefinition["key"] }) {
  const common = { width: 64, height: 64, viewBox: "0 0 64 64", "aria-hidden": true } as const;
  switch (sceneKey) {
    case "trusted-source":
      return (
        <svg {...common}>
          {[0, 1, 2].map((i) => (
            <rect key={i} x={14 + i * 2} y={10 + i * 4} width="30" height="40" rx="3" stroke="#078A88" strokeWidth="1.5" fill="none" opacity={0.5 + i * 0.2} />
          ))}
        </svg>
      );
    case "secure-intake":
      return (
        <svg {...common}>
          <circle cx="32" cy="32" r="20" stroke="#078A88" strokeWidth="2" fill="none" />
          <rect x="24" y="22" width="16" height="20" rx="2" stroke="#B6DAE0" strokeWidth="1.5" fill="none" />
        </svg>
      );
    case "human-review":
      return (
        <svg {...common}>
          <rect x="20" y="30" width="12" height="10" rx="2" stroke="#B6DAE0" strokeWidth="2" fill="none" />
          <path d="M22 30 v-6 a4 4 0 0 1 8 0 v6" stroke="#B6DAE0" strokeWidth="2" fill="none" />
        </svg>
      );
    case "structured-knowledge":
      return (
        <svg {...common}>
          <rect x="10" y="14" width="18" height="36" rx="2" stroke="#078A88" strokeWidth="1.5" fill="none" />
          {[0, 1, 2].map((i) => (
            <g key={i}>
              <rect x={40} y={12 + i * 14} width="14" height="10" rx="2" stroke="#97CECD" strokeWidth="1.5" fill="none" />
              <line x1="28" y1={17 + i * 14} x2="40" y2={17 + i * 14} stroke="#078A88" strokeWidth="1" />
            </g>
          ))}
        </svg>
      );
    case "retrieval":
      return (
        <svg {...common}>
          {[0, 1, 2].map((i) => (
            <rect key={i} x={12 + i * 16} y={20 + i * 6} width="12" height={24 - i * 6} rx="2" stroke="#B6DAE0" strokeWidth="1.5" fill="none" opacity={1 - i * 0.25} />
          ))}
        </svg>
      );
    case "product-vision":
      return (
        <svg {...common}>
          <rect x="16" y="20" width="32" height="20" rx="3" stroke="#B6DAE0" strokeWidth="1.5" fill="none" opacity="0.6" />
          <line x1="32" y1="40" x2="32" y2="50" stroke="#078A88" strokeWidth="1.5" />
        </svg>
      );
    case "reverse-traceability":
    default:
      return (
        <svg {...common}>
          <path d="M46 32 H18 M26 24 L18 32 L26 40" stroke="#09B993" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
  }
}
