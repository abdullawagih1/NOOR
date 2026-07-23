import "server-only";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { getServerEnv } from "@/lib/env/server";
import { getPublicEnv } from "@/lib/env/public";

/**
 * Service-role Supabase client. Bypasses RLS entirely — the database, not
 * this file, is what must be trusted to keep tenants apart, so every call
 * site using this client is responsible for its own authorization checks
 * (Security Agent requirement, Master Prompt §21).
 *
 * Never import this module from a "use client" file or expose its output to
 * the browser — the `server-only` import turns an accidental client import
 * into a build error, not just a broken convention.
 * SUPABASE_SERVICE_ROLE_KEY must only ever be read here. Sprint 0 has no
 * call sites for this yet — it exists so Sprint 1 workers and privileged
 * Route Handlers (e.g. signed upload URLs) have one audited place to
 * construct this client rather than each reinventing it.
 */
export function createServiceRoleClient() {
  const server = getServerEnv();
  const url = server.SUPABASE_URL ?? getPublicEnv().NEXT_PUBLIC_SUPABASE_URL;

  return createSupabaseClient(url, server.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
