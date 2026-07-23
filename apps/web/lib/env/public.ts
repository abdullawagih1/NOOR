import { z } from "zod";

/**
 * Browser-safe environment. Every value here is genuinely public — it ends
 * up in the client bundle regardless of validation, so nothing server-only
 * may ever be added to this schema (see lib/env/server.ts instead).
 *
 * `getPublicEnv()` is a function, not a pre-parsed constant, on purpose:
 * this repo relies on the throw happening at request/render time, not at
 * module import time, so that routes which never construct a Supabase
 * client (the static ones: /, /403, /access-denied, /design-system) keep
 * building successfully even when no Supabase project is configured yet.
 * Eagerly parsing at import time would break that property.
 */
const publicEnvSchema = z.object({
  NEXT_PUBLIC_APP_URL: z.string().url().default("http://localhost:3000"),
  NEXT_PUBLIC_SUPABASE_URL: z
    .string({ required_error: "NEXT_PUBLIC_SUPABASE_URL is required (see .env.example)" })
    .url("NEXT_PUBLIC_SUPABASE_URL must be a valid URL"),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z
    .string({ required_error: "NEXT_PUBLIC_SUPABASE_ANON_KEY is required (see .env.example)" })
    .min(1, "NEXT_PUBLIC_SUPABASE_ANON_KEY must not be empty"),
});

export type PublicEnv = z.infer<typeof publicEnvSchema>;

export function getPublicEnv(): PublicEnv {
  return publicEnvSchema.parse({
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  });
}
