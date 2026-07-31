import Image from "next/image";
import Link from "next/link";

/**
 * Two-column authentication composition (UX-1.1 §8) — a white brand
 * panel carrying the full logo at a size where both the wordmark and
 * the descriptor stay legible, next to a soft-cyan panel holding the
 * actual form. Used by /login only; /forgot-password and
 * /update-password use the simpler AuthCardShell below, since they are
 * secondary flows off the main sign-in surface, not the primary
 * first-impression screen.
 */
export function AuthSplitShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col lg:flex-row">
      <div className="flex flex-1 flex-col items-center justify-center gap-lg bg-canvas p-xl text-center lg:max-w-md">
        <Link href="/" aria-label="Noor home" className="rounded-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent">
          <Image
            src="/brand/noor-logo-primary.png"
            alt="Noor — Clinical Intelligence"
            width={226}
            height={200}
            className="h-40 w-auto sm:h-48"
            priority
          />
        </Link>
        <div className="h-1 w-16 rounded-pill bg-brand-gradient" aria-hidden="true" />
        <p className="max-w-xs text-sm text-muted">
          Evidence-governed knowledge operations for clinical teams — controlled review, deterministic
          extraction, and auditable processing.
        </p>
      </div>
      <div className="flex flex-1 items-center justify-center bg-surface-soft p-xl">
        <div className="w-full max-w-sm">{children}</div>
      </div>
    </div>
  );
}

/**
 * Centered single-card shell for the secondary auth flows (forgot/
 * update password) — same light system, a compact logo, no full split
 * composition (these aren't the product's first impression).
 */
export function AuthCardShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-lg bg-surface-soft p-xl">
      <Link href="/" aria-label="Noor home" className="rounded-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent">
        <Image
          src="/brand/noor-logo-navigation.png"
          alt="Noor — Clinical Intelligence"
          width={121}
          height={100}
          className="h-12 w-auto"
        />
      </Link>
      <div className="w-full max-w-sm">{children}</div>
    </div>
  );
}
