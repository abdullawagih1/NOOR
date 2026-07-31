/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Vercel deployment target per Architecture Report §5. No server-role
  // Supabase key is ever read on the client — see lib/supabase/server.ts.

  // @noor/ui ships TS/TSX source, not a pre-built bundle (same monorepo
  // pattern as @noor/clinical-schemas) — Next transpiles it directly.
  transpilePackages: ["@noor/ui"],

  // UX-1.1: the small circular "N" badge visible in local dev
  // screenshots is Next.js's own built-in development-mode indicator
  // (route/build status) — it never renders in `next build`/`next
  // start` output or a deployed Vercel Preview, so it was never part of
  // the actual product surface. Disabled here via the documented,
  // supported config flag so local screenshots taken during this
  // corrective mission represent the real, shipped experience.
  devIndicators: false,
};

export default nextConfig;
