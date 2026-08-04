import type { MetadataRoute } from "next";

// Read directly, not via getPublicEnv() — same reasoning as layout.tsx's
// metadataBase: this route must keep building on environments with no
// Supabase env configured (mission §25).
const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";

/**
 * LX-1.2 mission §25 — the public route's first real robots.txt (none
 * existed before this mission). Disallows every workspace, auth-
 * utility, and internal design/prototype route; the design routes
 * already 404 in a real production build (unchanged gate), so this is
 * defense-in-depth for the one place they ARE reachable — a Vercel
 * Preview with NOOR_CINEMATIC_PREVIEW_ENABLED=true.
 */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        disallow: [
          "/login",
          "/forgot-password",
          "/update-password",
          "/auth/",
          "/403",
          "/access-denied",
          "/admin",
          "/admin/",
          "/clinician",
          "/clinician/",
          "/reviewer",
          "/reviewer/",
          "/quality",
          "/quality/",
          "/knowledge",
          "/knowledge/",
          "/design",
          "/design/",
          "/design-system",
        ],
      },
    ],
    sitemap: `${appUrl}/sitemap.xml`,
  };
}
