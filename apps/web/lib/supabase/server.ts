import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getPublicEnv } from "@/lib/env/public";

/**
 * Cookie-aware Supabase client for Server Components, Route Handlers, and
 * Server Actions. Runs as the request's authenticated (or anonymous) user —
 * RLS applies exactly as it would for the browser client. This is the
 * default for all application reads/writes (ADR 0003: RLS-first
 * authorization). Use lib/supabase/service-role.ts only for the narrow set
 * of operations that must legitimately bypass RLS.
 *
 * Server Components cannot set cookies (Next.js restriction); the `catch`
 * below is a documented no-op there, relied upon because middleware already
 * refreshes the session before the request reaches a Server Component.
 */
export async function createClient() {
  const env = getPublicEnv();
  const cookieStore = await cookies();

  return createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options)
          );
        } catch {
          // Called from a Server Component: middleware already refreshes
          // the session, so this is safe to ignore here.
        }
      },
    },
  });
}
