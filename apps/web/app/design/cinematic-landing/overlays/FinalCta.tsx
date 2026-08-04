import Link from "next/link";

/** Scene 7's final CTA (mission §19) — real routes only, no fabricated
 * demo/waitlist route. */
export function FinalCta() {
  return (
    <div className="flex flex-col items-start gap-md">
      <h2 className="max-w-xl font-semibold leading-[1.05] text-white text-[clamp(1.9rem,3.6vw,3.25rem)]">
        Build clinical intelligence on evidence you can trace.
      </h2>
      <div className="flex flex-wrap items-center gap-md">
        <Link
          href="/login"
          className="rounded-sm bg-primary px-lg py-sm text-base font-medium text-on-primary transition-colors hover:bg-primary-active focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          Sign in to NOOR
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
