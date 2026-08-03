"use client";

import { CheckCircle2, FileText, GitBranch, Eye, Link2 } from "lucide-react";
import Image from "next/image";

const STAGES_AR = [
  { label: "المصدر", icon: FileText },
  { label: "موثّق", icon: CheckCircle2 },
  { label: "تمت المراجعة", icon: Eye },
  { label: "مُهيكل", icon: GitBranch },
  { label: "قابل للتتبع", icon: Link2 },
] as const;

/**
 * RTL structural preview (mission §25 / §32.10) — isolated, scoped
 * dir="rtl" demonstration, matching the existing precedent in
 * apps/web/app/design-system/page.tsx rather than flipping the whole
 * app into a live RTL mode. English copy only; this validates
 * *structure* (unmirrored logo, semantic arrow direction, LTR-preserved
 * technical labels), not Arabic translation quality — that is an
 * explicit future localization acceptance gate, not claimed here.
 */
export function RtlStructuralPreview() {
  return (
    <section
      aria-labelledby="rtl-structural-preview-heading"
      className="flex flex-col gap-md rounded-md border border-border bg-canvas p-lg shadow-card"
      data-testid="prototype-rtl-structural-preview"
    >
      <div className="flex flex-col gap-xxs">
        <h2 id="rtl-structural-preview-heading" className="text-lg font-semibold text-ink">
          7. RTL Structural Preview
        </h2>
        <p className="text-sm text-muted">
          Isolated <code>dir=&quot;rtl&quot;</code> structural check — logo stays unmirrored, provenance direction
          reads right-to-left semantically (not auto-mirrored), and English technical labels (checksums) stay LTR
          inside the RTL layout. Synthetic structural Arabic labels only — full translation validation is a future
          localization gate, not claimed here.
        </p>
      </div>

      <div dir="rtl" lang="ar" className="flex flex-col gap-md rounded-sm border border-border bg-surface-soft p-lg font-arabic">
        <div className="flex items-center justify-between">
          <Image
            src="/brand/noor-logo-navigation.png"
            alt="Noor"
            width={121}
            height={100}
            className="h-8 w-auto"
            style={{ transform: "none" }}
            data-testid="rtl-logo"
          />
          <span className="rounded-sm bg-primary px-md py-xs text-sm font-medium text-on-primary">تسجيل الدخول</span>
        </div>

        <ol className="flex flex-wrap items-center gap-sm" aria-label="مراحل تدفق الأدلة">
          {STAGES_AR.map((stage, index) => {
            const Icon = stage.icon;
            return (
              <li key={stage.label} className="flex items-center gap-sm">
                <div className="flex flex-col items-center gap-xxs">
                  <span className="flex h-11 w-11 items-center justify-center rounded-pill border-2 border-accent bg-accent-soft text-accent-active">
                    <Icon size={20} aria-hidden="true" />
                  </span>
                  <span className="text-xs font-medium text-body">{stage.label}</span>
                </div>
                {index < STAGES_AR.length - 1 ? (
                  // Semantic direction, not CSS auto-mirroring: in RTL the
                  // reading flow moves right-to-left, so the connector and
                  // its arrowhead point toward the reader's left explicitly.
                  <span aria-hidden="true" className="text-muted">
                    &larr;
                  </span>
                ) : null}
              </li>
            );
          })}
        </ol>

        <div className="flex items-center gap-xs rounded-sm border border-border bg-canvas p-md">
          <span className="text-sm text-body">بصمة الملف</span>
          <span className="font-mono text-xs text-muted" dir="ltr" data-testid="rtl-checksum-ltr">
            sha256:8f3a…c19e
          </span>
        </div>
      </div>
    </section>
  );
}
