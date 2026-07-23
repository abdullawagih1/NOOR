"use client";

import { forwardRef, useId, useState } from "react";
import { cn } from "../src/cn";

const fieldBase =
  "w-full rounded-sm border border-border bg-canvas px-md py-xs text-base text-ink " +
  "placeholder:text-muted-soft focus:border-primary focus:outline focus:outline-2 " +
  "focus:outline-offset-0 focus:outline-primary disabled:bg-surface-soft disabled:text-muted";

export interface TextFieldProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string;
  hint?: string;
  error?: string;
}

export const TextInput = forwardRef<HTMLInputElement, TextFieldProps>(
  ({ label, hint, error, id, className, ...props }, ref) => {
    const generatedId = useId();
    const inputId = id ?? generatedId;
    const hintId = hint ? `${inputId}-hint` : undefined;
    const errorId = error ? `${inputId}-error` : undefined;

    return (
      <div className="flex flex-col gap-xxs">
        <label htmlFor={inputId} className="text-sm font-medium text-body">
          {label}
        </label>
        <input
          ref={ref}
          id={inputId}
          className={cn(fieldBase, error && "border-[var(--noor-state-critical-border)]", className)}
          aria-invalid={Boolean(error)}
          aria-describedby={cn(hintId, errorId) || undefined}
          {...props}
        />
        {hint ? (
          <p id={hintId} className="text-xs text-muted">
            {hint}
          </p>
        ) : null}
        {error ? (
          <p id={errorId} role="alert" className="text-xs text-[var(--noor-state-critical-fg)]">
            {error}
          </p>
        ) : null}
      </div>
    );
  }
);
TextInput.displayName = "TextInput";

export const PasswordInput = forwardRef<HTMLInputElement, TextFieldProps>((props, ref) => {
  const [visible, setVisible] = useState(false);
  return (
    <div className="relative">
      <TextInput ref={ref} type={visible ? "text" : "password"} {...props} />
      <button
        type="button"
        onClick={() => setVisible((v) => !v)}
        aria-label={visible ? "Hide password" : "Show password"}
        className="absolute right-3 top-[2.1rem] text-xs font-medium text-muted hover:text-ink"
      >
        {visible ? "Hide" : "Show"}
      </button>
    </div>
  );
});
PasswordInput.displayName = "PasswordInput";

export interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  label: string;
  hint?: string;
  error?: string;
}

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ label, hint, error, id, className, ...props }, ref) => {
    const generatedId = useId();
    const inputId = id ?? generatedId;
    return (
      <div className="flex flex-col gap-xxs">
        <label htmlFor={inputId} className="text-sm font-medium text-body">
          {label}
        </label>
        <textarea
          ref={ref}
          id={inputId}
          className={cn(fieldBase, "min-h-[6rem] resize-y", error && "border-[var(--noor-state-critical-border)]", className)}
          aria-invalid={Boolean(error)}
          {...props}
        />
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
Textarea.displayName = "Textarea";
