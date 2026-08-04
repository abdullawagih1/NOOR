import type { SceneDefinition } from "./sceneConfig";

/**
 * Complete static illustrations for the reduced-motion / WebGL-
 * unavailable path (mission §23) — one per scene, each depicting the
 * scene's full resolved state (not an in-progress animation frame,
 * since there is no motion here to animate toward it). Every element
 * mission §23 lists as required is present: source document +
 * identity, the verification gateway with BOTH the valid and rejected
 * paths, the review gate's page/extracted-text/finding/accepted
 * state, the page-to-span-to-chunk relationship with persistent
 * connecting lines, ranked evidence 1–3 with a human-judgment
 * indicator, the product-vision workspace, and the complete six-layer
 * reverse-traceability diagram. Brand tokens only, no raster image, no
 * external asset.
 */
export function ReducedMotionIllustration({ sceneKey }: { sceneKey: SceneDefinition["key"] }) {
  const frame = { viewBox: "0 0 400 320", "aria-hidden": true, className: "h-auto w-full max-w-md" } as const;

  switch (sceneKey) {
    case "trusted-source":
      return (
        <svg {...frame}>
          {[0, 1, 2, 3].map((i) => (
            <rect key={i} x={90 - i * 4} y={40 + i * 10} width="180" height="220" rx="8" fill="#0C3258" stroke="#1FD6D2" strokeOpacity={0.35 + i * 0.12} strokeWidth="2" />
          ))}
          <rect x={78} y={220} width="204" height="60" rx="8" fill="#0C3258" stroke="#8FF0DA" strokeWidth="2.5" />
          {[0, 1, 2, 3, 4].map((i) => (
            <line key={i} x1={98} y1={70 + i * 16} x2={252 - (i % 2) * 20} y2={70 + i * 16} stroke="#B9DFE6" strokeOpacity="0.5" strokeWidth="2" />
          ))}
          <circle cx="230" cy="250" r="16" fill="#0C3258" stroke="#2FE8B8" strokeWidth="2" />
          <path d="M223 250 l5 5 l10 -12" stroke="#2FE8B8" strokeWidth="2.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
          <text x="98" y="260" fill="#D7F0F3" fontSize="13" fontFamily="inherit">Source registered — verified</text>
        </svg>
      );

    case "secure-intake":
      return (
        <svg {...frame}>
          <circle cx="150" cy="160" r="95" fill="none" stroke="#1FD6D2" strokeWidth="3" />
          <rect x="118" y="110" width="64" height="90" rx="6" fill="#0C3258" stroke="#8FF0DA" strokeWidth="2.5" />
          <circle cx="150" cy="235" r="14" fill="#0C3258" stroke="#2FE8B8" strokeWidth="2" />
          <path d="M144 235 l4 4 l8 -10" stroke="#2FE8B8" strokeWidth="2.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
          <text x="96" y="270" fill="#D7F0F3" fontSize="12">Valid source — continues</text>

          <rect x="300" y="130" width="46" height="62" rx="5" fill="#3A2A28" stroke="#C4574A" strokeWidth="2" opacity="0.85" />
          <line x1="308" y1="145" x2="336" y2="175" stroke="#C4574A" strokeWidth="3" strokeLinecap="round" />
          <line x1="336" y1="145" x2="308" y2="175" stroke="#C4574A" strokeWidth="3" strokeLinecap="round" />
          <text x="278" y="215" fill="#E3A79C" fontSize="12">Invalid source — stopped</text>
          <line x1="248" y1="160" x2="290" y2="160" stroke="#C4574A" strokeWidth="2" strokeDasharray="4 4" />
        </svg>
      );

    case "human-review":
      return (
        <svg {...frame}>
          <rect x="30" y="40" width="140" height="200" rx="6" fill="#0C3258" stroke="#7FA6D4" strokeWidth="2" />
          <text x="42" y="30" fill="#B9DFE6" fontSize="12">Original page</text>
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <line key={i} x1="46" y1={65 + i * 22} x2={150 - (i % 2) * 24} y2={65 + i * 22} stroke="#B9DFE6" strokeOpacity="0.45" strokeWidth="2" />
          ))}
          <rect x="46" y="125" width="90" height="20" rx="3" fill="#7FA6D4" fillOpacity="0.35" stroke="#7FA6D4" strokeWidth="1.5" />

          <rect x="210" y="40" width="140" height="200" rx="6" fill="#0C3258" stroke="#1FD6D2" strokeWidth="2" />
          <text x="222" y="30" fill="#8FF0DA" fontSize="12">Extracted representation</text>
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <line key={i} x1="226" y1={65 + i * 22} x2={330 - (i % 3) * 18} y2={65 + i * 22} stroke="#8FF0DA" strokeOpacity="0.45" strokeWidth="2" />
          ))}
          <rect x="226" y="125" width="90" height="20" rx="3" fill="#2FE8B8" fillOpacity="0.25" stroke="#2FE8B8" strokeWidth="1.5" />

          <circle cx="200" cy="280" r="20" fill="#0C3258" stroke="#2FE8B8" strokeWidth="2.5" />
          <path d="M191 280 l6 6 l12 -14" stroke="#2FE8B8" strokeWidth="3" fill="none" strokeLinecap="round" strokeLinejoin="round" />
          <text x="140" y="310" fill="#8FF0DA" fontSize="12">Reviewer decision — accepted, path unlocked</text>
        </svg>
      );

    case "structured-knowledge":
      return (
        <svg {...frame}>
          <rect x="30" y="30" width="130" height="260" rx="6" fill="#0C3258" stroke="#7FA6D4" strokeWidth="2" />
          {[0, 1, 2].map((i) => (
            <rect key={i} x="42" y={60 + i * 80} width="106" height="46" rx="4" fill="#1FD6D2" fillOpacity="0.22" stroke="#1FD6D2" strokeWidth="1.5" />
          ))}
          {[0, 1, 2].map((i) => (
            <g key={i}>
              <line x1="160" y1={83 + i * 80} x2="245" y2={83 + i * 80} stroke="#1FD6D2" strokeWidth="2" />
              <rect x="248" y={62 + i * 80} width="110" height="42" rx="5" fill="#0C3258" stroke="#5BE0DC" strokeWidth="2" />
              <text x="262" y={87 + i * 80} fill="#D7F0F3" fontSize="11">Chunk {i + 1}</text>
            </g>
          ))}
          <text x="42" y="310" fill="#B9DFE6" fontSize="12">Every chunk keeps its line back to the page</text>
        </svg>
      );

    case "retrieval":
      return (
        <svg {...frame}>
          <path d="M20 160 L70 160" stroke="#D7F0F3" strokeWidth="2.5" markerEnd="url(#arrow)" />
          <defs>
            <marker id="arrow" markerWidth="8" markerHeight="8" refX="4" refY="4" orient="auto">
              <path d="M0 0 L8 4 L0 8 Z" fill="#D7F0F3" />
            </marker>
          </defs>
          <text x="16" y="145" fill="#D7F0F3" fontSize="11">Query</text>

          {[0, 1, 2].map((i) => (
            <g key={i}>
              <rect x={290 - i * 20} y={40 + i * 90} width={120 - i * 12} height="70" rx="6" fill="#0C3258" stroke="#2FE8B8" strokeWidth={2.4 - i * 0.4} />
              <circle cx={300 - i * 20} cy={62 + i * 90} r="13" fill="#2FE8B8" fillOpacity="0.9" />
              <text x={294 - i * 20} y={67 + i * 90} fill="#04261F" fontSize="13" fontWeight="700">{i + 1}</text>
              <text x={252 - i * 20} y={95 + i * 90} fill="#B9DFE6" fontSize="10">relevance {(0.9 - i * 0.18).toFixed(2)}</text>
            </g>
          ))}
          <line x1="90" y1="160" x2="180" y2="75" stroke="#1FD6D2" strokeWidth="1.5" strokeDasharray="3 4" />
          <line x1="90" y1="160" x2="180" y2="160" stroke="#1FD6D2" strokeWidth="1.5" strokeDasharray="3 4" />
          <line x1="90" y1="160" x2="180" y2="245" stroke="#1FD6D2" strokeWidth="1.5" strokeDasharray="3 4" />
          <text x="60" y="290" fill="#8FF0DA" fontSize="12">Human relevance judgment · exact source location</text>
        </svg>
      );

    case "product-vision":
      return (
        <svg {...frame}>
          <rect x="60" y="40" width="280" height="90" rx="8" fill="#0C3258" stroke="#D7F0F3" strokeWidth="2" />
          <text x="76" y="70" fill="#D7F0F3" fontSize="13">&ldquo;Synthetic evidence statement, non-clinical&rdquo;</text>
          <rect x="76" y="86" width="120" height="18" rx="9" fill="#D7F0F3" fillOpacity="0.16" stroke="#D7F0F3" strokeWidth="1.2" />
          <text x="84" y="99" fill="#D7F0F3" fontSize="10">Product vision</text>

          {[0, 1, 2].map((i) => (
            <g key={i}>
              <line x1={140 + i * 60} y1="130" x2={140 + i * 60} y2="180" stroke="#1FD6D2" strokeWidth="2" />
              <rect x={100 + i * 60} y="180" width="80" height="46" rx="6" fill="#0C3258" stroke="#5BE0DC" strokeWidth="1.8" />
              <text x={112 + i * 60} y="207" fill="#B9DFE6" fontSize="10">Evidence {i + 1}</text>
            </g>
          ))}
          <text x="76" y="270" fill="#8FF0DA" fontSize="12">Claims stay traceable. Human authority stays explicit.</text>
        </svg>
      );

    case "reverse-traceability":
    default: {
      const layers = [
        "Intelligence statement",
        "Supporting evidence",
        "Retrieved chunk",
        "Exact source span",
        "Original page",
        "Trusted guideline",
      ];
      return (
        <svg {...frame} viewBox="0 0 400 380">
          {layers.map((label, i) => (
            <g key={label}>
              <rect x="40" y={20 + i * 58} width="320" height="42" rx="6" fill="#0C3258" stroke="#2FE8B8" strokeOpacity={0.5 + i * 0.08} strokeWidth="2" />
              <circle cx="62" cy={41 + i * 58} r="8" fill="#2FE8B8" fillOpacity={0.4 + i * 0.1} />
              <text x="82" y={46 + i * 58} fill="#D7F0F3" fontSize="13">{label}</text>
              {i < layers.length - 1 ? (
                <line x1="62" y1={62 + i * 58} x2="62" y2={78 + i * 58} stroke="#2FE8B8" strokeWidth="2" />
              ) : null}
            </g>
          ))}
        </svg>
      );
    }
  }
}
