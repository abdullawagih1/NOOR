import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { sanitizeNextPath, resolvePostLoginDestination } from "@/lib/auth/redirect";
import { getAuthenticatedContext, toPostLoginAccess } from "@/lib/auth/context";

/**
 * Exchanges a Supabase auth code (magic link, email confirmation, password
 * reset) for a session. Password-based sign-in (lib/auth/actions.ts) does
 * not use this route, but it must exist for any flow that emails a link
 * back to the app.
 *
 * LX-1.2: resolves the same canonical post-login destination password
 * sign-in uses (mission §23) — a magic-link/reset-confirmation
 * exchange with no "next" must not default to "/" any more than a
 * password sign-in should.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const code = searchParams.get("code");
  const next = sanitizeNextPath(searchParams.get("next"));

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      const access = await getAuthenticatedContext();
      const destination = resolvePostLoginDestination(next, toPostLoginAccess(access));
      return NextResponse.redirect(`${origin}${destination}`);
    }
  }

  return NextResponse.redirect(`${origin}/login?error=${encodeURIComponent("Sign-in link is invalid or expired.")}`);
}
