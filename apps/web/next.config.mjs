/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Vercel deployment target per Architecture Report §5. No server-role
  // Supabase key is ever read on the client — see lib/supabase/server.ts.

  // @noor/ui ships TS/TSX source, not a pre-built bundle (same monorepo
  // pattern as @noor/clinical-schemas) — Next transpiles it directly.
  transpilePackages: ["@noor/ui"],
};

export default nextConfig;
