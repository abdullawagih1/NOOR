import { createBrowserClient } from "@supabase/ssr";

/**
 * Browser-only Supabase client. Uses the public URL and anon key exclusively
 * — RLS is what protects data, not this client's privileges. Never import
 * SUPABASE_SERVICE_ROLE_KEY here; it does not exist in the browser bundle.
 */
export function createClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    throw new Error(
      "Supabase browser configuration missing. Set NEXT_PUBLIC_SUPABASE_URL " +
        "and NEXT_PUBLIC_SUPABASE_ANON_KEY (see .env.example)."
    );
  }

  return createBrowserClient(url, anonKey);
}
