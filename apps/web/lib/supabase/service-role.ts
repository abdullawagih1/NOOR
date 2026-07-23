import { createClient as createSupabaseClient } from "@supabase/supabase-js";

/**
 * Service-role Supabase client. Bypasses RLS entirely — the database, not
 * this file, is what must be trusted to keep tenants apart, so every call
 * site using this client is responsible for its own authorization checks
 * (Security Agent requirement, Master Prompt §21).
 *
 * Never import this module from a "use client" file or expose its output to
 * the browser. SUPABASE_SERVICE_ROLE_KEY must only ever be read here.
 * Sprint 0 has no call sites for this yet — it exists so Sprint 1 workers
 * and privileged Route Handlers (e.g. signed upload URLs) have one audited
 * place to construct this client rather than each reinventing it.
 */
export function createServiceRoleClient() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "Supabase service-role configuration missing. Set SUPABASE_URL and " +
        "SUPABASE_SERVICE_ROLE_KEY as server-only environment variables " +
        "(see .env.example). This must never be read from a client component."
    );
  }

  return createSupabaseClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
