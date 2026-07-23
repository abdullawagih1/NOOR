import { createBrowserClient } from "@supabase/ssr";
import { getPublicEnv } from "@/lib/env/public";

/**
 * Browser-only Supabase client. Uses the public URL and anon key exclusively
 * — RLS is what protects data, not this client's privileges. Never import
 * SUPABASE_SERVICE_ROLE_KEY here; it does not exist in the browser bundle.
 */
export function createClient() {
  const env = getPublicEnv();
  return createBrowserClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
}
