"use client";

import { Search } from "lucide-react";
import { useState } from "react";

export interface ClinicalQuestionBarProps {
  placeholder?: string;
  onSubmit?: (question: string) => void;
  disabled?: boolean;
}

/**
 * Shell only — the pill-shaped question surface DESIGN.md's warmth
 * direction calls for, adapted from a search bar to a clinical question
 * prompt. No retrieval/generation wiring; onSubmit is a plain callback the
 * Sprint 1 RAG integration will replace.
 */
export function ClinicalQuestionBar({ placeholder = "Ask a clinical question…", onSubmit, disabled }: ClinicalQuestionBarProps) {
  const [value, setValue] = useState("");

  return (
    <form
      role="search"
      onSubmit={(event) => {
        event.preventDefault();
        if (value.trim()) onSubmit?.(value.trim());
      }}
      className="flex items-center gap-xs rounded-pill border border-border bg-canvas px-lg py-sm shadow-card focus-within:border-primary"
    >
      <label htmlFor="clinical-question" className="sr-only">
        Clinical question
      </label>
      <input
        id="clinical-question"
        type="text"
        value={value}
        onChange={(event) => setValue(event.target.value)}
        placeholder={placeholder}
        disabled={disabled}
        className="min-w-0 flex-1 border-none bg-transparent text-base text-ink placeholder:text-muted-soft focus:outline-none"
      />
      <button
        type="submit"
        disabled={disabled}
        aria-label="Ask Noor"
        className="flex h-11 w-11 shrink-0 items-center justify-center rounded-pill bg-primary text-on-primary hover:bg-primary-active disabled:opacity-50"
      >
        <Search size={18} aria-hidden="true" />
      </button>
    </form>
  );
}
