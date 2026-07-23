import { cn } from "../src/cn";

export interface WorkspaceNavItem {
  label: string;
  href: string;
  active?: boolean;
}

/** Presentational only — the caller decides which items to include based on permissions, and which is active. */
export function WorkspaceNav({ items }: { items: WorkspaceNavItem[] }) {
  return (
    <nav aria-label="Workspaces" className="flex flex-wrap gap-xs">
      {items.map((item) => (
        <a
          key={item.href}
          href={item.href}
          aria-current={item.active ? "page" : undefined}
          className={cn(
            "rounded-pill px-md py-xxs text-sm font-medium transition-colors",
            item.active ? "bg-primary-soft text-primary-active" : "text-muted hover:bg-surface-soft hover:text-ink"
          )}
        >
          {item.label}
        </a>
      ))}
    </nav>
  );
}
