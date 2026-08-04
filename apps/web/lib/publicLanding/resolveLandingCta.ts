import { getAuthenticatedContext, toPostLoginAccess } from "@/lib/auth/context";
import { resolvePostLoginDestination } from "@/lib/auth/redirect";
import type { PublicLandingCta } from "./PublicLandingCta";

/**
 * The public landing's primary call-to-action, resolved once per
 * request on the server (LX-1.2 mission §22/§24) — never computed or
 * switched on the client, so there is no flash between "Sign in" and
 * "Open NOOR".
 *
 * An unauthenticated visitor gets the pre-LX-1.2 default. An
 * authenticated visitor — regardless of whether their membership
 * resolves cleanly — gets "Open NOOR" pointed at whatever
 * `resolvePostLoginDestination` would send them to on a fresh sign-in
 * (their workspace, or /access-denied): the same destination reached
 * by clicking "Sign in" while already authenticated, so the two paths
 * never disagree.
 */
export async function resolveLandingCta(): Promise<PublicLandingCta> {
  const access = await getAuthenticatedContext();
  if (access.kind === "unauthenticated") {
    return { href: "/login", label: "Sign in" };
  }
  return {
    href: resolvePostLoginDestination(undefined, toPostLoginAccess(access)),
    label: "Open NOOR",
  };
}
