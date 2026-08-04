import Link from "next/link";
import type { PublicLandingCta } from "@/lib/publicLanding/PublicLandingCta";

/**
 * Scene 7's final CTA (mission §19) — real routes only, no fabricated
 * demo/waitlist route. `cta` is resolved server-side per request
 * (LX-1.2 mission §22/§24): "Sign in to NOOR" for an unauthenticated
 * visitor, "Open NOOR" pointed straight at the caller's workspace when
 * already authenticated — never a hardcoded "/login".
 */
export function FinalCta({ cta }: { cta: PublicLandingCta }) {
  const label = cta.href === "/login" ? "Sign in to NOOR" : "Open NOOR";
  return (
    <div className="flex flex-col items-start gap-md">
      <h2 className="max-w-xl font-semibold leading-[1.05] text-white text-[clamp(1.9rem,3.6vw,3.25rem)]">
        Build clinical intelligence on evidence you can trace.
      </h2>
      <div className="flex flex-wrap items-center gap-md">
        <Link
          href={cta.href}
          className="rounded-sm bg-primary px-lg py-sm text-base font-medium text-on-primary transition-colors hover:bg-primary-active focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          {label}
        </Link>
        <a
          href="#scene-1"
          className="text-sm font-medium text-white/80 underline-offset-4 hover:text-white hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          Explore the evidence journey again
        </a>
      </div>
    </div>
  );
}
