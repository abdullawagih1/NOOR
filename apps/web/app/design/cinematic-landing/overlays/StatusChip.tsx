import type { SceneDefinition } from "../sceneConfig";

const STYLES: Record<SceneDefinition["status"], { bg: string; fg: string; border: string }> = {
  available: { bg: "rgba(9,185,147,0.12)", fg: "#5FE0BC", border: "rgba(9,185,147,0.4)" },
  "internal-evaluation": { bg: "rgba(4,80,146,0.18)", fg: "#9AC1F2", border: "rgba(69,141,215,0.4)" },
  "product-vision": { bg: "rgba(182,218,224,0.12)", fg: "#E7F4F6", border: "rgba(182,218,224,0.4)" },
};

export function StatusChip({ status, label }: { status: SceneDefinition["status"]; label: string }) {
  const style = STYLES[status];
  return (
    <span
      className="inline-flex items-center rounded-pill px-md py-xxs text-xs font-medium"
      style={{ backgroundColor: style.bg, color: style.fg, border: `1px solid ${style.border}` }}
    >
      {label}
    </span>
  );
}
