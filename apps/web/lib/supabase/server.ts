import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

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
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    throw new Error(
      "Supabase server configuration missing. Set NEXT_PUBLIC_SUPABASE_URL " +
        "and NEXT_PUBLIC_SUPABASE_ANON_KEY (see .env.example)."
    );
  }

  const cookieStore = await cookies();

  return createServerClient(url, anonKey, {
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
