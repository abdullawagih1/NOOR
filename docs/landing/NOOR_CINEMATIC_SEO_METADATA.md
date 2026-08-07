# NOOR Cinematic Landing — SEO and Metadata

Status: **LX-1.3 — Complete. The LX-1.2 metadata-streaming limitation is now RESOLVED, not just documented.**

## LX-1.3 update — the streaming-metadata gap is fixed

The "known framework limitation" section below (LX-1.2's honest, unresolved finding) was investigated further from first principles this mission, including fetching current official Next.js documentation directly (not relying on memory). Root cause confirmed: Next.js 15.2+'s deliberate "streaming metadata" behavior for dynamic routes — which already exempts Google's own crawlers by default, so real search indexing was never actually at risk, only the Lighthouse score (a proxy metric) and any non-exempted tool/bot. **Fixed** via Next's own officially-documented `htmlLimitedBots: /.*/ ` config switch in `next.config.mjs` — not a workaround, not a route-architecture compromise, no sacrifice of the auth-aware CTA. Lighthouse SEO now reads a clean **1.00** (confirmed via a real post-fix run). Full investigation: `docs/landing/NOOR_NEXT_METADATA_STREAMING_ASSESSMENT.md`.

## What was added (LX-1.2)

- `apps/web/app/robots.ts` — the app's first real `robots.txt`. Disallows every workspace/auth-utility/internal-design route; allows `/`. Points `sitemap` at `/sitemap.xml`.
- `apps/web/app/sitemap.ts` — the app's first real `sitemap.xml`. Lists only `/` — the one genuinely public, indexable page.
- `apps/web/app/page.tsx::generateMetadata()` — page-specific title/description/canonical/Open Graph/Twitter metadata for `/`, varying the description slightly by experience (legacy vs. cinematic) while keeping the same truthful product claims either way.
- `export const metadata = { robots: { index: false, follow: false } }` added to `apps/web/app/design/cinematic-landing/page.tsx` — defense-in-depth: the route already 404s in a real production build by design, but it IS reachable on a Preview deployment, so it gets an explicit noindex there too.

## Truthful claims only

Neither landing variant claims regulatory approval, medical-device certification, guaranteed accuracy, zero hallucination, hospital partnerships, customer counts, or clinical outcomes — none of those claims exist anywhere in either landing's copy, confirmed by direct source review. The cinematic Product Vision scene keeps its "Synthetic demonstration — not clinical guidance" label unconditionally visible (not hidden after animation, not gated behind any interaction) — unchanged from LX-1.1.1, re-confirmed this mission. No structured data (`SoftwareApplication`/`Organization` schema) was added — not required by this mission and not worth the risk of an inaccurate or premature claim in machine-readable form.

## Social preview asset

Reused the existing, already-approved `apps/web/public/brand/social-preview.png` (1200×630, official NOOR logo lockup on a white ground, no fake dashboard, no debug UI, no unsupported claim) rather than generating a new cinematic-specific image. This is a deliberate scoping decision, not an oversight: the asset already satisfies every requirement mission §26 lists (official logo, approved palette, no fake dashboard, no debug UI, optimized size, local asset, already wired into `layout.tsx`'s metadata), and Production stays on the legacy experience for the duration of this mission — the social preview any real visitor's link-share would see is unaffected either way.

## A real, investigated framework limitation — not fixed, documented honestly

While measuring Lighthouse SEO scores against a real local production build, the `meta-description` audit failed (score 0) on `/` even though `curl`-ing the raw HTML response confirmed the tag's text was genuinely present in the document. Investigated rather than dismissed:

1. Confirmed via Playwright that `document.querySelector('meta[name="description"]')` finds the tag, but its **parent element is `<body>`, not `<head>`** — even after full page load and network idle. `document.head.querySelector(...)` (what Lighthouse's audit actually checks) correctly finds nothing.
2. Ruled out `generateMetadata` being `async` as the cause: making it a plain synchronous function had no effect.
3. Ruled out the explicit `dynamic = "force-dynamic"` export as the cause: removing it had no effect (the route stays dynamic automatically anyway, because `resolveLandingCta()` calls `cookies()` internally).
4. Confirmed the same misplacement already existed on `/login` — a route this mission never touched, which never had a page-level `generateMetadata` at all and only inherits `layout.tsx`'s static metadata. A fully **static** route (`/403`) does NOT exhibit this — its metadata correctly lands in `<head>`.

This isolates the real cause to Next.js 15.5.21's own "streaming metadata" behavior (`node_modules/next/dist/server/lib/streaming-metadata.js`) for **any dynamically-rendered route**, not to anything this mission's code does. The framework deliberately exempts known simple/non-JS-executing "HTML-limited" bot user agents from this path — those crawlers already receive synchronous, correctly `<head>`-placed metadata unconditionally, regardless of this route. The residual, unresolved risk is narrower than the raw Lighthouse score suggests, but is not proven zero for a JS-executing crawler that reads `document.head` strictly rather than the whole document.

**Why this wasn't chased further in LX-1.2:** at the time, a real fix appeared to require either ejecting `/` from dynamic rendering (which would break the auth-aware CTA) or a Next.js version change. **LX-1.3 found a third option**: Next.js's own `htmlLimitedBots` config already existed for exactly this purpose (it ships as of 15.2.0 — this app was already on 15.5.21, so the switch was available all along; LX-1.2 simply hadn't fetched the current official docs to find it). See the update at the top of this document and `NOOR_NEXT_METADATA_STREAMING_ASSESSMENT.md`.

## SEO score, honestly reported

**Post-LX-1.3 fix**: Lighthouse SEO now reads a clean `1.00` on the cinematic route, confirmed via a real Lighthouse run after applying `htmlLimitedBots: /.*/ ` in `next.config.mjs`. (Historical note, preserved for the record: prior to this fix, it consistently read `0.92` — one point, `meta-description` — on every dynamically-rendered route in this app, including `/login`; `/403`, fully static, already read `1.00`.)
