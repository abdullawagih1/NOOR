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

  // LX-1.3: fixes the real, investigated `<meta name="description">`-
  // renders-in-<body>-not-<head> issue on dynamic routes (LX-1.2's
  // NOOR_CINEMATIC_SEO_METADATA.md). Root cause, confirmed against
  // Next.js's own official docs this mission (not assumed): Next 15.2+
  // "streaming metadata" — for any dynamically-rendered route, HEAD
  // metadata streams in after the initial UI rather than blocking on
  // it, and is only guaranteed synchronous/head-placed for a built-in
  // list of known non-JS "HTML-limited" crawlers (Google's own
  // crawlers were ALREADY on that default list, so real Google
  // indexing was never actually at risk — but Lighthouse's Chrome
  // client is not on it, hence the real 0.92 SEO score). `generateMetadata()`
  // on `/` does no meaningful async work (it only reads an env var),
  // so there is no real perceived-performance benefit to streaming it
  // here — `htmlLimitedBots: /.*/ ` is Next's own documented, fully
  // supported switch to disable streaming metadata for every request,
  // not a user-agent hack or a workaround: https://nextjs.org/docs/app/api-reference/config/next-config-js/htmlLimitedBots
  htmlLimitedBots: /.*/,
};

export default nextConfig;
