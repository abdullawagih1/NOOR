import { cn } from "../src/cn";

export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("rounded-md border border-border bg-canvas p-lg shadow-card", className)}>
      {children}
    </div>
  );
}

export function Section({
  title,
  description,
  children,
  className,
}: {
  title?: string;
  description?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("flex flex-col gap-md", className)}>
      {title ? (
        <div className="flex flex-col gap-xxs">
          <h2 className="text-xl font-semibold text-ink">{title}</h2>
          {description ? <p className="text-sm text-muted">{description}</p> : null}
        </div>
      ) : null}
      {children}
    </section>
  );
}

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  actions?: React.ReactNode;
}) {
  return (
    <header className="flex flex-col gap-sm border-b border-border pb-lg sm:flex-row sm:items-end sm:justify-between">
      <div className="flex flex-col gap-xxs">
        {eyebrow ? (
          <span className="text-xs font-semibold uppercase tracking-wide text-muted">{eyebrow}</span>
        ) : null}
        <h1 className="text-2xl font-semibold text-ink">{title}</h1>
        {description ? <p className="text-sm text-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex items-center gap-xs">{actions}</div> : null}
    </header>
  );
}
