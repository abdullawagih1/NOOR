import Image from "next/image";
import Link from "next/link";
import type { PublicLandingCta } from "@/lib/publicLanding/PublicLandingCta";

export type { PublicLandingCta };

const DEFAULT_CTA: PublicLandingCta = { href: "/login", label: "Sign in" };

/**
 * Shared chrome for every public, non-workspace surface (landing, 403,
 * access-denied, not-found, general error) — one header/footer
 * definition, not copy-pasted per page (UX-1.1 §12). Auth pages
 * (login/forgot-password/update-password) use AuthShell instead, since
 * their brand panel already serves the header's role.
 */
export function PublicHeader({ showSignIn = true, cta }: { showSignIn?: boolean; cta?: PublicLandingCta }) {
  const resolvedCta = cta ?? DEFAULT_CTA;
  return (
    <header className="border-b border-border bg-canvas">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-lg py-sm">
        <Link
          href="/"
          aria-label="Noor home"
          className="inline-flex items-center rounded-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
        >
          <Image
            src="/brand/noor-logo-navigation.png"
            alt="Noor — Clinical Intelligence"
            width={121}
            height={100}
            className="h-9 w-auto sm:h-10"
            priority
          />
        </Link>
        {showSignIn ? (
          <Link
            href={resolvedCta.href}
            className="rounded-sm bg-primary px-md py-xs text-sm font-medium text-on-primary transition-colors hover:bg-primary-active focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            {resolvedCta.label}
          </Link>
        ) : null}
      </div>
    </header>
  );
}

export function PublicFooter({ cta }: { cta?: PublicLandingCta }) {
  const resolvedCta = cta ?? DEFAULT_CTA;
  const year = new Date().getFullYear();
  return (
    <footer className="border-t border-border bg-surface-soft">
      <div className="mx-auto flex max-w-6xl flex-col items-center gap-xs px-lg py-lg text-center text-sm text-muted sm:flex-row sm:justify-between sm:text-start">
        <p>NOOR — Clinical Intelligence OS</p>
        <p>© {year} NOOR</p>
        <Link href={resolvedCta.href} className="text-primary hover:underline">
          {resolvedCta.label}
        </Link>
      </div>
    </footer>
  );
}

export function PublicShell({
  children,
  showSignIn = true,
  cta,
}: {
  children: React.ReactNode;
  showSignIn?: boolean;
  cta?: PublicLandingCta;
}) {
  return (
    <div className="flex min-h-screen flex-col bg-canvas">
      <PublicHeader showSignIn={showSignIn} cta={cta} />
      <main className="flex-1">{children}</main>
      <PublicFooter cta={cta} />
    </div>
  );
}
