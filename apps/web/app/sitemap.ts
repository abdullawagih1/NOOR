import type { MetadataRoute } from "next";

const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";

/**
 * LX-1.2 mission §25 — the public route's first real sitemap.xml (none
 * existed before this mission). Lists only "/" — the one genuinely
 * public, indexable page. `/login` and every workspace/design route
 * are deliberately excluded (see app/robots.ts's disallow list) —
 * they carry no independent SEO value and some are auth/permission
 * gated for every visitor anyway.
 */
export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: `${appUrl}/`,
      changeFrequency: "weekly",
      priority: 1,
    },
  ];
}
