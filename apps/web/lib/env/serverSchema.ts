import { z } from "zod";

/**
 * The actual validation logic for server-only environment variables,
 * factored out of lib/env/server.ts so it's unit-testable directly:
 * `server-only` (imported only in server.ts) throws unconditionally
 * outside Next's own "react-server" bundler condition — including in a
 * plain Node/tsx test run — so this file must not import it. Application
 * code should still import from lib/env/server.ts, never from here
 * directly, so the guard stays in effect.
 */
const serverEnvSchema = z.object({
  SUPABASE_URL: z.string().url().optional(),
  SUPABASE_SERVICE_ROLE_KEY: z
    .string({ required_error: "SUPABASE_SERVICE_ROLE_KEY is required (see .env.example) — server-only, never NEXT_PUBLIC_" })
    .min(1, "SUPABASE_SERVICE_ROLE_KEY must not be empty"),
  WORKER_BASE_URL: z.string().url("WORKER_BASE_URL must be a valid URL").optional(),
  WORKER_INTERNAL_TOKEN: z
    .string()
    .min(32, "WORKER_INTERNAL_TOKEN must be at least 32 characters (generate with: openssl rand -hex 32)")
    .optional(),
});

export type ServerEnv = z.infer<typeof serverEnvSchema>;

export function parseServerEnv(): ServerEnv {
  return serverEnvSchema.parse({
    SUPABASE_URL: process.env.SUPABASE_URL,
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    WORKER_BASE_URL: process.env.WORKER_BASE_URL || undefined,
    WORKER_INTERNAL_TOKEN: process.env.WORKER_INTERNAL_TOKEN || undefined,
  });
}
