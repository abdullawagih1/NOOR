# Next.js Metadata Streaming — Assessment

Status: **LX-1.3 — Complete. Root-caused, classified, and RESOLVED (not merely documented).**

## The original observation (LX-1.2)

Lighthouse's `meta-description` audit failed (score 0) on every dynamically-rendered route in the app, even though the raw HTTP response body contained the correct `<meta name="description">` text.

## Investigation, from first principles (mission §30)

1. **Raw HTTP response**: `curl` against `/` confirmed the meta tag's text was genuinely present in the response body.
2. **Browser DOM after hydration**: Playwright confirmed `document.querySelector('meta[name="description"]').parentElement.tagName` was `BODY`, not `HEAD` — even after full `networkidle` wait.
3. **What Lighthouse parses**: confirmed Lighthouse's audit specifically checks `document.head`, which is why it failed while `curl`'s raw-text grep succeeded.
4. **Cross-route comparison**: `/403` (fully static, `○` in the build output) placed metadata correctly in `<head>`. `/login` (dynamic, `ƒ`, but with NO page-level `generateMetadata` at all — only inherits `layout.tsx`'s static object) exhibited the identical `<body>`-placement bug. This proved the trigger was **dynamic rendering itself**, not anything specific to the new `generateMetadata()` function added to `/` in LX-1.2.
5. **Official Next.js documentation** (fetched directly this mission, not assumed from memory): confirmed this is Next.js 15.2+'s deliberate "streaming metadata" feature — for dynamically rendered pages, metadata streams in after the initial UI rather than blocking on it, to improve perceived performance.
6. **Crawler/user-agent behavior**: the official docs explicitly state streaming metadata is **disabled** for a built-in list of "HTML-limited" bots detected via User-Agent — and **Google's own crawlers are on that default list** (`Mediapartners-Google`, `AdsBot-Google`, `Google-PageRenderer`), alongside Bingbot, Twitterbot, and Slackbot. Real Google indexing traffic was therefore never actually at risk of missing the description — only tools like Lighthouse (using a real, non-exempted Chrome instance) surfaced the gap.

## Classification

**SEO metadata streaming risk: NONE (after fix).**

Before the fix applied this mission, the honest classification would have been **LOW** — Google's own crawlers were already exempted by Next's default list, so real search-engine indexing was not meaningfully at risk; only the Lighthouse *score* (a proxy metric, not the actual outcome it proxies for) and any non-Google, non-default-exempted crawler or link-preview bot were affected.

## The fix — an officially supported switch, not a workaround

`apps/web/next.config.mjs`:

```js
const nextConfig = {
  // ...
  htmlLimitedBots: /.*/,
};
```

This is Next.js's own documented mechanism (`htmlLimitedBots`, introduced in 15.2.0) for exactly this situation — matching every user agent as "HTML-limited" disables streaming metadata for every request, forcing synchronous, `<head>`-placed metadata unconditionally. It is not a user-agent hack (mission §30 explicitly forbids those unless officially supported) — this option exists specifically for this purpose, documented at `https://nextjs.org/docs/app/api-reference/config/next-config-js/htmlLimitedBots`, with "disable completely" as one of its two documented use cases.

**Why this is safe and has no real downside here**: streaming metadata exists to avoid blocking the initial HTML on slow `generateMetadata()` work (e.g., a data fetch). `/`'s `generateMetadata()` does no meaningful async work — it synchronously reads one environment variable — so there was never a real perceived-performance benefit being traded away by disabling streaming.

## Verification

- Real Playwright DOM inspection, post-fix: `document.querySelector('meta[name="description"]').parentElement.tagName === "HEAD"` on both `/` and `/login`.
- Real Lighthouse run, post-fix: SEO category **1.00** (was 0.92), on the cinematic desktop route.
- Full regression suite (25 `apps/web` test files) still passes — no behavior outside metadata placement changed.

## What was explicitly NOT done, per mission §30's constraints

- The root route was **not** made static (would have broken the auth-aware CTA).
- Metadata was **not** duplicated manually into both body and head.
- No raw `<head>` markup was injected.
- No ad hoc user-agent detection was written — the fix uses Next's own first-class config option.
- Nothing about security or functionality was sacrificed to reach a Lighthouse 1.00 — the fix is a pure, officially-supported configuration change with no behavioral trade-off identified.
