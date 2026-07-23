import { forwardRef, useId } from "react";
import { cn } from "../src/cn";

export interface CheckboxProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string;
}

export const Checkbox = forwardRef<HTMLInputElement, CheckboxProps>(
  ({ label, id, className, ...props }, ref) => {
    const generatedId = useId();
    const inputId = id ?? generatedId;
    return (
      <label htmlFor={inputId} className="flex items-center gap-xs text-sm text-ink">
        <input
          ref={ref}
          id={inputId}
          type="checkbox"
          className={cn(
            "h-4 w-4 rounded-[0.25rem] border-border-strong text-primary focus:outline focus:outline-2 focus:outline-primary",
            className
          )}
          {...props}
        />
        {label}
      </label>
    );
  }
);
Checkbox.displayName = "Checkbox";

export interface RadioProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string;
}

export const Radio = forwardRef<HTMLInputElement, RadioProps>(
  ({ label, id, className, ...props }, ref) => {
    const generatedId = useId();
    const inputId = id ?? generatedId;
    return (
      <label htmlFor={inputId} className="flex items-center gap-xs text-sm text-ink">
        <input
          ref={ref}
          id={inputId}
          type="radio"
          className={cn("h-4 w-4 border-border-strong text-primary focus:outline focus:outline-2 focus:outline-primary", className)}
          {...props}
        />
        {label}
      </label>
    );
  }
);
Radio.displayName = "Radio";
