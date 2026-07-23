import { forwardRef } from "react";
import { cn } from "../src/cn";

export type ButtonVariant = "primary" | "secondary" | "text" | "danger";
export type ButtonSize = "md" | "sm";

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

const base =
  "inline-flex items-center justify-center gap-xs rounded-sm font-medium transition-colors " +
  "disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 " +
  "focus-visible:outline-offset-2 focus-visible:outline-primary";

const variants: Record<ButtonVariant, string> = {
  primary: "bg-primary text-on-primary hover:bg-primary-active",
  secondary: "bg-canvas text-ink border border-border-strong hover:bg-surface-soft",
  text: "bg-transparent text-ink hover:bg-surface-soft",
  danger: "bg-transparent text-[var(--noor-state-critical-fg)] border border-[var(--noor-state-critical-border)] hover:bg-[var(--noor-state-critical-bg)]",
};

const sizes: Record<ButtonSize, string> = {
  md: "h-11 px-lg text-base",
  sm: "h-9 px-md text-sm",
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ variant = "primary", size = "md", className, ...props }, ref) => (
    <button ref={ref} className={cn(base, variants[variant], sizes[size], className)} {...props} />
  )
);
Button.displayName = "Button";

export interface IconButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  label: string;
  variant?: ButtonVariant;
}

export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(
  ({ label, variant = "text", className, children, ...props }, ref) => (
    <button
      ref={ref}
      aria-label={label}
      title={label}
      className={cn(
        "inline-flex h-10 w-10 items-center justify-center rounded-pill transition-colors",
        "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        variant === "primary" ? "bg-primary text-on-primary hover:bg-primary-active" : "text-body hover:bg-surface-soft",
        className
      )}
      {...props}
    >
      {children}
    </button>
  )
);
IconButton.displayName = "IconButton";
