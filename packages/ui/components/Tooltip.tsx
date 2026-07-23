"use client";

import { cloneElement, useId, useState } from "react";
import { cn } from "../src/cn";

export function Tooltip({
  label,
  children,
  className,
}: {
  label: string;
  children: React.ReactElement;
  className?: string;
}) {
  const [visible, setVisible] = useState(false);
  const tooltipId = useId();

  return (
    <span
      className={cn("relative inline-flex", className)}
      onMouseEnter={() => setVisible(true)}
      onMouseLeave={() => setVisible(false)}
      onFocus={() => setVisible(true)}
      onBlur={() => setVisible(false)}
    >
      {cloneElement(children, { "aria-describedby": tooltipId } as Partial<unknown>)}
      {visible ? (
        <span
          id={tooltipId}
          role="tooltip"
          className="absolute bottom-full left-1/2 z-10 mb-xxs -translate-x-1/2 whitespace-nowrap rounded-sm bg-ink px-sm py-xxs text-xs text-canvas"
        >
          {label}
        </span>
      ) : null}
    </span>
  );
}
