import { forwardRef, useId } from "react";
import { cn } from "../src/cn";

export interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  label: string;
  hint?: string;
  error?: string;
}

export const Select = forwardRef<HTMLSelectElement, SelectProps>(
  ({ label, hint, error, id, className, children, ...props }, ref) => {
    const generatedId = useId();
    const selectId = id ?? generatedId;
    return (
      <div className="flex flex-col gap-xxs">
        <label htmlFor={selectId} className="text-sm font-medium text-body">
          {label}
        </label>
        <select
          ref={ref}
          id={selectId}
          className={cn(
            "w-full rounded-sm border border-border bg-canvas px-md py-xs text-base text-ink",
            "focus:border-primary focus:outline focus:outline-2 focus:outline-primary",
            error && "border-[var(--noor-state-critical-border)]",
            className
          )}
          aria-invalid={Boolean(error)}
          {...props}
        >
          {children}
        </select>
        {hint ? <p className="text-xs text-muted">{hint}</p> : null}
        {error ? (
          <p role="alert" className="text-xs text-[var(--noor-state-critical-fg)]">
            {error}
          </p>
        ) : null}
      </div>
    );
  }
);
Select.displayName = "Select";
