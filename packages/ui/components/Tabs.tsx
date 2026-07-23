"use client";

import { useState } from "react";
import { cn } from "../src/cn";

export interface TabItem {
  key: string;
  label: string;
  content: React.ReactNode;
}

export function Tabs({ items, defaultKey }: { items: TabItem[]; defaultKey?: string }) {
  const [active, setActive] = useState(defaultKey ?? items[0]?.key);
  const activeItem = items.find((item) => item.key === active);

  return (
    <div>
      <div role="tablist" className="flex gap-lg border-b border-border">
        {items.map((item) => (
          <button
            key={item.key}
            role="tab"
            aria-selected={active === item.key}
            onClick={() => setActive(item.key)}
            className={cn(
              "border-b-2 px-xxs pb-xs text-sm font-medium transition-colors",
              active === item.key ? "border-primary text-ink" : "border-transparent text-muted hover:text-ink"
            )}
          >
            {item.label}
          </button>
        ))}
      </div>
      <div role="tabpanel" className="pt-md">
        {activeItem?.content}
      </div>
    </div>
  );
}
