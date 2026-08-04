/**
 * The public landing's primary call-to-action target, resolved
 * server-side per request (LX-1.2 mission §22/§24). Shared between
 * `PublicShell.tsx` (which renders it) and `resolveLandingCta.ts`
 * (which computes it) so both sides of the contract stay in one
 * place.
 */
export interface PublicLandingCta {
  href: string;
  label: string;
}
