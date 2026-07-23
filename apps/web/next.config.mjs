/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Vercel deployment target per Architecture Report §5. No server-role
  // Supabase key is ever read on the client — see lib/supabase/server.ts.
};

export default nextConfig;
