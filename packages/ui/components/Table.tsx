import { ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "../src/cn";

export function Table({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("overflow-x-auto rounded-md border border-border", className)}>
      <table className="w-full border-collapse text-left text-sm">{children}</table>
    </div>
  );
}

export function TableHead({ children }: { children: React.ReactNode }) {
  return <thead className="bg-surface-soft text-xs font-semibold uppercase tracking-wide text-muted">{children}</thead>;
}

export function TableBody({ children }: { children: React.ReactNode }) {
  return <tbody className="divide-y divide-border">{children}</tbody>;
}

export function TableRow({ children, className }: { children: React.ReactNode; className?: string }) {
  return <tr className={cn("hover:bg-surface-soft", className)}>{children}</tr>;
}

export function TableHeaderCell({ children }: { children: React.ReactNode }) {
  return <th scope="col" className="px-md py-sm">{children}</th>;
}

export function TableCell({ children, className }: { children: React.ReactNode; className?: string }) {
  return <td className={cn("px-md py-sm text-body", className)}>{children}</td>;
}

export function Pagination({
  page,
  pageCount,
  onPageChange,
}: {
  page: number;
  pageCount: number;
  onPageChange: (page: number) => void;
}) {
  return (
    <nav aria-label="Pagination" className="flex items-center justify-between gap-md text-sm text-muted">
      <button
        type="button"
        disabled={page <= 1}
        onClick={() => onPageChange(page - 1)}
        className="inline-flex items-center gap-xxs rounded-sm px-sm py-xxs disabled:opacity-40 hover:bg-surface-soft"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Previous
      </button>
      <span aria-live="polite">
        Page {page} of {pageCount}
      </span>
      <button
        type="button"
        disabled={page >= pageCount}
        onClick={() => onPageChange(page + 1)}
        className="inline-flex items-center gap-xxs rounded-sm px-sm py-xxs disabled:opacity-40 hover:bg-surface-soft"
      >
        Next <ChevronRight size={16} aria-hidden="true" />
      </button>
    </nav>
  );
}
