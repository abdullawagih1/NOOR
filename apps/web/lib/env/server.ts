import "server-only";

/**
 * Server-only environment entry point. The `server-only` import makes any
 * accidental "use client" import of this module a build-time error, not
 * just a broken convention — see docs/operations/environment-variables.md.
 * Validation logic itself lives in lib/env/serverSchema.ts (which must
 * never import "server-only", so it stays unit-testable outside Next's
 * bundler) — this file only re-exports it behind the guard.
 */
export { parseServerEnv as getServerEnv, type ServerEnv } from "./serverSchema";
