import { FileText } from "lucide-react";
import { Card } from "../Card";

export interface CitationCardProps {
  sourceTitle: string;
  pageReference: string;
  excerpt: string;
  className?: string;
}

/** Mocked-data display shell only — no retrieval wiring (Sprint 1 scope). */
export function CitationCard({ sourceTitle, pageReference, excerpt, className }: CitationCardProps) {
  return (
    <Card className={className}>
      <div className="flex items-start gap-sm">
        <FileText size={18} className="mt-0.5 shrink-0 text-muted" aria-hidden="true" />
        <div className="flex flex-col gap-xxs">
          <p className="text-sm font-semibold text-ink">{sourceTitle}</p>
          <p className="text-xs text-muted">{pageReference}</p>
          <blockquote className="mt-xxs border-l-2 border-border-strong pl-sm text-sm italic text-body">
            {excerpt}
          </blockquote>
        </div>
      </div>
    </Card>
  );
}
